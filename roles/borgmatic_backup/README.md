# borgmatic_backup

Install inventory-selected Borg and Borgmatic versions in a dedicated Python
virtual environment, render one native Borgmatic configuration mapping, and
optionally schedule Borgmatic through `/etc/cron.d`.

This role is intentionally narrow. It does not model Borgmatic's configuration
schema. Sources, repositories, retention, hooks, database dumps, monitoring,
and other Borgmatic features belong directly in `borgmatic_backup_config`.

The role runs with administrative privileges and backups run as root. Use
`become: true` in the caller playbook.

## Boundaries

The role does not:

- manage SSH keys, SSH configuration, or known-host entries;
- provision backup storage accounts or servers;
- initialize, migrate, or delete repositories;
- execute a backup during convergence;
- calculate fleet schedule slots;
- install another operational wrapper around Borgmatic.

Use `rolandu.homeops.ssh_root_client` separately for root's outbound SSH
identity and trusted server configuration. Provision and initialize backup
repositories manually.

## Configuration

`borgmatic_backup_config` is required and must be a non-empty mapping. It is
serialized directly with `to_nice_yaml` into the managed configuration file:

```yaml
borgmatic_backup_config:
  repositories:
    - path: ssh://backup/./borg
      label: offsite
  source_directories:
    - /srv
    - /etc
    - /var
    - /home
    - /root
  exclude_patterns:
    - /var/log
    - /var/cache
    - /var/tmp
    - /var/lib/docker
    - /var/lib/containerd
    - /var/lib/containers
  encryption_passphrase: "{{ vault_borgmatic_passphrase }}"
  compression: auto,zstd
  keep_daily: 7
  keep_weekly: 4
  keep_monthly: 12
  keep_yearly: 3
  checks:
    - name: repository
      frequency: 1 month
    - name: archives
      frequency: 1 month
```

Multiple repositories use Borgmatic's native repository list and are processed
according to Borgmatic's behavior. Give repositories labels so operators can
select one through `--repository`.

Repository entries should use Borgmatic's native mapping form, for example
`{path: ssh://backup/./borg, label: offsite}`. The role does not normalize
shorthand repository strings; callers should pass the exact structure they
want written to Borgmatic's configuration.

The role only validates that the top-level value is a non-empty mapping.
Borgmatic remains the source of truth for its supported keys and semantics.
This allows new Borgmatic features, including native hooks and monitoring
integrations, without changing the role.

The configuration may contain secrets. Keep them in Ansible Vault. The render
task suppresses output and diffs, the configuration directory is mode `'0700'`,
and the configuration file is mode `'0600'`.

## Variables

### Installation

- `borgmatic_backup_borg_version`: exact Borg version installed from PyPI.
- `borgmatic_backup_borgmatic_version`: exact Borgmatic version installed from
  PyPI.
- `borgmatic_backup_python`: Python used to create the virtual environment.
- `borgmatic_backup_install_root`: installation root below `app_root_dir`.
- `borgmatic_backup_venv_path`: managed Python virtual environment; defaults
  to the installation root for compatibility with existing installations.
- `borgmatic_backup_install_packages`: install target distribution
  prerequisites when `true`.
- `borgmatic_backup_packages`: overrideable Debian/Ubuntu prerequisite list.
- `borgmatic_backup_borg_path`: stable Borg symlink.
- `borgmatic_backup_borgmatic_path`: stable Borgmatic symlink.

### Configuration and logging

- `borgmatic_backup_config`: required native Borgmatic mapping.
- `borgmatic_backup_config_dir`: protected configuration directory.
- `borgmatic_backup_config_path`: managed YAML file immediately below the
  configuration directory.
- `borgmatic_backup_lock_file`: host-wide cron lock file.
- `borgmatic_backup_log_file`: dedicated scheduled-run log.
- `borgmatic_backup_log_mode`: log mode, default `'0640'`.
- `borgmatic_backup_logrotate_file`: managed logrotate policy.

### Scheduling

- `borgmatic_backup_schedule_enabled`: install the cron entry when `true`;
  defaults to `false`.
- `borgmatic_backup_cron_file`: managed file below `/etc/cron.d`.
- `borgmatic_backup_cron`: `minute`, `hour`, `day`, `month`, and `weekday`.
- `borgmatic_backup_run_arguments`: list of Borgmatic action arguments for the
  scheduled invocation. An empty list runs Borgmatic's configured default action
  sequence.

Cron invokes the managed Borgmatic binary directly, prefixed by `flock -n`.
Action arguments are placed before the managed `--config` flag to avoid
ambiguous parsing on Borgmatic versions where `--config` can consume multiple
values. Concurrent scheduled invocations fail instead of overlapping. Output is
appended to the dedicated log and managed by logrotate.

### Teardown

- `borgmatic_backup_teardown`: remove role-managed local state when `true`.

Teardown removes the virtual environment, stable command links, configuration,
cron, logrotate policy, and local log. It does not uninstall distribution
packages, invoke Borg/Borgmatic, or modify any referenced local or remote
repository.

## Example

```yaml
---
- name: Configure Borgmatic backups
  hosts: backup_hosts
  gather_facts: true
  become: true

  roles:
    - role: rolandu.homeops.borgmatic_backup
      vars:
        borgmatic_backup_config:
          repositories:
            - path: ssh://backup/./borg
              label: offsite
          source_directories:
            - /srv
            - /etc
          encryption_passphrase: "{{ vault_borgmatic_passphrase }}"
        borgmatic_backup_schedule_enabled: false
```

## Operator commands from the controller

This role does not ship an operational wrapper for Borgmatic commands. Use a
normal Ansible ad-hoc command from the caller repository, or a caller-local
script that wraps the same pattern:

```bash
ansible server01 \
  -m ansible.builtin.command \
  -a '/usr/local/bin/borgmatic config validate --config /etc/borgmatic/config.yaml' \
  -b
```

Run these commands against one host at a time unless you intentionally want to
operate on multiple repositories/hosts. The command module runs the binary
directly; shell operators such as pipes, redirects, globbing, and environment
assignment are not interpreted.

Additional examples:

```bash
# Initialize one manually provisioned repository.
ansible server01 -m ansible.builtin.command \
  -a '/usr/local/bin/borgmatic repo-create --encryption repokey-blake2 --repository offsite --config /etc/borgmatic/config.yaml' \
  -b

# Dry-run creation, then create an archive.
ansible server01 -m ansible.builtin.command \
  -a '/usr/local/bin/borgmatic --dry-run create --repository offsite --config /etc/borgmatic/config.yaml' \
  -b
ansible server01 -m ansible.builtin.command \
  -a '/usr/local/bin/borgmatic create --repository offsite --stats --config /etc/borgmatic/config.yaml' \
  -b

# Inspect and check the repository.
ansible server01 -m ansible.builtin.command \
  -a '/usr/local/bin/borgmatic repo-list --repository offsite --config /etc/borgmatic/config.yaml' \
  -b
ansible server01 -m ansible.builtin.command \
  -a '/usr/local/bin/borgmatic check --repository offsite --config /etc/borgmatic/config.yaml' \
  -b

# Restore the latest archive into an existing destination.
ansible server01 -m ansible.builtin.command \
  -a '/usr/local/bin/borgmatic extract --repository offsite --archive latest --destination /tmp/borg-restore --config /etc/borgmatic/config.yaml' \
  -b
```

Consult the help for the installed Borgmatic version before running destructive
or repository-modifying actions. Do not put secrets in command arguments; use
the protected configuration or Borgmatic credential commands.

## Upgrade process

Borg and Borgmatic version defaults live in `defaults/main.yml`. Inventory may
override either value per host. To stage an upgrade:

1. Override both values as needed on one test host.
2. Apply the role with scheduling disabled.
3. Validate the configuration through the collection command playbook.
4. Run a real backup, repository check, archive listing, and canary restore.
5. Promote the tested values to group inventory or update the role defaults.
6. Remove the temporary host override and continue the rollout.

Configuration deployment or command success alone does not prove a usable
backup. Do not enable scheduling until the repository has been initialized, a
backup has completed, and known canary data has been restored and compared.
