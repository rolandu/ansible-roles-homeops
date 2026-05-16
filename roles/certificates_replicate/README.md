# certificates_replicate

Pull certificate directories from another host over SSH/rsync and keep local permissions suitable for services such as nginx.

This role is intentionally simpler than `certificates_replicate_dsm`: it does not know about DSM certificate stores. It installs a managed replication script, creates local certificate directories, optionally installs a cron entry under `/etc/cron.d`, and can reload webservers when certificate file content changes.

## Requirements

- SSH access from the target host to the certificate source host.
- `rsync` available on both hosts.
- Source certificate files readable by `certificates_replicate_remote_user`.
- The target play should normally run with `become: true`, because the role writes under `/opt`, `/srv`, `/var/log`, and `/etc/cron.d` by default.

## Role Variables

Defaults are defined in `defaults/main.yml`.

- `certificates_replicate_script_dir` (string, default `/opt/certificates-replicate`): directory for the managed script.
- `certificates_replicate_script_path` (string, default `{{ certificates_replicate_script_dir }}/replicate-certificates.sh`): script path.
- `certificates_replicate_log_file` (string, default `/var/log/certificates-replicate.log`): dedicated log file.
- `certificates_replicate_shared_group` (string, default `certificates`): group assigned to local certificate files.
- `certificates_replicate_dir_mode` (string, default `2770`): mode for local certificate directories.
- `certificates_replicate_file_mode` (string, default `0640`): mode for local certificate files.
- `certificates_replicate_install_packages` (bool, default `true`): install `rsync` and `openssh-client`.
- `certificates_replicate_install_cron` (bool, default `true`): manage `/etc/cron.d/certificates-replicate`.
- `certificates_replicate_cron_schedule` (string, default `17 4,16 * * *`): full cron schedule expression.
- `certificates_replicate_remote_user` (string, required): SSH user on the source host.
- `certificates_replicate_remote_host` (string, required): source host name or address.
- `certificates_replicate_remote_base_dir` (string, default `/srv/certificates/live`): default source parent directory. Used as `<remote_base_dir>/<item.name>` when an item omits `remote_path`.
- `certificates_replicate_local_base_dir` (string, default `/srv/certificates/live`): default target parent directory. Used as `<local_base_dir>/<item.name>` when an item omits `local_path`.
- `certificates_replicate_items` (list, required): certificate directories to sync.
- `certificates_replicate_validate_run` (bool, default `false`): run the generated script once during the Ansible play and print stdout/stderr.
- `certificates_replicate_rsync_copy_links` (bool, default `true`): pass `--copy-links`, useful for Certbot `live/` symlinks.
- `certificates_replicate_delete` (bool, default `false`): pass `--delete` to remove local files missing on the source.
- `certificates_replicate_reload_nginx` (bool, default `true`): after changed syncs, reload nginx when the `nginx` command exists and the `nginx` service is active.
- `certificates_replicate_reload_apache` (bool, default `true`): after changed syncs, reload Apache when `apache2ctl` or `httpd` exists and the matching service is active.
- `certificates_replicate_post_sync_commands` (list[string], default `[]`): custom commands to run after changed syncs, for example to reload a Docker container.
- `certificates_replicate_ssh_private_key_path` (string, default empty): optional SSH key path.
- `certificates_replicate_ssh_strict_host_key_checking` (bool, default `true`): SSH host key checking mode.
- `certificates_replicate_ssh_known_hosts_file` (string, default empty): optional known_hosts path.
- `certificates_replicate_ssh_extra_args` (list[string], default `[]`): extra SSH arguments for rsync.

Each `certificates_replicate_items` entry needs:

- `name`: safe log label, using letters, numbers, `_`, `.`, or `-`.
- `remote_path` (optional): absolute source directory on `certificates_replicate_remote_host`. Defaults to `{{ certificates_replicate_remote_base_dir }}/{{ name }}`.
- `local_path` (optional): absolute target directory on this host. Defaults to `{{ certificates_replicate_local_base_dir }}/{{ name }}`.

## Example

```yaml
---
- name: Pull certificates to nginx host
  hosts: proxy
  become: true

  roles:
    - role: rolandu.homeops.certificates_replicate
      vars:
        certificates_replicate_remote_user: certsync
        certificates_replicate_remote_host: certbot.example.com
        certificates_replicate_shared_group: certificates
        certificates_replicate_items:
          - name: example.com
        certificates_replicate_ssh_private_key_path: /root/.ssh/id_ed25519
```

Ansible-managed validation run:

```yaml
certificates_replicate_validate_run: true
```

When enabled, the role runs the generated script, prints the script output to
the Ansible console, and then fails the play if the command returned a non-zero
exit code.

Manual real run:

```bash
sudo /opt/certificates-replicate/replicate-certificates.sh
```

The script writes logs to stdout/stderr. The role-managed cron entry redirects
that output to `certificates_replicate_log_file`.

The script prints `rsync --itemize-changes` output for diagnostics, but reload
decisions are based on a before/after fingerprint of local certificate files and
symlink targets. Metadata-only changes, such as permissions or directory
timestamps, do not trigger webserver reloads. The script does not preserve
source owner, group, or permissions because the role normalizes local
certificate ownership and modes after each sync.

## Webserver Reload Behavior

An Ansible handler is not enough for scheduled certificate replication, because future cron runs happen outside the play. For that reason, the managed script handles reloads itself when certificate file content changes.

The script can reload nginx and Apache. Each check is enabled by default, and
skips gracefully when binaries or active systemd services are missing:

- nginx: `nginx -t`, then `systemctl reload nginx`
- Apache: `apache2ctl configtest` and `systemctl reload apache2`, or `httpd -t` and `systemctl reload httpd`

Additional commands can be configured with `certificates_replicate_post_sync_commands`.

This role does not include a Docker scenario test. Meaningful runtime validation requires a reachable certificate source host and real certificate files.
