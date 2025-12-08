# openvpn_client

Install and configure an OpenVPN client from an exported `.ovpn` profile, handling both `openvpn-client@` and legacy `openvpn@` systemd units.

## Role Variables

- `openvpn_client_name` (string, default: `client`): profile name; expects `<name>.ovpn` on the controller.
- `openvpn_client_local_dir` (string, default: `{{ inventory_dir }}/artifacts/{{ hostvars[groups['vpn_server'][0]].inventory_hostname }}/openvpn-clients`): controller path that already contains the exported `.ovpn`.
- `openvpn_client_enable_ip_forward` (bool, default: true): enable IPv4 forwarding (for gateway clients).

## Example

```yaml
- hosts: vpn_clients
  vars:
    openvpn_client_name: laptop1
    openvpn_client_local_dir: "{{ inventory_dir }}/artifacts/vpn-server/openvpn-clients"
    openvpn_client_enable_ip_forward: false
  roles:
    - openvpn_client
```

The role copies `<name>.ovpn` to `/etc/openvpn[/client]/<name>.conf`, ensures the service is enabled/started, and optionally turns on IPv4 forwarding.
