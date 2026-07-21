#!/usr/bin/env bash
# Run the Docker-backed Borgmatic role scenario: converge twice, validate the
# generic collection command playbook, create a real local backup and restore,
# then verify teardown leaves the repository intact. No remote backup or
# production inventory is used.
set -euo pipefail

scenario_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${scenario_dir}/../../.." && pwd)"
work_dir="${repo_root}/.ansible-tmp/scenarios/borgmatic_backup"
image_name="homeops-ansible-ubuntu-ssh-target:22.04"
container_name="homeops-borgmatic-backup-$$"
controller_key="${work_dir}/controller_key"
inventory_file="${work_dir}/inventory.ini"

cleanup() {
  if [[ "${HOMEOPS_TEST_KEEP_CONTAINER:-0}" != "1" ]]; then
    docker rm -f "${container_name}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

for required_command in docker ssh ssh-keygen ansible-playbook; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${required_command}" >&2
    exit 127
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not reachable by the current user." >&2
  exit 1
fi

mkdir -p "${work_dir}"
rm -f "${controller_key}" "${controller_key}.pub" "${inventory_file}"

docker build \
  -t "${image_name}" \
  -f "${repo_root}/tests/scenarios/_common/ubuntu-ssh-target/Dockerfile" \
  "${repo_root}/tests/scenarios/_common/ubuntu-ssh-target"

ssh-keygen -q -t ed25519 -N "" -C "homeops-test-controller" -f "${controller_key}"
docker run -d --name "${container_name}" -p 127.0.0.1::22 "${image_name}" >/dev/null

docker exec "${container_name}" install -d -m 0700 -o ansibletest -g ansibletest /home/ansibletest/.ssh
docker cp "${controller_key}.pub" "${container_name}:/tmp/controller_key.pub"
docker exec "${container_name}" sh -c "cat /tmp/controller_key.pub > /home/ansibletest/.ssh/authorized_keys"
docker exec "${container_name}" chown ansibletest:ansibletest /home/ansibletest/.ssh/authorized_keys
docker exec "${container_name}" chmod 0600 /home/ansibletest/.ssh/authorized_keys
docker exec "${container_name}" sh -c "echo 'ansibletest ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ansibletest"
docker exec "${container_name}" chmod 0440 /etc/sudoers.d/90-ansibletest

ssh_port="$(docker inspect --format '{{ (index (index .NetworkSettings.Ports "22/tcp") 0).HostPort }}' "${container_name}")"

for _ in {1..30}; do
  if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "${controller_key}" -p "${ssh_port}" ansibletest@127.0.0.1 true >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i "${controller_key}" -p "${ssh_port}" ansibletest@127.0.0.1 true >/dev/null

printf '%s\n' '[role_backup]' > "${inventory_file}"
printf '%s%s%s%s%s\n' \
  'borgmatic-target ansible_host=127.0.0.1' \
  " ansible_port=${ssh_port}" \
  ' ansible_user=ansibletest' \
  " ansible_ssh_private_key_file=${controller_key}" \
  ' ansible_python_interpreter=/usr/bin/python3' >> "${inventory_file}"

export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_LOCAL_TEMP="${repo_root}/.ansible-tmp/local"
export ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote
export ANSIBLE_ROLES_PATH="${repo_root}/roles"
mkdir -p "${ANSIBLE_LOCAL_TEMP}"

echo "=== converge: borgmatic_backup ==="
ansible-playbook -i "${inventory_file}" "${scenario_dir}/converge.yml"

echo "=== idempotence: borgmatic_backup ==="
idempotence_log="${work_dir}/idempotence.log"
ansible-playbook -i "${inventory_file}" "${scenario_dir}/converge.yml" | tee "${idempotence_log}"
if ! grep -Eq "changed=0 .*failed=0" "${idempotence_log}"; then
  echo "ERROR: second converge was not idempotent." >&2
  exit 1
fi

echo "=== ad-hoc command: borgmatic config validate ==="
ansible \
  -i "${inventory_file}" \
  borgmatic-target \
  -m ansible.builtin.command \
  -a '/usr/local/bin/borgmatic config validate --config /etc/borgmatic/config.yaml' \
  -b

echo "=== verify: borgmatic_backup ==="
ansible-playbook -i "${inventory_file}" "${scenario_dir}/verify.yml"

echo "=== teardown: borgmatic_backup ==="
ansible-playbook -i "${inventory_file}" "${scenario_dir}/teardown.yml"
ansible-playbook -i "${inventory_file}" "${scenario_dir}/verify_teardown.yml"
