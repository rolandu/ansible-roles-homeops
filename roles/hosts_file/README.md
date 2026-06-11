# hosts_file

Manage persistent host name entries in `/etc/hosts`.

This role is intended for hosts that need a small set of stable internal names
without depending on local, VPN, or self-hosted DNS. It uses the same
`domain`/`answer` shape as the `adguardhome_docker` role's `adguard_rewrites`,
so the same rewrite data can be reused for local hosts-file entries.

**This is an administrative role and it assumes privileged execution (`become: true`) works on the target host.**

## Role Variables

- `hosts_file_rewrites` (list, default: `{{ adguard_rewrites | default([]) }}`):
  hosts entries to manage. Each entry must have `domain` and `answer`.
  (This is the same format that the adguardhome_docker role uses.)
- `hosts_file_manage_cloud_init` (bool, default: `true`): when `/etc/cloud`
  exists, write a cloud-init drop-in so cloud-init only manages the local
  hostname entry.
- `hosts_file_cloud_init_mode` (string, default: `localhost`): cloud-init
  `manage_etc_hosts` value. This role currently supports only `localhost`.
- `hosts_file_cloud_init_config_path` (string, default:
  `/etc/cloud/cloud.cfg.d/99-homeops-hosts-file.cfg`): cloud-init drop-in path.
- `hosts_file_validate` (bool, default: `true`): run `getent hosts` for each
  configured domain after writing `/etc/hosts`.

Each `hosts_file_rewrites` entry supports:

- `domain`: host name to resolve locally. Wildcards are not supported.
- `answer`: IPv4 or IPv6 address. CNAME-style answers are not supported because
  `/etc/hosts` only maps names to addresses.

## Example

```yaml
- hosts: dns_servers
  become: true
  roles:
    - role: hosts_file
      vars:
        hosts_file_rewrites:
          - domain: monitoring.rolandu.net
            answer: 192.168.1.20
```

Reuse AdGuard Home rewrites directly:

```yaml
adguard_rewrites:
  - domain: monitoring.rolandu.net
    answer: 192.168.1.20

hosts_file_rewrites: "{{ adguard_rewrites }}"
```

## Cloud-init

Some Debian/Ubuntu cloud images configure cloud-init with
`manage_etc_hosts: true`, which causes `/etc/hosts` to be regenerated from a
template on boot. When `hosts_file_manage_cloud_init` is enabled and
`/etc/cloud` exists, this role writes:

```yaml
manage_etc_hosts: localhost
```

This keeps cloud-init responsible for the host's own `127.0.1.1` hostname entry
while leaving the rest of `/etc/hosts` available for Ansible's managed block.

The role does not manage `/etc/resolv.conf` or system DNS resolver settings.
