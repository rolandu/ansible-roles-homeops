# resticprofile_backup

Install a pinned [Resticprofile](https://creativeprojects.github.io/resticprofile/)
binary, install Restic from the target distribution, render one root-owned
configuration with one profile per backup target, and optionally schedule the
profiles as a sequential group through `/etc/cron.d`.

The role deliberately does not create or initialize remote repositories. Set
up the remote target, credentials, and SSH host-key trust separately, deploy
this role with scheduling disabled, initialize and test the repository, and
only then enable cron.

**This is an administrative role and assumes privileged execution
(`become: true`) works on the target.**

## Supported targets

- Debian and Ubuntu
- `x86_64`, `aarch64`, and `armv7l`

Resticprofile is downloaded from its official release using the no-self-update
build. The archive SHA-256 digest is pinned in role defaults. Restic, cron,
`flock`, and logrotate come from distribution packages.

## Backup targets

Every `resticprofile_targets` item requires a unique `name`, `repository`, and
`password`. A target can also provide its own
`environment`, `extra_config`, `gatus_endpoint_key`, and `gatus_token`:

```yaml
resticprofile_targets:
  - name: primary
    repository: sftp:backup-a@example.net:/repositories/server01
    password: "{{ vault_restic_primary_password }}"
    environment:
      RESTIC_CACHE_DIR: /var/cache/restic-primary
  - name: secondary
    repository: s3:s3.example.net/restic/server01
    password: "{{ vault_restic_secondary_password }}"
    environment:
      AWS_ACCESS_KEY_ID: "{{ vault_restic_s3_access_key }}"
      AWS_SECRET_ACCESS_KEY: "{{ vault_restic_s3_secret_key }}"
```

Each target gets a separate root-only password file and, when needed, a
separate root-only environment file. The cron wrapper invokes
`resticprofile_group_name` (default `all`), which runs the target profiles in
the configured order. They do not run concurrently.
`resticprofile_group_continue_on_error` defaults to `true`, so an unavailable
target does not prevent the remaining targets from being attempted; the group
command still exposes the failure.

Store all passwords and backend credentials in Ansible Vault.

## Backup policy

- `resticprofile_sources` defaults to `/srv`, `/etc`, `/var`, `/home`, and
  `/root`.
- `resticprofile_excludes` omits logs, caches, temporary files, and container
  runtime storage under `/var/lib`. `/srv/docker-data` remains included.
- `resticprofile_one_file_system` defaults to `false`, so explicitly listed
  sources include mounted filesystems below them.
- `resticprofile_tags` defaults to the inventory hostname.
- `resticprofile_retention` defaults to 7 daily, 4 weekly, 12 monthly, and 3
  yearly snapshots. Retention and pruning run after a successful backup.
- `resticprofile_extra_config` is recursively merged into every profile.
  A target's `extra_config` is applied afterward. Lists are appended.

File-level backups of active database files are not automatically
application-consistent. Add suitable dump/snapshot hooks before relying on the
backup for PostgreSQL, MariaDB/MySQL, or similar services.

## Scheduling

`resticprofile_schedule_enabled` defaults to `false`. When enabled,
`resticprofile_backup_cron` supplies the five cron time fields:

```yaml
resticprofile_schedule_enabled: true
resticprofile_backup_cron:
  minute: "30"
  hour: "12"
  day: "*"
  month: "*"
  weekday: "*"
```

An optional independent check schedule is controlled by
`resticprofile_check_schedule_enabled` and `resticprofile_check_cron`.

Cron calls a role-managed wrapper protected by `flock`. Concurrent invocations
fail instead of overlapping. Output is appended to
`/var/log/resticprofile-backup.log`, which has a managed logrotate policy.

## Gatus notifications

Set `resticprofile_gatus_enabled: true` and provide:

- `resticprofile_gatus_url`: Gatus base URL, for example
  `https://status.example.net`.
- `resticprofile_gatus_endpoint_key`: default external endpoint key.
- `resticprofile_gatus_token`: default bearer token; keep it in Ansible Vault.

Each target may override the endpoint key and token. Every target must have
effective values from either its overrides or the defaults. The role adds
Resticprofile's native `send-after` and `send-after-fail` HTTP hooks to the
backup command. A successful target backup reports `success=true`; a failed
one reports `success=false` with a fixed, non-sensitive failure summary.
Detailed errors remain in the protected backup log. Notifications are per
target, so one sequential group run can update several Gatus endpoints. See
the [Resticprofile HTTP hook
reference](https://creativeprojects.github.io/resticprofile/configuration/http_hooks/).

Resticprofile logs notification-delivery failures but does not change the
backup command's exit status for them. Monitor network reachability to Gatus
separately if notification delivery itself is critical.

## Installation and paths

- `resticprofile_version`: pinned Resticprofile release; read the current value
  from `defaults/main.yml`.
- `resticprofile_architecture_map` and `resticprofile_checksums`: release asset
  mappings and SHA-256 digests.
- `resticprofile_install_packages`: install distribution dependencies,
  default `true`.
- `resticprofile_packages`: package list.
- `resticprofile_install_root`: release and runner root, default
  `/opt/resticprofile`.
- `resticprofile_binary_path`: default `/usr/local/bin/resticprofile`.
- `resticprofile_config_dir`: default `/etc/resticprofile`.
- `resticprofile_config_path`: default `/etc/resticprofile/profiles.yaml`.
- Password and environment files are generated in
  `resticprofile_config_dir` with target-name suffixes.
- `resticprofile_log_file`: default `/var/log/resticprofile-backup.log`.
- `resticprofile_log_mode`: default `'0640'`.

All configuration, password, and environment files are owned by root and use
mode `'0600'`. Secret-bearing tasks suppress logging and diffs.

## Updating Resticprofile

The release and its integrity pins live together in `defaults/main.yml`:

- `resticprofile_version` selects the release.
- `resticprofile_checksums` pins the release asset for each supported
  architecture.

To upgrade, change the release, replace every architecture checksum with the
SHA-256 value for the matching new release asset, and run the role's static
validation and Docker scenario. Never carry checksums forward from an older
release. Roll the result out to one host with scheduling disabled and verify a
backup and canary restore before wider deployment.

## Teardown

Set `resticprofile_teardown: true` to remove the downloaded Resticprofile
binary, configuration, wrapper, cron, logrotate policy, cache, and local log.
The role does not uninstall distribution packages or modify/delete the remote
repository.

## Example

```yaml
---
- name: Configure secondary Restic backup
  hosts: backup_hosts
  become: true
  roles:
    - role: rolandu.homeops.resticprofile_backup
      vars:
        resticprofile_targets:
          - name: offsite
            repository: >-
              sftp:backup@example.net:/repositories/server01
            password: "{{ vault_resticprofile_password }}"
            environment:
              RESTIC_CACHE_DIR: /var/cache/restic
        resticprofile_schedule_enabled: false
```

## Manual workflow

Commands use the role-managed wrapper so configuration, credentials, locking,
and profile selection stay consistent. Without `--profile`, the wrapper runs
the configured group and therefore applies the command to every target.

Dry-run the backup command:

```bash
sudo /opt/resticprofile/bin/run-resticprofile backup --dry-run
```

Initialize a repository after manually provisioning the target:

```bash
sudo /opt/resticprofile/bin/run-resticprofile --profile offsite init
```

Run and inspect backups:

```bash
sudo /opt/resticprofile/bin/run-resticprofile backup
sudo /opt/resticprofile/bin/run-resticprofile snapshots
sudo /opt/resticprofile/bin/run-resticprofile check
```

Select one target when listing or restoring a particular repository:

```bash
sudo /opt/resticprofile/bin/run-resticprofile --profile offsite snapshots
sudo mkdir -p /tmp/restic-restore
sudo /opt/resticprofile/bin/run-resticprofile --profile offsite restore latest \
  --target /tmp/restic-restore
```

Do not enable scheduling until a real backup and restore have both succeeded.
