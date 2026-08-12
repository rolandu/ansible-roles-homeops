#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "${script_dir}" rev-parse --show-toplevel)"
index_file="${repo_root}/repo-index.txt"

usage() {
  cat <<EOF
Usage: scripts/index-repo.sh [--output PATH]

Options:
  --output PATH  Write the index to PATH. Relative paths resolve from repo root.
  -h, --help     Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --output requires a path." >&2
        exit 2
      fi
      index_file="$2"
      if [[ "${index_file}" != /* ]]; then
        index_file="${repo_root}/${index_file}"
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

declare -A descriptions=()

if [[ -f "${index_file}" ]]; then
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" == *": "* ]]; then
      path="${line%%: *}"
      descriptions["${path}"]="${line#*: }"
    fi
  done < "${index_file}"
fi

index_dir="$(dirname "${index_file}")"
temp_root="${repo_root}/.ansible-tmp"
mkdir -p "${index_dir}" "${temp_root}"

work_dir="$(mktemp -d "${temp_root}/index-repo.XXXXXX")"
paths_file="${work_dir}/paths"
tmp_file="${work_dir}/index"
cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

git -C "${repo_root}" ls-files -coz --exclude-standard | sort -z > "${paths_file}"

count=0
while IFS= read -r -d '' path; do
  printf '%s: %s\n' "${path}" "${descriptions["${path}"]-}" >> "${tmp_file}"
  count=$((count + 1))
done < "${paths_file}"

mv "${tmp_file}" "${index_file}"
cleanup
trap - EXIT

relative_index="${index_file#${repo_root}/}"
echo "Indexed ${count} paths in ${relative_index}"
