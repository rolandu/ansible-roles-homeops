#!/usr/bin/env bash

set -euo pipefail

export HCLOUD_ZONE={{ hcloud_zone | quote }}   # name or ID
export HCLOUD_TOKEN={{ hcloud_token | quote }}
export HCLOUD_TTL={{ hcloud_ttl | default(60) }}
export GRACE_SECONDS={{ grace_seconds | default(hcloud_ttl | default(60)) }}

export CERTBOT_EMAIL={{ certbot_email | quote }}
# export DEBUG=1  # optional
# export DRYRUN=1  # optional - certbot dryrun, no certs issued



makecert() {
  local domain="${1:?Usage: makecert <domain> <cert-name>}"
  local certname="${2:?Usage: makecert <domain> <cert-name>}"

  # Mandatory email (set once in your env): export CERTBOT_EMAIL="you@example.com"
  local email="${CERTBOT_EMAIL:?set CERTBOT_EMAIL}"

  # Optional dry-run toggle
  local maybe_dry=()
  [[ "${DRYRUN:-0}" == "1" ]] && maybe_dry+=(--dry-run)

  echo "Attempting to make/renew cert for $domain (lineage: $certname) using $email"

  certbot certonly \
    --keep-until-expiring \
    --manual --preferred-challenges dns \
    --manual-auth-hook "/etc/letsencrypt/dns-auth-hetzner.sh auth" \
    --manual-cleanup-hook "/etc/letsencrypt/dns-auth-hetzner.sh cleanup" \
    --cert-name "$certname" \
    --email "$email" --agree-tos --no-eff-email --non-interactive \
    "${maybe_dry[@]}" \
    -d "$domain"

  echo
  echo "--------------------------------------------------------------------"
  echo
}


# Iterate configured lineages sequentially
{% for item in certbot_lineages %}
makecert {{ item.domain | quote }} {{ item.certname | quote }}
{% endfor %}

