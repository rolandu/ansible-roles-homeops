# openvpn_server

Provision an OpenVPN server with EasyRSA, generate client certificates, export inline `.ovpn` bundles locally, and configure routing/NAT for a LAN behind the server.

## Role Variables

- `openvpn_server_name` (string, default: `server`): systemd unit and certificate name.
- `openvpn_network` / `openvpn_netmask` (strings): VPN subnet and netmask.
- `openvpn_port` (int, default: 1194) and `openvpn_proto` (string, default: `udp`): listener settings.
- `home_lan_network` / `home_lan_netmask` (strings): LAN behind the VPN gateway; pushed to clients.
- `openvpn_full_tunnel` (bool, default: false): when true, push default route; otherwise split-tunnel to `home_lan_network`.
- `openvpn_remote_host` (string, required for clients): public FQDN/IP used in exported `.ovpn`.
- `openvpn_clients` (list, default: `['homegateway']`): client names to build and export.
- `gateway_client_name` (string, default: `homegateway`): client that receives a CCD route to `home_lan_network`.
- `openvpn_client_export_dir` (string, default: `/root/openvpn-clients`): export path on the server.
- `openvpn_client_local_dir` (string, default: `{{ inventory_dir }}/artifacts/{{ inventory_hostname }}/openvpn-clients`): export path on the controller (delegated tasks).
- `easyrsa_dir`, `openvpn_server_dir`, `ccd_dir` (strings): paths for PKI and server/CCD files.

## Example

```yaml
- hosts: vpn_server
  vars:
    openvpn_remote_host: "vpn.example.com"
    openvpn_clients:
      - homegateway
      - laptop1
  roles:
    - openvpn_server
```

Running the role installs OpenVPN + EasyRSA, builds CA/server/client certs, writes server config, starts `openvpn-server@<name>`, exports `.ovpn` files locally under `{{ openvpn_client_local_dir }}`, and enables NAT for `10.200.0.0/24`.
