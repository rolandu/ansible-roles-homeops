# host_health_heartbeat

Install a root-owned host health script and optional cron entry that reports to
a configurable HTTP monitoring endpoint.

**This is an administrative role and it assumes privileged execution (`become: true`) works on the target host.**

The role is intended for basic host liveness and condition checks. It renders
notification URLs and headers into the managed script, so the script is
installed as `root:root` with mode `0700`.

## Requirements

- `curl` and `jq` are required for HTTP notification and URL encoding. The role
  installs them by default.
- SMART checks require `smartctl` and root access to the configured devices.
  The role installs `smartmontools` when SMART devices are configured.
- Btrfs checks require `btrfs`. The role installs `btrfs-progs` when Btrfs
  paths are configured.
- ZFS checks require `zpool`. The role does not install ZFS packages.
- Docker checks require the Docker CLI. The role does not install Docker.

## Role Variables

Defaults are defined in `defaults/main.yml`.

- `host_health_heartbeat_script_dir` (string, default
  `/opt/host-health-heartbeat`): directory for the managed script.
- `host_health_heartbeat_script_path` (string, default
  `{{ host_health_heartbeat_script_dir }}/host-health-heartbeat.sh`): script
  path.
- `host_health_heartbeat_log_file` (string, default
  `/var/log/host-health-heartbeat.log`): dedicated cron log file.
- `host_health_heartbeat_log_mode` (string, default `0640`): log file mode.
- `host_health_heartbeat_install_dependencies` (bool, default `true`): install
  required packages for enabled checks.
- `host_health_heartbeat_install_cron` (bool, default `true`): manage
  `/etc/cron.d/host-health-heartbeat`.
- `host_health_heartbeat_cron_schedule` (string, default `*/10 * * * *`): full
  cron schedule expression.
- `host_health_heartbeat_validate_run` (bool, default `false`): run the
  generated script once during the Ansible play.

Notification variables:

- `host_health_heartbeat_notify_method` (string, default `POST`): HTTP method.
- `host_health_heartbeat_notify_success_url` (string): URL template used when
  all checks pass.
- `host_health_heartbeat_notify_failure_url` (string): URL template used when a
  check fails.
- `host_health_heartbeat_notify_headers` (list[string]): HTTP headers passed to
  `curl`.
- `host_health_heartbeat_error_max_chars` (int, default `1200`): maximum
  length of the joined error message.

The URL templates support `{success}`, `{duration}`, and `{error}` placeholders.
The script URL-encodes placeholder values with `jq`.

Gatus-compatible defaults are built from:

- `host_health_heartbeat_gatus_url` (string, required when using defaults):
  base Gatus URL, for example `https://status.example.org`.
- `host_health_heartbeat_gatus_endpoint_key` (string, required when using
  defaults): Gatus external endpoint key, for example
  `server01_host-health`.
- `host_health_heartbeat_gatus_token` (string, required when using defaults):
  Gatus external endpoint bearer token.

Check variables:

- `host_health_heartbeat_check_diskspace` (bool, default `true`): enable
  diskspace and inode checks.
- `host_health_heartbeat_diskspace_check_all` (bool, default `true`): check all
  mounted real filesystems reported by `df`, excluding pseudo/temporary
  filesystem types.
- `host_health_heartbeat_diskspace_filesystems` (list[string], default `[]`):
  explicit filesystem mount paths to require and check. If
  `diskspace_check_all` is `false`, this list is the full diskspace target set.
- `host_health_heartbeat_diskspace_min_free_pct` (int, default `10`): minimum
  free disk percentage.
- `host_health_heartbeat_diskspace_min_free_inodes_pct` (int, default `5`):
  minimum free inode percentage. Set to `-1` to skip inode checks.
- `host_health_heartbeat_systemd_failed_units` (bool, default `true`): fail
  when `systemctl --failed` reports units.
- `host_health_heartbeat_load_check` (bool, default `true`): check 1-minute
  load average.
- `host_health_heartbeat_load_1m_max_per_cpu` (float, default `8.0`): maximum
  1-minute load average per online CPU.
- `host_health_heartbeat_memory_check` (bool, default `false`): check
  available memory percentage.
- `host_health_heartbeat_memory_min_available_pct` (int, default `5`):
  minimum available memory percentage when memory checks are enabled.
- `host_health_heartbeat_smart_devices` (list[dict], default `[]`): optional
  SMART devices to check.
- `host_health_heartbeat_zfs_check` (bool, default `false`): run
  `zpool status -x`.
- `host_health_heartbeat_zfs_pools` (list[string], default `[]`): optional
  ZFS pools to pass to `zpool status -x`. Empty means all pools.
- `host_health_heartbeat_btrfs_paths` (list[string], default `[]`): Btrfs
  mount paths checked with `btrfs device stats`.
- `host_health_heartbeat_docker_containers` (list[string], default `[]`):
  Docker containers to check with `docker inspect`. A container fails when it
  is missing, not running, or has a defined health check that is not `healthy`.
- `host_health_heartbeat_custom_commands` (list[dict], default `[]`): custom
  root-run shell checks. A nonzero exit status fails the heartbeat.

Each `host_health_heartbeat_smart_devices` entry supports:

- `device`: absolute device path, for example `/dev/sda` or
  `/dev/disk/by-id/...`.
- `type` (optional): value passed to `smartctl -d`, for example `sat`.

Each `host_health_heartbeat_custom_commands` entry supports:

- `name`: label included in error messages.
- `command`: shell command run as root by the heartbeat script.

## Example

```yaml
---
- name: Install host health heartbeat
  hosts: servers
  become: true

  roles:
    - role: rolandu.homeops.host_health_heartbeat
      vars:
        host_health_heartbeat_gatus_url: "https://monitoring.example.net"
        host_health_heartbeat_gatus_endpoint_key: "server01_host-health"
        host_health_heartbeat_gatus_token: "{{ vault_gatus_external_token }}"
        host_health_heartbeat_diskspace_filesystems:
          - /mnt/data
          - /mnt/backup
        host_health_heartbeat_smart_devices:
          - device: /dev/disk/by-id/ata-Samsung_SSD_example
        host_health_heartbeat_zfs_check: true
        host_health_heartbeat_zfs_pools:
          - tank
        host_health_heartbeat_docker_containers:
          - adguardhome
          - gatus
        host_health_heartbeat_custom_commands:
          - name: backup marker recent
            command: test "$(find /mnt/backup -name last-ok -mtime -2)"
```

Custom HTTP receiver example:

```yaml
host_health_heartbeat_notify_success_url: >-
  https://monitoring.example.net/heartbeat/server01?ok={success}&time={duration}
host_health_heartbeat_notify_failure_url: >-
  https://monitoring.example.net/heartbeat/server01?ok={success}&time={duration}&message={error}
host_health_heartbeat_notify_headers:
  - "X-Heartbeat-Token: {{ vault_heartbeat_token }}"
```

Ansible-managed validation run:

```yaml
host_health_heartbeat_validate_run: true
```

When enabled, the role runs the generated script, prints stdout/stderr, and
then fails the play if the command returned a nonzero exit code.

Manual dry run without sending the HTTP request:

```bash
sudo DRY_RUN=1 /opt/host-health-heartbeat/host-health-heartbeat.sh
```

Manual real run:

```bash
sudo /opt/host-health-heartbeat/host-health-heartbeat.sh
```

The script exits `0` after reporting success, `1` after reporting failed
checks, and `2` when it cannot send the HTTP notification.
