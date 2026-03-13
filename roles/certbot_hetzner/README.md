# certbot_hetzner

Install Certbot with a Hetzner DNS-01 helper, deploy the hcloud CLI, and set up a cron job to renew certificates defined in `certbot_lineages`.

The role installs required tools, deploys scripts under `/opt/certbot-scripts` by default, stores certbot state/certificates under `/srv/certificates` by default, and registers a cron entry for periodic renewals.

## Defaults and Validation

All role defaults are defined in `defaults/main.yml`.

The role fails fast when required settings are missing or invalid:
- required: `hcloud_zone`, `hcloud_token`, `certbot_email`, `certbot_lineages`
- required path/group settings are validated for non-empty absolute paths and valid modes
- each lineage item must include non-empty `domain` and `certname`

The generated runner script also validates required runtime settings before calling certbot.

## Role Variables

- `use_venv` (bool, default: `false`): install Certbot into a dedicated venv instead of OS packages.
- `certbot_venv_path` (string, default: `/opt/certbot/venv`): venv path when `use_venv` is true.
- `install_certbot_nginx` (bool, default: `false`): also install the `certbot-nginx` plugin in the venv.
- `hcloud_download_url` (string): tarball URL for the hcloud CLI.
- `hcloud_binary_path` (string, default: `/usr/local/bin/hcloud`): location for the hcloud binary.

- `certbot_scripts_dir` (string, default: `/opt/certbot-scripts`): directory for role-managed scripts.
- `certbot_runner_script_path` (string, default: `{{ certbot_scripts_dir }}/certbot-script.sh`): certbot runner path.
- `certbot_auth_hook_path` (string, default: `{{ certbot_scripts_dir }}/dns-auth-hetzner.sh`): Hetzner DNS auth hook path.

- `certbot_certificates_dir` (string, default: `/srv/certificates`): certificate/state root.
- `certbot_config_dir` (string, default: `{{ certbot_certificates_dir }}`): certbot `--config-dir`.
- `certbot_work_dir` (string, default: `{{ certbot_certificates_dir }}/work`): certbot `--work-dir`.
- `certbot_logs_dir` (string, default: `{{ certbot_certificates_dir }}/logs`): certbot `--logs-dir`.
- `certbot_cron_log_file` (string, default: `{{ certbot_logs_dir }}/certbot-script.log`): cron log target.
- `certbot_cron_schedule` (string, default: `22 3,15 * * *`): full cron schedule expression.

- `certbot_shared_group` (string, default: `certificates`): group granted shared read/write certificate access.
- `certbot_dir_mode` (string, default: `2770`): mode for certificate directories (`setgid` keeps group inheritance).
- `certbot_file_mode` (string, default: `0660`): mode for certificate files.

- `hcloud_zone` (string, required): Hetzner DNS zone name or ID.
- `hcloud_token` (string, required): Hetzner API token with DNS write permissions.
- `hcloud_ttl` (int, default: `60`): TTL for `_acme-challenge` TXT records.
- `grace_seconds` (int, default: `hcloud_ttl`): extra wait after TXT propagation to allow caches to expire.

- `certbot_email` (string, required): email for Certbot registration.
- `certbot_lineages` (list[dict], required): domains to issue/renew. Each item needs `domain` and `certname`.

## Manual Commands

Commands below reference current role defaults:
- runner: `/opt/certbot-scripts/certbot-script.sh`
- DNS hook: `/opt/certbot-scripts/dns-auth-hetzner.sh`
- certbot config/work/log dirs: `/srv/certificates`, `/srv/certificates/work`, `/srv/certificates/logs`

Dry run via runner (recommended):

```bash
sudo DRYRUN=1 /opt/certbot-scripts/certbot-script.sh
```

Real run via runner:

```bash
sudo /opt/certbot-scripts/certbot-script.sh
```

Dry-run renewal check for all existing lineages:

```bash
sudo certbot renew --dry-run \
  --config-dir /srv/certificates \
  --work-dir /srv/certificates/work \
  --logs-dir /srv/certificates/logs
```

Real renewal run for all existing lineages:

```bash
sudo certbot renew \
  --config-dir /srv/certificates \
  --work-dir /srv/certificates/work \
  --logs-dir /srv/certificates/logs
```

## Example

```yaml
- hosts: vpn
  roles:
    - role: certbot_hetzner
      vars:
        use_venv: true
        certbot_shared_group: certificates
        hcloud_zone: "example.com"
        hcloud_token: "{{ vault_hcloud_token }}"
        certbot_email: admin@example.com
        certbot_lineages:
          - { domain: "example.com", certname: "example.com" }
          - { domain: "*.example.com", certname: "wildcard.example.com" }
```
