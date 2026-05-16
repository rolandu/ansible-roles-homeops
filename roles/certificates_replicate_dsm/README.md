# certificates_replicate_dsm

Render a DSM certificate replication script based on [`elfenquetsche/dsm-cert-update`](https://github.com/elfenquetsche/dsm-cert-update), install it in the SSH user's home directory, and print the command to run from Synology DSM Task Scheduler.

This role is for Synology DSM hosts that pull certificate files from another machine over SSH/rsync and then install them into DSM certificate locations. It intentionally does not install a cron entry because DSM scheduled tasks are normally configured through the DSM UI.

The script is vendored as a role template. DSM does not need `git` or internet access to GitHub.

## Requirements

- SSH access from the DSM host to the certificate source host.
- `bash`, `rsync`, `jq`, and `openssl` available on DSM, as required by the upstream script.
- A DSM certificate entry already created manually. Its DSM description must exactly match `certificates_replicate_dsm_cert_desc`.
- The DSM Task Scheduler task must run as `root`, because the upstream script writes under DSM certificate directories and restarts services.

## Role Variables

Defaults are defined in `defaults/main.yml`.

- `certificates_replicate_dsm_base_dir` (string, default empty): base directory for all role-managed files. Empty means the current SSH user's home directory.
- `certificates_replicate_dsm_script_dir_name` (string, default `dsm-cert-update`): directory under the base directory.
- `certificates_replicate_dsm_script_name` (string, default `replicate-certificates.sh`): generated certificate replication script name.
- `certificates_replicate_dsm_task_script_name` (string, default `dsm-task-replicate-certificates.sh`): generated helper script name for DSM Task Scheduler.
- `certificates_replicate_dsm_local_cert_dir_name` (string, default `certificates`): local staging directory name under the script directory.
- `certificates_replicate_dsm_log_file_name` (string, default `replicate-certificates.log`): log filename under the script directory.

Required in inventory or the caller playbook:

- `certificates_replicate_dsm_domain`: certificate domain name.
- `certificates_replicate_dsm_remote_user`: SSH user on the certificate source host.
- `certificates_replicate_dsm_remote_host`: source host name or address.
- `certificates_replicate_dsm_remote_base_dir`: source directory containing certificate files.
- `certificates_replicate_dsm_cert_desc`: DSM certificate description label. This must match the manually created DSM certificate exactly.

Optional runtime settings:

- `certificates_replicate_dsm_archive_base_dir` (string, default `/usr/syno/etc/certificate/_archive`): DSM archive directory.
- `certificates_replicate_dsm_archive_id` (string, default empty): optional explicit DSM archive ID. Empty means resolve the archive ID by `certificates_replicate_dsm_cert_desc` from DSM's `INFO` file.
- `certificates_replicate_dsm_dry_run` (bool, default `false`): default script dry-run mode. You can override per run with `DRY_RUN=true` or `DRY_RUN=false`.
- `certificates_replicate_dsm_rsync_copy_links` (bool, default `true`): pass `--copy-links` to rsync so Certbot `live/` symlinks are copied as certificate files.
- `certificates_replicate_dsm_root_cert_required` (bool, default `false`): fail when a matching root certificate cannot be found in DSM's trust store. Disabled by default because Let's Encrypt `chain.pem` commonly contains only the intermediate certificate, such as E7.
- `certificates_replicate_dsm_cert_src`, `certificates_replicate_dsm_chain_src`, `certificates_replicate_dsm_fullchain_src`, `certificates_replicate_dsm_privkey_src`: optional source filename overrides passed to the upstream script when set.
- `certificates_replicate_dsm_ssh_private_key_path` (string, default empty): optional SSH private key used by rsync. This is useful when DSM Task Scheduler runs as root but the key lives in another user's home directory.
- `certificates_replicate_dsm_ssh_strict_host_key_checking` (bool, default `true`): set SSH `StrictHostKeyChecking`.
- `certificates_replicate_dsm_ssh_known_hosts_file` (string, default empty): optional SSH known_hosts file used by rsync.
- `certificates_replicate_dsm_ssh_extra_args` (list[string], default `[]`): extra SSH arguments appended to the rsync SSH command.

## Example

```yaml
---
- name: Configure DSM certificate replication
  hosts: synology
  gather_facts: false
  become: false

  roles:
    - role: rolandu.homeops.certificates_replicate_dsm
      vars:
        certificates_replicate_dsm_domain: example.com
        certificates_replicate_dsm_remote_user: certsync
        certificates_replicate_dsm_remote_host: certbot.example.com
        certificates_replicate_dsm_remote_base_dir: /srv/certificates/live/example.com
        certificates_replicate_dsm_cert_desc: "*.example.com"
        certificates_replicate_dsm_cert_src: cert.pem
        certificates_replicate_dsm_chain_src: chain.pem
        certificates_replicate_dsm_fullchain_src: fullchain.pem
        certificates_replicate_dsm_privkey_src: privkey.pem
        certificates_replicate_dsm_ssh_private_key_path: /var/services/homes/admin/.ssh/id_ed25519
```

## DSM Task Scheduler

After the role runs, create a DSM Task Scheduler user-defined script:

1. Open Control Panel -> Task Scheduler.
2. Create a scheduled user-defined script.
3. Set the user to `root`.
4. Paste the generated helper path printed by the role, for example:

```bash
/var/services/homes/admin/dsm-cert-update/dsm-task-replicate-certificates.sh
```

Manual dry run:

```bash
DRY_RUN=true /var/services/homes/admin/dsm-cert-update/replicate-certificates.sh
```

Manual real run:

```bash
/var/services/homes/admin/dsm-cert-update/replicate-certificates.sh
```

This role does not include a Docker scenario test. The behavior depends on DSM certificate internals, DSM Task Scheduler, and a real certificate source host.

## Notes

The rendered script differs from the upstream script in a few operationally important ways:

- it resolves the DSM archive ID by `CERT_DESC` instead of blindly using `_archive/DEFAULT`
- it logs command output and real exit codes more verbosely
- it supports an explicit SSH private key and known_hosts file for rsync
- it uses `rsync --copy-links` by default so Certbot `live/` symlinks are copied as real files
