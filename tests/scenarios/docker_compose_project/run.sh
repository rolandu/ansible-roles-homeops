#!/usr/bin/env bash
set -euo pipefail

scenario_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${scenario_dir}/../../.." && pwd)"
work_dir="${repo_root}/.ansible-tmp/scenarios/docker_compose_project"
image_name="homeops-docker-compose-project-target:25.0.5"
container_name="homeops-docker-compose-project-$$"
controller_key="${work_dir}/controller_key"
inventory_file="${work_dir}/inventory.ini"

cleanup() {
  if [[ "${HOMEOPS_TEST_KEEP_CONTAINER:-0}" != "1" ]]; then
    docker rm -f "${container_name}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

for command in docker ssh ssh-keygen ansible-playbook; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${command}" >&2
    exit 127
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not reachable by the current user." >&2
  exit 1
fi

mkdir -p "${work_dir}"
rm -f "${controller_key}" "${controller_key}.pub" "${inventory_file}"

docker build -t "${image_name}" "${scenario_dir}"
ssh-keygen -q -t ed25519 -N "" -C "homeops-test-controller" -f "${controller_key}"
docker run -d \
  --privileged \
  --name "${container_name}" \
  -p 127.0.0.1::22 \
  --entrypoint /bin/sh \
  "${image_name}" \
  -c '/usr/local/bin/dockerd-entrypoint.sh dockerd >/var/log/dockerd.log 2>&1 & exec /usr/sbin/sshd -D -e' \
  >/dev/null

docker exec "${container_name}" install -d -m 0700 -o ansibletest -g ansibletest /home/ansibletest/.ssh
docker cp "${controller_key}.pub" "${container_name}:/home/ansibletest/.ssh/authorized_keys"
docker exec "${container_name}" chown ansibletest:ansibletest /home/ansibletest/.ssh/authorized_keys
docker exec "${container_name}" chmod 0600 /home/ansibletest/.ssh/authorized_keys

ssh_port="$(docker inspect \
  --format '{{ (index (index .NetworkSettings.Ports "22/tcp") 0).HostPort }}' \
  "${container_name}")"

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

if ! ssh \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -i "${controller_key}" \
  -p "${ssh_port}" \
  ansibletest@127.0.0.1 true >/dev/null 2>&1; then
  echo "ERROR: scenario SSH target is not reachable." >&2
  exit 1
fi

for _ in {1..60}; do
  if docker exec "${container_name}" docker info >/dev/null 2>&1 \
    && docker exec "${container_name}" docker compose version >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! docker exec "${container_name}" docker info >/dev/null 2>&1; then
  docker exec "${container_name}" sed -n '1,200p' /var/log/dockerd.log >&2
  exit 1
fi

cat > "${inventory_file}" <<EOF
[docker_compose_project_targets]
docker-compose-project-target ansible_host=127.0.0.1 ansible_port=${ssh_port} ansible_user=ansibletest ansible_ssh_private_key_file=${controller_key} ansible_python_interpreter=/usr/bin/python3 ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF

export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_LOCAL_TEMP="${repo_root}/.ansible-tmp/local"
export ANSIBLE_REMOTE_TEMP="/tmp/ansible-remote"
export ANSIBLE_ROLES_PATH="${repo_root}/roles"
export ANSIBLE_COLLECTIONS_PATH="${repo_root}/.ansible-tmp/collections:/usr/share/ansible/collections"
unset NO_COLOR
export ANSIBLE_FORCE_COLOR="${ANSIBLE_FORCE_COLOR:-1}"
mkdir -p "${ANSIBLE_LOCAL_TEMP}"

echo "=== converge: docker_compose_project ==="
ansible-playbook -i "${inventory_file}" "${scenario_dir}/converge.yml"

echo "=== idempotence: docker_compose_project ==="
idempotence_log="${work_dir}/idempotence.log"
ansible-playbook -i "${inventory_file}" "${scenario_dir}/converge.yml" | tee "${idempotence_log}"
if ! grep -Eq "changed=0 .*failed=0" "${idempotence_log}"; then
  echo "ERROR: second converge was not idempotent." >&2
  exit 1
fi

echo "=== verify: docker_compose_project ==="
ansible-playbook -i "${inventory_file}" "${scenario_dir}/verify.yml"

echo "=== managed configuration change: docker_compose_project ==="
ansible-playbook -i "${inventory_file}" "${scenario_dir}/change_config.yml"
ansible-playbook -i "${inventory_file}" "${scenario_dir}/verify_config_change.yml"

echo "=== compose definition change: docker_compose_project ==="
ansible-playbook -i "${inventory_file}" "${scenario_dir}/change_compose.yml"
ansible-playbook -i "${inventory_file}" "${scenario_dir}/verify_change.yml"

echo "=== invalid candidate: docker_compose_project ==="
if ansible-playbook -i "${inventory_file}" "${scenario_dir}/invalid_candidate.yml"; then
  echo "ERROR: invalid Compose candidate was accepted." >&2
  exit 1
fi
ansible-playbook -i "${inventory_file}" "${scenario_dir}/verify_invalid.yml"

echo "=== disable updates: docker_compose_project ==="
ansible-playbook -i "${inventory_file}" "${scenario_dir}/disable_updates.yml"
ansible-playbook -i "${inventory_file}" "${scenario_dir}/verify_updates_disabled.yml"

echo "=== teardown: docker_compose_project ==="
ansible-playbook -i "${inventory_file}" "${scenario_dir}/teardown.yml"
ansible-playbook -i "${inventory_file}" "${scenario_dir}/verify_teardown.yml"
