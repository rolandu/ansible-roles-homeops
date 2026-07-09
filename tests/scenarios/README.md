# Docker Scenario Tests

These scenarios run selected roles against temporary Docker containers over
real SSH. They are intentionally small and role-specific rather than one shared
inventory for every role.

Each scenario follows the same lifecycle:

1. Build the shared Ubuntu 22.04 SSH target image.
2. Start one temporary container.
3. Generate a temporary controller SSH key.
4. Install that controller public key into the container with `docker exec`.
5. Write a temporary Ansible inventory under `.ansible-tmp/`.
6. Run `converge.yml` once to apply the role.
7. Run `converge.yml` again and require `changed=0` for idempotence.
8. Run `verify.yml` to assert the final remote and controller-side state.
9. Remove the container unless `HOMEOPS_TEST_KEEP_CONTAINER=1` is set.

The temporary controller key is test harness bootstrap material. It is what lets
Ansible SSH into the container before the role under test has done anything.

The target image intentionally uses Ubuntu 22.04 rather than 24.04. The
controller-side Ansible package used by this repo can fail against Python 3.12
targets with `ansible.module_utils.six.moves` import errors; Ubuntu 22.04 keeps
the target Python at a compatible version.

## Scenarios

Run the SSH key generation scenario:

```bash
tests/scenarios/ssh_user_keys_generate/run.sh
```

This verifies that `ssh_user_keys_generate` creates a keypair for the current
SSH connection user and exports the public key to the controller artifact
directory.

Run the authorized key installation scenario:

```bash
tests/scenarios/ssh_user_keys_install/run.sh
```

This verifies that `ssh_user_keys_install` writes `authorized_keys` for the
current SSH connection user from both inline keys and controller-side key files.
The bootstrap controller key is included in the desired key list so Ansible can
reconnect for the idempotence and verification phases.

Run the full SSH users scenario:

```bash
tests/scenarios/ssh_users/run.sh
```

This verifies that `ssh_users` manages declared local groups before users,
creates a managed user, appends supplementary groups, writes authorized keys,
leaves unrelated groups alone, removes explicitly absent groups, and remains
idempotent.

Run the automatic security updates scenario:

```bash
tests/scenarios/automatic_updates_debian_ubuntu/run.sh
```

This verifies that `automatic_updates_debian_ubuntu` installs the native update
packages, writes security-only unattended-upgrades origins, configures reboot
and service restart behavior, logs apt-listchanges output, and remains
idempotent.

Run the Resticprofile backup scenario:

```bash
tests/scenarios/resticprofile_backup/run.sh
```

This verifies the pinned Resticprofile installation, two secure target
profiles and their sequential group, cron and logrotate files, idempotence, a
local canary backup to both repositories, a targeted restore, and explicit
teardown. It also renders per-target Gatus hooks and verifies that an
unreachable Gatus endpoint does not replace the backup result. The scenario
downloads packages and release artifacts only when an operator chooses to run
it.

Run the Borgmatic backup scenario:

```bash
tests/scenarios/borgmatic_backup/run.sh
```

This verifies the virtual-environment installation, secure native Borgmatic
configuration rendering, stable command links, direct `flock`-protected cron
execution, logging, and idempotence. It validates the generic collection
command playbook, then explicitly initializes a temporary local repository,
backs up and restores a canary, checks exclusions, and proves that role
teardown leaves repository data intact. SSH is used only by the Ansible test
harness; Borg transfers data between two paths inside the disposable
container.

## Requirements

The current user must be able to access Docker. If Docker was just installed or
your user was just added to the `docker` group, log out and back in before
running these scripts.
