# openvpn_server

Provision one or more community OpenVPN servers with EasyRSA PKI, per-client CCDs, and exported inline `.ovpn` bundles on the controller. See the client role for how those exports are consumed and managed: [openvpn_client](../openvpn_client/README.md). The role assumes you want to:
- Stand up a server (or several) with minimal defaults.
- Onboard one or more gateway clients that may advertise LANs behind them.
- Generate configs for roaming/local clients, including export-only clients that are not managed by Ansible.

**This is an administrative role and it assumes privileged execution (`become: true`) works on the target host.**

## Variables

- `openvpn_config` (list, required): VPN definitions. Each entry supports:
  - `vpn_name` (required): logical VPN name; used for systemd unit/config filenames and certificate CNs.
  - `server_hostname` (required): inventory/host name that should host this VPN (matched against `inventory_hostname`, `ansible_hostname`, or `ansible_fqdn`).
  - `network` / `netmask` (required): VPN subnet.
  - `port` (default: `1194`), `proto` (default: `udp`; valid options: `udp`, `tcp`), `dual_stack` (bool, default: `true`): when `true`, listeners use `udp6`/`tcp6` and clients get both `remote ... <proto>6` and `<proto>4`; when `false`, listeners use `udp4`/`tcp4` and clients get only `... <proto>4`.
  - `openvpn_remote_host` (string, required for clients): hostname/IP clients connect to (defaults to `server_hostname`).
  - Gateway LAN routing is defined per gateway client via `gateway_networks` (see clients list below); the role emits `route`/`iroute`/pull-filter bits as appropriate for client types.
  - `openvpn_full_tunnel` (bool, default: `false`): push `redirect-gateway` to clients.
  - `openvpn_ca_passphrase` (required): passphrase to protect the CA key; no default.
  - `openvpn_mgmt_password` (required): password used to enable the management socket; the role writes a password file and adds a `management <bind> <port> <file>` line.
  - `openvpn_mgmt_port`, `openvpn_mgmt_bind` (optional): address/port for the management socket (only used when `openvpn_mgmt_password` is set; defaults: `127.0.0.1` / `7505`).
  - `openvpn_client_export_dir` (default: `/root/openvpn-clients`): server-side export path for generated client bundles.
  - `openvpn_dns_servers` (string|list, optional): DNS server IPs to push to clients (adds `dhcp-option DNS` lines). Accepts a single IP string or a list of IP strings (values should be IP addresses).
  - `openvpn_dns_domain` (string|list, optional; default `"."`): routing domain scope(s) for `dhcp-option DOMAIN-ROUTE`. Accepts a single value (`"."`, `"~."`, `"example.com"`, `"~corp.example"`, etc.) or a list of scopes. Leading `~` is allowed in the input; the role strips it for the server push and re-adds it for NetworkManager clients. Default `.`/`~.` makes the VPN DNS the global resolver; provide one or more suffixes (e.g., `["~corp.example", "~internal.lan"]`) to limit DNS to specific zones.
  - `openvpn_server_dir` (default: `/etc/openvpn/server`; owned by `openvpn:openvpn`, 0750), `easyrsa_dir` (default: `/etc/openvpn/easy-rsa`), `ccd_dir` (default: `/etc/openvpn/ccd`; `openvpn:openvpn`, `0750`, CCD files `0640`).
  - `openvpn_client_to_client` (bool, default: `false`): enable `client-to-client` to allow traffic between VPN clients inside OpenVPN.
  - `clients` (list): client definitions. Fields:
    - `name` (required)
    - `type` (`gateway`|`roaming`|`local`, default `roaming`)
    - `static_ip` (optional, for CCD if set)
    - `gateway_networks` (list, required for `gateway`): one or more networks advertised by this gateway. Each entry supports:
      - `gateway_network_ip` (required)
      - `gateway_network_netmask` (required)
    - `local_ignore_networks` (list, optional; for `local`): networks to ignore when the server pushes LAN routes. Entries use the same schema as `gateway_networks`.
    - `managed` (bool, default `true`; set `false` to export only and skip client role)
    - `revoke` (bool, default `false`): when `true`, revoke the client certificate (if it exists) and refresh the CRL.
    - `dns_helper_script_override` (string, optional; default empty): absolute path to a DNS helper script on the client. When set, the client role uses this path directly and skips helper auto-discovery.
    - `prefer_vpn_dns` (bool, default `true`; impacts NetworkManager clients by setting DNS priority. The OpenVPN systemd client path now always applies pushed DNS using either `systemd-resolved` or `update-resolv-conf` automatically.)
- `openvpn_default_*` variables control defaults applied when the fields above are omitted:
  - `openvpn_default_port` (default: `1194`), `openvpn_default_proto` (default: `udp`), `openvpn_default_dual_stack` (default: `true`), `openvpn_default_full_tunnel` (default: `false`).
  - `openvpn_default_client_export_dir` (default: `/root/openvpn-clients`)
  - `openvpn_default_server_dir` (default: `/etc/openvpn/server`)
  - `openvpn_default_easyrsa_dir` (default: `/etc/openvpn/easy-rsa`)
  - `openvpn_default_ccd_dir` (default: `/etc/openvpn/ccd`)
  - `openvpn_default_clients` (default: `[]`) if no clients list is set.
  - `openvpn_default_mgmt_port` (default: `7505`)
  - `openvpn_default_mgmt_bind` (default: `127.0.0.1`)
  - `openvpn_default_dns_servers` (default: `[]`): DNS servers pushed to clients when `openvpn_dns_servers` is not set.
  - `openvpn_default_dns_domain` (default: `"."`): domain-route scope pushed when DNS servers are present.
  - `openvpn_default_dual_stack` (default: `true`)
- `artifacts_dir` (string, default: `{{ inventory_dir }}/artifacts`): base path on the controller for downloaded artifacts.
- `openvpn_client_local_dir_base` (string, default: `{{ artifacts_dir }}/openvpn-clients`): base path on the controller for exported configs. Files land under `<base>/<vpn_name>/<vpn_name>_<client>.ovpn`.

Protocol note: we default to `udp` with `dual_stack: true`, rendering `proto udp6` on the server so IPv4-mapped connects succeed when `net.ipv6.bindv6only=0` (this role enforces that sysctl). Set `dual_stack: false` to force IPv4-only sockets (`udp4`/`tcp4`).

### Client types

- `gateway`: may serve one or more LANs behind it; CCD gets `iroute` entries for `gateway_networks`, and clients get LAN route guards/pull-filters accordingly. Gateway nodes also enable forwarding/rp_filter loosening in the client role.
- `roaming`: typical laptop/remote/server; accepts pushed LAN routes and has no forwarding enabled.
- `local`: meant to stay on a certain LAN; receives pull-filter to ignore selected LAN routes (prevents hairpin) via `local_ignore_networks`, but otherwise acts like roaming. Good for export-only static devices, like local servers, that are in the same network as a gateway.

## Example vars

```yaml
openvpn_config:
  # Maximum example: shows every knob and multiple client types
  - vpn_name: home
    server_hostname: homeserver
    network: 10.200.0.0
    netmask: 255.255.255.0
    proto: udp
    dual_stack: true
    port: 1194
    openvpn_full_tunnel: true
    openvpn_remote_host: "vpn.example.com"
    openvpn_ca_passphrase: "changeme-ca"
    openvpn_mgmt_password: "changeme-mgmt"
    openvpn_mgmt_bind: "127.0.0.1"
    openvpn_mgmt_port: 7505
    openvpn_server_dir: "/etc/openvpn/server"
    easyrsa_dir: "/etc/openvpn/easy-rsa"
    ccd_dir: "/etc/openvpn/ccd"
    openvpn_client_export_dir: "/root/openvpn-clients"
    openvpn_dns_servers: [ "10.200.0.2", "1.1.1.1" ]
    openvpn_dns_domain: [ "~example.com", "~internal.lan" ]
    clients:
      - name: homegateway
        type: gateway
        static_ip: 10.200.0.10
        gateway_networks:
          - gateway_network_ip: 10.41.0.0
            gateway_network_netmask: 255.255.255.0
          - gateway_network_ip: 10.42.0.0
            gateway_network_netmask: 255.255.255.0
      - { name: laptop1, type: roaming }
      - { name: laptop2, type: roaming }
      - name: phone1
        type: local
        managed: false
        local_ignore_networks:
          - gateway_network_ip: 10.41.0.0
            gateway_network_netmask: 255.255.255.0

  # Minimum example: only required fields, all defaults applied
  - vpn_name: lab
    server_hostname: labserver
    network: 10.210.0.0
    netmask: 255.255.255.0
    openvpn_remote_host: "lab.example.com"
    clients:
      - { name: laptop1 }
```

The role installs OpenVPN + EasyRSA, builds CA/server/client certs, writes `openvpn-server@<vpn_name>` configs under `openvpn_server_dir`, enforces forwarding/rp_filter sysctls, renders CCD files, and exports inline client bundles to the controller under `openvpn_client_local_dir_base/<vpn_name>/<vpn_name>_<client>.ovpn`.

A dedicated system user/group `openvpn` is created; the service runs as that user and owns runtime assets (configs, server keys, CCDs, export dir). "Other" has no access to these paths.

**Static IP guidance**: place CCD/static addresses well outside your expected dynamic pool (e.g., `... .200` upward if you have only a handful of dynamic clients). OpenVPN does not reserve static ranges automatically, so avoid overlaps manually.

## Security defaults
- `tls-crypt` with a per-VPN key (`ta.key`)
- Require client certs (`verify-client-cert require`)
- Enforce cert type checks (`remote-cert-tls client` / `remote-cert-tls server`)
- Enable CRL validation (`crl-verify <openvpn_server_dir>/crl.pem`; CRL generated when missing or when the EasyRSA index changes)
- No password auth (no `auth-user-pass`)
- Use client certs (`<ca>`, `<cert>`, `<key>`)
- No static key mode (no `secret` directive)
- Modern cipher suites (`data-ciphers`/`data-ciphers-fallback`)
- Compression disabled (`allow-compression no`)
- Modern TLS 1.2 minimum (`tls-version-min 1.2`)
- Management interface only accessible locally (`127.0.0.1` default when enabled)
- UDP by default (configurable)

## Running multiple servers on the same host
Set unique values per VPN to avoid collisions:
- `openvpn_server_dir`: use a per-VPN directory (e.g., `/etc/openvpn/server-home`, `/etc/openvpn/server-lab`) so `server.crt/key`, `dh.pem`, `ta.key` don’t overwrite each other.
- `ccd_dir`: per-VPN CCD directories to avoid client-name clashes.
- `openvpn_client_export_dir`: per-VPN export path on the server, if you rely on server-side exports.
- `port` (and `proto`): ensure listener sockets don’t conflict.
- `openvpn_mgmt_port` (if management is enabled): unique per VPN.
