#!/usr/bin/env bash
set -u
set -o pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
roles_dir="${repo_root}/roles"
tmp_dir="${repo_root}/.ansible-tmp"
report_file=""

usage() {
  cat <<EOF
Usage: tests/lint-roles.sh [--report] [--report-file PATH]

Options:
  --report            Write output to tests/lint-report.txt.
  --report-file PATH  Write output to PATH. Relative paths resolve from repo root.
  -h, --help          Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      report_file="${repo_root}/tests/lint-report.txt"
      shift
      ;;
    --report-file)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --report-file requires a path." >&2
        exit 2
      fi
      report_file="$2"
      if [[ "${report_file}" != /* ]]; then
        report_file="${repo_root}/${report_file}"
      fi
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${tmp_dir}/cache}"
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-${tmp_dir}/local}"
export ANSIBLE_REMOTE_TEMP="${ANSIBLE_REMOTE_TEMP:-/tmp/ansible-remote}"

mkdir -p "${XDG_CACHE_HOME}" "${ANSIBLE_LOCAL_TEMP}"

if [[ -n "${report_file}" ]]; then
  mkdir -p "$(dirname "${report_file}")"
  export NO_COLOR=1
  export ANSIBLE_FORCE_COLOR=0
  exec > >(tee "${report_file}") 2>&1
  echo "Ansible lint report"
  echo "Generated: $(date -Is)"
  echo "Repository: ${repo_root}"
  echo
fi

if ! command -v ansible-lint >/dev/null 2>&1; then
  echo "ERROR: ansible-lint is not installed or not in PATH." >&2
  echo "Install it, then rerun: tests/lint-roles.sh" >&2
  exit 127
fi

if [[ ! -d "${roles_dir}" ]]; then
  echo "ERROR: roles directory not found: ${roles_dir}" >&2
  exit 1
fi

status=0

while IFS= read -r -d '' role_path; do
  role_name="$(basename "${role_path}")"

  echo
  echo "=== ansible-lint: ${role_name} ==="
  echo "Path: ${role_path#${repo_root}/}"

  if ! ansible-lint "${role_path}"; then
    status=1
  fi
done < <(find "${roles_dir}" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

exit "${status}"
