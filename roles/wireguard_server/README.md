# wireguard_server

Native WireGuard server role for Debian/Ubuntu systems.

**This is an administrative role and it assumes privileged execution (`become: true`) works on the target host.**

## Responsibilities

This role:

- installs native WireGuard packages
- creates `/etc/wireguard` and `/etc/wireguard/keys`
- generates and preserves the server private/public key pair
- generates and preserves peer private/public key pairs by default
- generates one client config per peer by default
- optionally generates QR code text files
- fetches generated client configs to the Ansible controller by default
- writes `/etc/wireguard/{{ wireguard_interface }}.conf`
- enables IPv4 forwarding when `wireguard_enable_ipv4_forwarding: true`
- enables IPv6 forwarding when `wireguard_enable_ipv6_forwarding: true`
- enables and starts `wg-quick@{{ wireguard_interface }}`

This role does **not**:

- open firewall ports
- configure NAT
- configure UFW
- configure nftables
- configure iptables
- install configs on remote client machines

## Variables

- `wireguard_interface` (default: `wg0`): interface and systemd instance name.
- `wireguard_network_name` (default: `home`): logical network name shared with `wireguard_client` for artifact paths.
- `wireguard_port` (default: `51820`): UDP listen port.
- `wireguard_endpoint` (required when client configs are generated for peers): public DNS name or IP clients use to reach the VPN server.
- `wireguard_config_dir` (default: `/etc/wireguard`): WireGuard config directory.
- `wireguard_key_dir` (default: `{{ wireguard_config_dir }}/keys`): private/public key directory.
- `wireguard_interface_addresses` (default: `[10.100.0.1/24]`): addresses assigned to the server's WireGuard interface. These render as `Address` in `wg0.conf`.
- `wireguard_enable_ipv4_forwarding` (default: `true`): manage `net.ipv4.ip_forward`.
- `wireguard_enable_ipv6_forwarding` (default: `true`): manage `net.ipv6.conf.all.forwarding`.
- `wireguard_save_config` (default: `false`): rendered as `SaveConfig`.
- `wireguard_manage_service` (default: `true`): enable/start/restart `wg-quick@<interface>`.
- `wireguard_packages` (default: `wireguard`, `wireguard-tools`): packages installed on Debian-family systems.
- `wireguard_generate_peer_keys_on_server` (default: `true`): generate peer private keys on the VPN server.
- `wireguard_generate_client_configs` (default: `true`): generate client configs from server-side peer keys. Requires `wireguard_generate_peer_keys_on_server: true`.
- `wireguard_client_config_dir` (default: `/opt/wireguard-clients`): server-side output directory for generated client configs and QR text files.
- `wireguard_client_config_generate_qr` (default: `true`): generate terminal QR code text files using `qrencode`.
- `wireguard_client_config_fetch_to_controller` (default: `true`): fetch generated client configs and QR text files to the controller.
- `artifacts_dir` (default: `{{ inventory_dir }}/artifacts`): controller artifact base path.
- `wireguard_client_config_local_dir_base` (default: `{{ artifacts_dir }}/wireguard-clients`): controller WireGuard artifact base.
- `wireguard_client_config_local_dir` (default: `{{ wireguard_client_config_local_dir_base }}/{{ wireguard_network_name }}`): final controller export path.
- `wireguard_dns` (default: empty): default DNS value rendered into generated client configs.
- `wireguard_persistent_keepalive` (default: `25`): default client `PersistentKeepalive`.
- `wireguard_client_config_packages` (default: `qrencode`): packages installed when QR generation is enabled.
- `wireguard_peers` (default: `[]`): peer definitions.

Each peer supports:

- `name` (required): safe filename/key identifier, matching `^[A-Za-z0-9_.-]+$`.
- `addresses` (required): peer tunnel address(es), normally `/32` for IPv4 and `/128` for IPv6.
- `server_allowed_ips` (optional): server-side `AllowedIPs`; defaults to `addresses`.
- `client_allowed_ips` (required when `wireguard_generate_client_configs: true`): client-side routing policy for generated client configs.
- `dns` (optional): DNS value for generated client config; defaults to `wireguard_dns`.
- `persistent_keepalive` (optional): generated client config keepalive; defaults to `wireguard_persistent_keepalive`.
- `public_key` (optional): required only if `wireguard_generate_peer_keys_on_server: false`.

## Example playbook

```yaml
---
- name: Configure WireGuard VPN
  hosts: vpn
  become: true

  roles:
    - role: wireguard_server
```

## Example vars

```yaml
wireguard_interface: wg0
wireguard_network_name: home
wireguard_port: 51820

# Public DNS name or public IP that clients use to reach the VPN.
# Do not use ansible_host unless that is truly the public VPN endpoint.
wireguard_endpoint: vpn.example.com

wireguard_interface_addresses:
  - 10.100.0.1/24
  # - fd42:100:100::1/64

wireguard_dns: "10.100.0.1"

wireguard_enable_ipv4_forwarding: true
wireguard_enable_ipv6_forwarding: true

wireguard_persistent_keepalive: 25

# Generated configs are fetched to:
# {{ artifacts_dir }}/wireguard-clients/{{ wireguard_network_name }}/
wireguard_generate_client_configs: true
wireguard_client_config_fetch_to_controller: true

wireguard_peers:
  - name: phone
    addresses:
      - 10.100.0.2/32
    client_allowed_ips: "0.0.0.0/0"  # for full tunnel VPN
    dns: "10.100.0.1"
    persistent_keepalive: 25

  - name: laptop
    addresses:
      - 10.100.0.3/32
    client_allowed_ips: "10.100.0.0/24, 192.168.1.0/24"
    dns: "10.100.0.1"
    persistent_keepalive: 25
```

Generated client configs contain peer private keys. By default, they are written
on the VPN server under:

```text
/opt/wireguard-clients/
```

and fetched to the controller under:

```text
{{ artifacts_dir }}/wireguard-clients/{{ wireguard_network_name }}/
```

The [wireguard_client](../wireguard_client/README.md) role installs one of
those fetched configs on an actual client host.

`wireguard_interface_addresses` is the server's own tunnel address, not just a
network declaration. If you want the WireGuard tunnel network to be all of
`10.100.*.*`, use a `/16` interface address:

```yaml
wireguard_interface_addresses:
  - 10.100.0.1/16
```

Peers should still normally use single-host addresses:

```yaml
wireguard_peers:
  - name: phone
    addresses:
      - 10.100.0.2/32
```

## Routing additional networks

Additional networks that clients should reach through the VPN are controlled by
each peer's client-side `client_allowed_ips`, not by
`wireguard_interface_addresses`.

For example, if:

- the WireGuard tunnel network is `10.100.0.0/16`
- the VPN server can also reach a physical LAN at `10.50.0.0/16`

then a split-tunnel peer can route both ranges through the VPN like this:

```yaml
wireguard_interface_addresses:
  - 10.100.0.1/16

wireguard_peers:
  - name: laptop
    addresses:
      - 10.100.0.2/32
    client_allowed_ips: "10.100.0.0/16, 10.50.0.0/16"
```

The server-side peer `AllowedIPs` should usually remain only the peer tunnel
address, for example `10.100.0.2/32`. Do not put `10.50.0.0/16` in
`server_allowed_ips` unless that network is behind the peer. In normal home VPN
setups where `10.50.0.0/16` is behind or directly reachable from the server,
the Linux routing table and firewall/NAT policy handle that path.

## Firewall requirements

Firewall and NAT policy belong in a separate firewall role or host-specific
firewall variables. This keeps `wireguard_server` responsible for WireGuard
itself, while the firewall role remains the single owner of packet filtering,
forwarding policy, NAT, rule order, and teardown.

The WireGuard role still manages the kernel forwarding sysctls needed for
routing through the VPN server:

- `net.ipv4.ip_forward`, controlled by `wireguard_enable_ipv4_forwarding`
- `net.ipv6.conf.all.forwarding`, controlled by `wireguard_enable_ipv6_forwarding`

At minimum, the firewall role should allow inbound WireGuard traffic:

```text
WAN -> VPN server UDP/51820 allow
```

If VPN clients should access the home LAN, allow forwarding from the WireGuard interface/subnet to the LAN:

```text
wg0 / 10.100.0.0/24 -> 192.168.1.0/24 allow
```

Return traffic must also work. Choose one model:

- NAT model: masquerade VPN client traffic behind the VPN server's LAN IP.
- Routed model: add a static route on the LAN router, for example `10.100.0.0/24` via the VPN server LAN IP.

For full tunnel clients using `client_allowed_ips: "0.0.0.0/0"`, the firewall role needs forwarding from `wg0` to WAN plus NAT/masquerade from the VPN subnet to WAN unless your network routes it differently.

For IPv6 full tunnel clients using `client_allowed_ips: "0.0.0.0/0, ::/0"`, prefer a routed IPv6 prefix. Do not assume IPv6 NAT; design IPv6 routing and firewalling deliberately before enabling `::/0`.

If VPN clients use internal DNS, allow them to reach the resolver:

```text
10.100.0.0/24 -> 10.100.0.1 UDP/TCP 53 allow
10.100.0.0/24 -> 192.168.1.1 UDP/TCP 53 allow
```

This role intentionally does not render `PostUp` or `PostDown` firewall/NAT rules into `wg0.conf`.

### Example with a separate firewall role

If your firewall role accepts allowed port lists and additional iptables rules,
a typical NAT-based WireGuard server can look like this:

```yaml
firewall_allowed_tcp_ports:
  - "22" # SSH
  - "53" # DNS, only if this host serves DNS over TCP

firewall_allowed_udp_ports:
  - "53" # DNS, only if this host serves DNS
  - "51820" # WireGuard; match wireguard_port if you override it

firewall_additional_rules:
  - "iptables -I FORWARD 1 -i wg0 -o eth0 -j ACCEPT"
  - "iptables -I FORWARD 2 -i eth0 -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  - "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
```

Adjust `wg0`, `eth0`, and `51820` if your WireGuard interface, WAN/LAN
interface, or `wireguard_port` differ.

The `MASQUERADE` rule is the simple home-lab model: LAN and internet hosts see
traffic as coming from the VPN server, so they do not need a route back to the
WireGuard subnet. If you prefer routed networking, omit NAT and add a route on
the LAN router instead, for example `10.100.0.0/24` via the VPN server's LAN IP.

For split tunnel clients, make sure `client_allowed_ips` includes every network
the client should route through the tunnel. If clients should use DNS on the VPN
server, include the VPN subnet or at least the DNS server address:

```yaml
client_allowed_ips: "10.100.0.0/24, 192.168.1.0/24"
```

or:

```yaml
client_allowed_ips: "10.100.0.1/32, 192.168.1.0/24"
```

## Verification

On the server:

```bash
sudo systemctl status wg-quick@wg0
sudo wg show
ip address show wg0
sysctl net.ipv4.ip_forward
sysctl net.ipv6.conf.all.forwarding
```

## Important notes

- Peer private keys are generated on the VPN server for operational simplicity.
- Back up `/etc/wireguard/keys`.
- Existing key files are not regenerated unless manually deleted.
- If `/etc/wireguard/keys/server_private.key` is lost, existing clients must be reconfigured.
- Removing a peer from `wireguard_peers` removes it from the generated server config, but old key files may remain on disk intentionally.
- Manual key cleanup should be deliberate.
