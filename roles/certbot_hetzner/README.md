# certbot_hetzner

Install Certbot with a Hetzner DNS-01 helper, deploy the hcloud CLI, and set up a cron job to renew certificates defined in `certbot_lineages`.

The role installs required tools, deploys `/etc/letsencrypt/dns-auth-hetzner.sh` and `/etc/letsencrypt/certbot-script.sh`, then registers a cron entry to renew twice daily.

## Role Variables

- `use_venv` (bool, default: false): install Certbot into a dedicated venv instead of OS packages.
- `certbot_venv_path` (string, default: `/opt/certbot`): venv path when `use_venv` is true.
- `install_certbot_nginx` (bool, default: false): also install the `certbot-nginx` plugin in the venv.
- `hcloud_download_url` (string): tarball URL for the hcloud CLI (defaults to latest release).
- `hcloud_binary_path` (string, default: `/usr/local/bin/hcloud`): location for the hcloud binary.
- `hcloud_zone` (string, required): Hetzner DNS zone name or ID.
- `hcloud_token` (string, required): Hetzner API token with DNS write permissions.
- `hcloud_ttl` (int, default: 60): TTL for `_acme-challenge` TXT records.
- `grace_seconds` (int, default: `hcloud_ttl`): extra wait after TXT propagation to allow caches to expire.
- `certbot_email` (string, required): email for Certbot registration.
- `certbot_lineages` (list[dict], required): domains to issue/renew. Each item needs `domain` and `certname`.

## Example

```yaml
- hosts: vpn
  roles:
    - role: certbot_hetzner
      vars:
        use_venv: true
        install_certbot_nginx: false
        hcloud_zone: "example.com"
        hcloud_token: "{{ vault_hcloud_token }}"
        certbot_email: admin@example.com
        certbot_lineages:
          - { domain: "example.com", certname: "example.com" }
          - { domain: "*.example.com", certname: "wildcard.example.com" }
```

