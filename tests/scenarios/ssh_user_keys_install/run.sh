#!/usr/bin/env bash
set -euo pipefail

scenario_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${scenario_dir}/../../.." && pwd)"
work_dir="${repo_root}/.ansible-tmp/scenarios/ssh_user_keys_install"
image_name="homeops-ansible-ubuntu-ssh-target:22.04"
container_name="homeops-ssh-user-keys-install-$$"
controller_key="${work_dir}/controller_key"
inline_key="${work_dir}/inline_key"
file_key="${work_dir}/file_key"
inventory_file="${work_dir}/inventory.ini"
artifacts_dir="${work_dir}/artifacts"

# Set HOMEOPS_TEST_KEEP_CONTAINER=1 when debugging to inspect the container
# after a failed run.
cleanup() {
  if [[ "${HOMEOPS_TEST_KEEP_CONTAINER:-0}" != "1" ]]; then
    docker rm -f "${container_name}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 127
  fi
}

require_command docker
require_command ssh
require_command ssh-keygen
require_command ansible-playbook

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not reachable by the current user." >&2
  echo "Run this after Docker access is available, or use sudo:" >&2
  echo "  sudo ${BASH_SOURCE[0]}" >&2
  exit 1
fi

mkdir -p "${work_dir}" "${artifacts_dir}/ssh_keys"
rm -rf "${artifacts_dir:?}/"*
mkdir -p "${artifacts_dir}/ssh_keys"
rm -f \
  "${controller_key}" "${controller_key}.pub" \
  "${inline_key}" "${inline_key}.pub" \
  "${file_key}" "${file_key}.pub" \
  "${inventory_file}"

docker build \
  -t "${image_name}" \
  -f "${repo_root}/tests/scenarios/_common/ubuntu-ssh-target/Dockerfile" \
  "${repo_root}/tests/scenarios/_common/ubuntu-ssh-target"

# The controller key is the bootstrap key used by Ansible for SSH. The inline
# and file keys are additional desired authorized_keys entries under test.
ssh-keygen -q -t ed25519 -N "" -C "homeops-test-controller" -f "${controller_key}"
ssh-keygen -q -t ed25519 -N "" -C "homeops-test-inline" -f "${inline_key}"
ssh-keygen -q -t ed25519 -N "" -C "homeops-test-file" -f "${file_key}"
cp "${file_key}.pub" "${artifacts_dir}/ssh_keys/file_key.pub"

docker run -d --name "${container_name}" -p 127.0.0.1::22 "${image_name}" >/dev/null

# Seed the bootstrap public key directly with Docker so the first Ansible SSH
# connection can happen. The role later rewrites authorized_keys, so converge.yml
# includes this same key in the desired authorized key list.
docker exec "${container_name}" install -d -m 0700 -o ansibletest -g ansibletest /home/ansibletest/.ssh
docker cp "${controller_key}.pub" "${container_name}:/tmp/controller_key.pub"
docker exec "${container_name}" sh -c "cat /tmp/controller_key.pub > /home/ansibletest/.ssh/authorized_keys"
docker exec "${container_name}" chown ansibletest:ansibletest /home/ansibletest/.ssh/authorized_keys
docker exec "${container_name}" chmod 0600 /home/ansibletest/.ssh/authorized_keys

ssh_port="$(docker inspect \
  --format '{{ (index (index .NetworkSettings.Ports "22/tcp") 0).HostPort }}' \
  "${container_name}")"

# Wait until sshd is accepting the bootstrap key. The final ssh command after
# the loop gives a clear failure if the container never became reachable.
for _ in {1..30}; do
  if ssh \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "${controller_key}" \
    -p "${ssh_port}" \
    ansibletest@127.0.0.1 true >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

ssh \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${controller_key}" \
  -p "${ssh_port}" \
  ansibletest@127.0.0.1 true >/dev/null

cat > "${inventory_file}" <<EOF
[ssh_user_keys_install_targets]
ssh-key-install-target ansible_host=127.0.0.1 ansible_port=${ssh_port} ansible_user=ansibletest ansible_ssh_private_key_file=${controller_key} ansible_python_interpreter=/usr/bin/python3
EOF

export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_LOCAL_TEMP="${repo_root}/.ansible-tmp/local"
export ANSIBLE_REMOTE_TEMP="/tmp/ansible-remote"
export ANSIBLE_ROLES_PATH="${repo_root}/roles"
export HOMEOPS_TEST_ARTIFACTS_DIR="${artifacts_dir}"
export HOMEOPS_TEST_CONTROLLER_PUBLIC_KEY
export HOMEOPS_TEST_INLINE_PUBLIC_KEY
export HOMEOPS_TEST_FILE_PUBLIC_KEY
# Force color because the idempotence run is piped through tee, which otherwise
# makes Ansible think it is not writing to an interactive terminal.
unset NO_COLOR
export ANSIBLE_FORCE_COLOR="${ANSIBLE_FORCE_COLOR:-1}"

HOMEOPS_TEST_CONTROLLER_PUBLIC_KEY="$(<"${controller_key}.pub")"
HOMEOPS_TEST_INLINE_PUBLIC_KEY="$(<"${inline_key}.pub")"
HOMEOPS_TEST_FILE_PUBLIC_KEY="$(<"${file_key}.pub")"

mkdir -p "${ANSIBLE_LOCAL_TEMP}"

# Converge applies the role once.
echo "=== converge: ssh_user_keys_install ==="
ansible-playbook -i "${inventory_file}" "${scenario_dir}/converge.yml"

# A second converge should report no changes.
echo "=== idempotence: ssh_user_keys_install ==="
idempotence_log="${work_dir}/idempotence.log"
ansible-playbook -i "${inventory_file}" "${scenario_dir}/converge.yml" | tee "${idempotence_log}"
if ! grep -Eq "changed=0 .*failed=0" "${idempotence_log}"; then
  echo "ERROR: second converge was not idempotent." >&2
  exit 1
fi

# Verify asserts authorized_keys ownership, mode, and exact contents.
echo "=== verify: ssh_user_keys_install ==="
ansible-playbook -i "${inventory_file}" "${scenario_dir}/verify.yml"

echo
echo "=== manual inspection: ssh_user_keys_install ==="
echo "Expected remote state:"
echo "  - /home/ansibletest/.ssh/authorized_keys exists with mode 0600"
echo "  - authorized_keys contains exactly these three key comments:"
echo "    - homeops-test-controller"
echo "    - homeops-test-inline"
echo "    - homeops-test-file"
echo
echo "Remote /home/ansibletest/.ssh directory:"
docker exec "${container_name}" ls -la /home/ansibletest/.ssh
echo
echo "Remote authorized_keys:"
docker exec "${container_name}" cat /home/ansibletest/.ssh/authorized_keys
echo
echo "Controller-side key file consumed by the role:"
echo "  - ${artifacts_dir}/ssh_keys/file_key.pub"
cat "${artifacts_dir}/ssh_keys/file_key.pub"
