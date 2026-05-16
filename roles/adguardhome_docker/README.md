# adguardhome_docker

Deploy AdGuard Home with Docker Compose (host networking), render an `AdGuardHome.yaml`, and (optionally) run a local DNS test against `127.0.0.1:53`.

**This is an administrative role and it assumes privileged execution (`become: true`) works on the target host.**

## Role Variables

- `adguard_admin_password_bcrypt` (string, required): bcrypt hash for the admin user (role fails if empty).
- `app_root_dir` (string, default: `/opt`): base path for app installs (global).
- `data_root_dir` (string, default: `/srv`): base path for service data (global).
- `docker_app_base_dir` (string, default: `{{ app_root_dir }}/docker`): base path for docker app stacks (global).
- `docker_data_base_dir` (string, default: `{{ data_root_dir }}/docker-data`): base path for docker data (global).
- `adguard_stack_dir` (string, default: `{{ docker_app_base_dir }}/adguardhome`): compose project directory.
- `adguard_data_dir` (string, default: `{{ docker_data_base_dir }}/adguardhome`): base path for persistent data.
- `adguard_conf_dir` / `adguard_work_dir` (string): derived from `adguard_stack_dir` and `adguard_data_dir`.
- `adguard_web_bind` / `adguard_web_port` (defaults: `127.0.0.1` / `3000`): admin UI listener.
- `adguard_dns_bind` / `adguard_dns_port` (defaults: `0.0.0.0` / `53`): DNS listener.
- `adguard_dnssec_enabled` (bool, default: `true`): enable DNSSEC validation.
- `adguard_upstreams` / `adguard_fallback_dns` / `adguard_bootstrap_dns` / `adguard_blocklists` / `adguard_rewrites` / `adguard_user_rules`: DNS config blocks.
- `adguard_image` (default: `adguard/adguardhome`) and `adguard_image_tag` (default: `latest`).
- `adguard_run_test` (bool, default: `true`): run a DNS query via `dig` against `127.0.0.1:53`.
- `adguard_test_domain` (string, default: `example.com`): domain used for the DNS test.
- `adguard_teardown` (bool, default: `false`): stop the AdGuard container without deleting data; re-enables the systemd-resolved stub listener if present.

## Usage

Ensure Docker + the Compose v2 plugin are installed on the target, and the `community.docker` collection is available. If `adguard_run_test` is enabled, install `dig` (package `dnsutils` on Debian/Ubuntu, `bind-utils` on RHEL/Fedora).

## Password hash

Generate a bcrypt hash and store it in `adguard_admin_password_bcrypt`.

```bash
htpasswd -nbB admin 'your-password' | cut -d: -f2
```

Or with Python (requires `bcrypt`):

```bash
python3 - <<'PY'
import bcrypt
print(bcrypt.hashpw(b"your-password", bcrypt.gensalt()).decode())
PY
```

## Example

```yaml
- hosts: dns
  roles:
    - role: adguardhome_docker
      vars:
        adguard_admin_password_bcrypt: "{{ vault_adguard_admin_bcrypt }}"
        adguard_web_bind: "127.0.0.1"
        adguard_dns_bind: "0.0.0.0"
        adguard_upstreams:
          - "tls://dns.quad9.net"
          - "tls://1.1.1.1"
```

Teardown example (stop containers, restore systemd-resolved stub):

```bash
ansible-playbook <playbook>.yml -l <host> -e adguard_teardown=true
```
