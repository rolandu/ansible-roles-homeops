# keepalived_dns_vip

Manage a Keepalived VRRP floating IP for a pair or small set of redundant DNS servers. The role installs Keepalived and `dig`, renders a DNS health-check script, renders `/etc/keepalived/keepalived.conf`, and starts the service.

**This is an administrative role and it assumes privileged execution (`become: true`) works on the target host.**

## Role Variables

- `keepalived_vip` (string, required): floating IP with prefix length, for example `192.0.2.53/24`.
- `keepalived_auth_pass` (string, required): VRRP PASS value. Keepalived only supports a short value here, so this role requires 1-8 characters from `A-Za-z0-9_.-`. Store it in Ansible Vault.
- `keepalived_interface` (string, default: `{{ ansible_default_ipv4.interface | default('eth0') }}`): interface that owns the VIP.
- `keepalived_instance_name` (string, default: `VI_DNS`): VRRP instance name.
- `keepalived_state` (string, default: `BACKUP`): `MASTER` or `BACKUP`.
- `keepalived_priority` (int, default: `100`): VRRP priority. Higher wins.
- `keepalived_virtual_router_id` (int, default: `53`): VRRP router ID. Must be unique on the L2 segment.
- `keepalived_packages` (list, default: `keepalived`, `dnsutils`): packages installed on Debian-family hosts.
- `keepalived_config_path` (string, default: `/etc/keepalived/keepalived.conf`): managed Keepalived config path.
- `keepalived_dns_check_script_path` (string, default: `/usr/local/sbin/keepalived-check-dns.sh`): managed health-check script path.
- `keepalived_dns_check_server` (string, default: `127.0.0.1`): DNS server queried by the local health check.
- `keepalived_dns_check_port` (int, default: `53`): DNS server port queried by the local health check.
- `keepalived_dns_check_name` (string, default: `example.com`): DNS name queried by the health check. Prefer an internal name that must be served by your DNS stack.
- `keepalived_dns_check_type` (string, default: `A`): DNS record type for the health check.
- `keepalived_dns_check_timeout` / `keepalived_dns_check_tries` (ints, defaults: `1` / `1`): `dig` timeout and retry count.
- `keepalived_dns_check_interval` / `keepalived_dns_check_fall` / `keepalived_dns_check_rise` (ints, defaults: `2` / `2` / `2`): Keepalived script tracking timing.
- `keepalived_validate_config` (bool, default: `true`): run `keepalived -t` before service changes.
- `keepalived_run_dns_check` (bool, default: `true`): run the DNS health check once during the play.
- `keepalived_manage_service` (bool, default: `true`): enable and start the Keepalived service.

## Example

```yaml
- name: Configure DNS floating IP
  hosts: dns_servers
  become: true
  roles:
    - role: keepalived_dns_vip
      vars:
        keepalived_interface: eth0
        keepalived_vip: "192.0.2.53/24"
        keepalived_virtual_router_id: 53
        keepalived_auth_pass: "{{ vault_keepalived_auth_pass }}"
        keepalived_dns_check_name: "dns-test.example.net"
```

Set per-host priorities in `host_vars`:

```yaml
# host_vars/dns-01/keepalived_dns_vip.yml
keepalived_state: MASTER
keepalived_priority: 150

# host_vars/dns-02/keepalived_dns_vip.yml
keepalived_state: BACKUP
keepalived_priority: 100
```

## DNS Health Check

The health check requires a non-empty `dig +short` answer. This is intentional: checking only that `keepalived` is alive can leave clients pointing at a DNS VIP on a host where the DNS service is dead.

For AdGuard Home, ensure DNS listens on all interfaces or explicitly on the VIP, for example `0.0.0.0:53` or the floating address.

## Firewall

VRRP uses IP protocol `112`, not TCP or UDP. Allow protocol `112` between the participating DNS nodes on the LAN interface. With an iptables-based firewall, that is typically a rule like:

```bash
iptables -A INPUT -i eth0 -p 112 -s 192.0.2.2 -j ACCEPT
```

Also allow DNS from the client networks that should use the floating IP.

## Testing Notes

A Docker scenario can verify package installation, templating, config validation, and idempotence. A realistic VRRP failover test is not reliable on an ordinary Docker bridge network because VRRP uses multicast and raw IP protocol `112`. Testing VIP movement usually needs privileged network namespaces, VMs, host networking, or a macvlan/ipvlan setup that behaves like the target L2 network.
