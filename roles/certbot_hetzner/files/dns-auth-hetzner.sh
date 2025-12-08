#!/usr/bin/env bash
# Hetzner (hcloud) DNS-01 hook for Certbot — unified script (SIMPLE MODE)
#
# This version intentionally OVERWRITES the TXT RRSet for _acme-challenge.
# It does NOT try to read/merge existing values. Use this only when you
# request/renew ONE authorization at a time for a zone (e.g., run certbot
# separately for apex and wildcard, not both in one command).
#
# Behavior
#   auth   : sets RRSet to exactly [ "${CERTBOT_VALIDATION}" ]
#            (tries a create with TTL first; then set-records)
#   cleanup: sets RRSet to [] which deletes it
#
# Requirements: hcloud CLI configured (token/context), jq. dig is optional.
#
# Usage examples:
#   export HCLOUD_ZONE="example.com"        # zone name or ID
#   export HCLOUD_TTL="60"                 # optional; default 60
#   # Request A SINGLE NAME per run (e.g., only example.com OR only *.example.com)
#   sudo -E certbot certonly \
#     --manual --preferred-challenges dns \
#     --manual-auth-hook /etc/letsencrypt/hooks/hetzner/certbot-hcloud.sh\ auth \
#     --manual-cleanup-hook /etc/letsencrypt/hooks/hetzner/certbot-hcloud.sh\ cleanup \
#     -d example.com                         # run again in a separate command for *.example.com

set -euo pipefail

# ---- Inputs -----------------------------------------------------------------
: "${HCLOUD_ZONE:?HCLOUD_ZONE not set (zone name or ID)}"
TTL="${HCLOUD_TTL:-60}"

: "${CERTBOT_DOMAIN:?CERTBOT_DOMAIN missing}"
: "${CERTBOT_VALIDATION:?CERTBOT_VALIDATION missing}"

SUBCMD="${1:-}"
RR_NAME="_acme-challenge"
QV="\"${CERTBOT_VALIDATION}\""  # Hetzner expects TXT with surrounding quotes

# Build correct FQDN for apex vs wildcard
if [[ "$CERTBOT_DOMAIN" == \*.* ]]; then
  BASE="${CERTBOT_DOMAIN#*.}"  # strip only the leading "*."
else
  BASE="$CERTBOT_DOMAIN"
fi
FQDN="${RR_NAME}.${BASE}"

# hcloud verbosity
if [[ "${DEBUG:-0}" == "1" ]]; then
  set -x
  HCLOUD_FLAGS=(--debug)
else
  HCLOUD_FLAGS=(--no-experimental-warnings)
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

log() { printf '%s
' "$@"; }          # info -> stdout (so Certbot won't say "error output")
err() { printf '%s
' "$@" >&2; }        # errors -> stderr
fail() { err "ERROR: $*"; exit 1; }

command -v hcloud >/dev/null 2>&1 || fail "hcloud CLI not found"
command -v jq >/dev/null 2>&1 || fail "jq not found"
# dig optional

# ---- Helpers ----------------------------------------------------------------
# Optional grace wait after authoritative success/absence to let recursive caches expire
# GRACE defaults to TTL seconds; override with GRACE_SECONDS env var.
GRACE="${GRACE_SECONDS:-$TTL}"

grace_wait() {
  # Wait for GRACE seconds, printing progress every 10s (or final shorter chunk)
  local total="${1:-$GRACE}"
  local interval=10
  local waited=0
  if (( total <= 0 )); then return 0; fi
  log "[grace] Waiting ${total}s (approx TTL) to allow recursive caches to age out…"
  while (( waited < total )); do
    local left=$(( total - waited ))
    local chunk=$(( left < interval ? left : interval ))
    log "[grace] sleeping ${chunk}s (remaining: ${left}s)"
    sleep "$chunk"
    waited=$(( waited + chunk ))
  done
  log "[grace] Done."
}

records_one_token() {
  jq -cn --arg v "$QV" '[{"value":$v, "comment":"added by certbot"}]'
}

records_empty() {
  echo '[]'
}

apply_records() {
  local json="$1"
  printf '%s' "$json" >"${TMP_DIR}/records.json"
  # Sanity check the JSON we are about to send
  if ! jq -e . "${TMP_DIR}/records.json" >/dev/null 2>&1; then
    fail "records.json is not valid JSON (content: $(cat "${TMP_DIR}/records.json" 2>/dev/null))"
  fi
  if [[ ! -s "${TMP_DIR}/records.json" ]]; then
    fail "records.json is empty"
  fi
  log "[apply] set-records ${HCLOUD_ZONE} ${RR_NAME} TXT with: $(cat "${TMP_DIR}/records.json")"
  hcloud "${HCLOUD_FLAGS[@]}" zone rrset set-records \
    --records-file "${TMP_DIR}/records.json" \
    "$HCLOUD_ZONE" "$RR_NAME" TXT >/dev/null
}

maybe_create_with_ttl() {
  local json="$1"
  printf '%s' "$json" >"${TMP_DIR}/records.json"
  if ! jq -e . "${TMP_DIR}/records.json" >/dev/null 2>&1; then
    fail "records.json (create) is not valid JSON"
  fi
  log "[create] trying create with TTL=${TTL} (ok if it already exists)"
  hcloud "${HCLOUD_FLAGS[@]}" zone rrset create \
    --name "$RR_NAME" --type TXT --ttl "$TTL" \
    --records-file "${TMP_DIR}/records.json" \
    "$HCLOUD_ZONE" >/dev/null 2>&1 || true
}

wait_for_dns() {
  command -v dig >/dev/null 2>&1 || { log "[wait] dig not found; skipping"; return 0; }
  local interval=10           # seconds between checks
  local max_seconds=180       # total wait = 3 minutes
  local tries=$((max_seconds/interval))
  local i=0
  log "[wait] Target: ${FQDN} should contain ${QV}"
  # Gather authoritative nameservers for the base zone
  local nslist; nslist=$(dig +short NS "${BASE}" | sed 's/\.$//')
  if [[ -z "$nslist" ]]; then
    log "[wait] No NS discovered for ${BASE}; will use default resolver only"
  else
    log "[wait] Authoritative NS for ${BASE}: ${nslist//$'
'/ }"
  fi
  while (( i < tries )); do
    i=$((i+1))
    local elapsed=$((i*interval - interval))
    local remaining=$((max_seconds - elapsed))

    # Default resolver view
    local out_def; out_def=$(dig +short TXT "$FQDN" 2>/dev/null || true)
    log "[wait ${i}/${tries}] default resolver => ${out_def:-<empty>} (elapsed: ${elapsed}s, left: ${remaining}s)"

    # Authoritative view: require ALL NS to include the value
    local all_ok=1
    if [[ -n "$nslist" ]]; then
      while read -r ns; do
        [[ -z "$ns" ]] && continue
        local out_ns; out_ns=$(dig +norecurse +short TXT "$FQDN" @"$ns" 2>/dev/null || true)
        log "[wait ${i}/${tries}] @${ns} => ${out_ns:-<empty>}"
        grep -F -- "$QV" <<<"$out_ns" >/dev/null 2>&1 || all_ok=0
      done <<< "$nslist"
    else
      # If no NS list, decide based on default resolver only
      grep -F -- "$QV" <<<"$out_def" >/dev/null 2>&1 || all_ok=0
    fi

    if (( all_ok == 1 )); then
      log "[wait] TXT visible on required resolvers."
      grace_wait "$GRACE"   # <-- grace after authoritative success
      return 0
    fi

    sleep "$interval"
  done
  log "[wait] WARNING: Gave up after ${max_seconds}s; TXT not consistent everywhere"
}


wait_until_absent() {
  command -v dig >/dev/null 2>&1 || { log "[wait] dig not found; skipping"; return 0; }
  local interval=10
  local max_seconds=180
  local tries=$((max_seconds/interval))
  local i=0
  log "[wait] Target: ${FQDN} should be ABSENT"
  local nslist; nslist=$(dig +short NS "${BASE}" | sed 's/\.$//')
  if [[ -n "$nslist" ]]; then
    log "[wait] Authoritative NS for ${BASE}: ${nslist//$'
'/ }"
  fi
  while (( i < tries )); do
    i=$((i+1))
    local elapsed=$((i*interval - interval))
    local remaining=$((max_seconds - elapsed))

    local out_def; out_def=$(dig +short TXT "$FQDN" 2>/dev/null || true)
    log "[wait ${i}/${tries}] default resolver => ${out_def:-<empty>} (elapsed: ${elapsed}s, left: ${remaining}s)"

    local all_absent=1
    if [[ -n "$nslist" ]]; then
      while read -r ns; do
        [[ -z "$ns" ]] && continue
        local out_ns; out_ns=$(dig +norecurse +short TXT "$FQDN" @"$ns" 2>/dev/null || true)
        log "[wait ${i}/${tries}] @${ns} => ${out_ns:-<empty>}"
        [[ -z "$out_ns" ]] || all_absent=0
      done <<< "$nslist"
    else
      [[ -z "$out_def" ]] || all_absent=0
    fi

    if (( all_absent == 1 )); then
      log "[wait] TXT absent on required resolvers."
      grace_wait "$GRACE"   # <-- grace after authoritative absence
      return 0
    fi

    sleep "$interval"
  done
  log "[wait] WARNING: Gave up after ${max_seconds}s; TXT still present somewhere"
}

# ---- Subcommands ------------------------------------------------------------
case "$SUBCMD" in
  auth)
    log "[auth] zone=${HCLOUD_ZONE} fqdn=${FQDN} ttl=${TTL}"
    log "[auth] quoted token=${QV}"

    one="$(records_one_token)"
    maybe_create_with_ttl "$one"   # set TTL if RRSet is new; harmless if exists
    apply_records "$one"            # OVERWRITE to single token
    wait_for_dns
    ;;

  cleanup)
    log "[cleanup] zone=${HCLOUD_ZONE} fqdn=${FQDN} removing token=${QV}"

    empty="$(records_empty)"
    apply_records "$empty"          # [] deletes the RRSet per CLI contract
    wait_until_absent
    ;;

  ""|-h|--help|help)
    cat <<'USAGE'
Hetzner (hcloud) DNS-01 hook for Certbot — unified script (SIMPLE MODE)

Subcommands:
  auth      Overwrite TXT RRSet to only our ACME token.
  cleanup   Delete the TXT RRSet (set to []).

IMPORTANT:
  • Run certbot for ONE authorization per command (do NOT combine apex + wildcard).
  • Example:
      # 1) apex
      sudo -E certbot certonly --manual --preferred-challenges dns \
        --manual-auth-hook /etc/letsencrypt/hooks/hetzner/certbot-hcloud.sh\ auth \
        --manual-cleanup-hook /etc/letsencrypt/hooks/hetzner/certbot-hcloud.sh\ cleanup \
        -d example.com
      # 2) wildcard (separate command)
      sudo -E certbot certonly --manual --preferred-challenges dns \
        --manual-auth-hook /etc/letsencrypt/hooks/hetzner/certbot-hcloud.sh\ auth \
        --manual-cleanup-hook /etc/letsencrypt/hooks/hetzner/certbot-hcloud.sh\ cleanup \
        -d '*.example.com'

Environment:
  HCLOUD_ZONE   (required) zone name or ID, e.g. example.com
  HCLOUD_TTL    (optional) RRSet TTL when created (default 60)
  DEBUG=1       (optional) enable bash -x and hcloud --debug

Certbot provides:
  CERTBOT_DOMAIN, CERTBOT_VALIDATION
USAGE
    ;;

  *)
    fail "unknown subcommand: ${SUBCMD}. Use auth|cleanup|--help"
    ;;

esac

