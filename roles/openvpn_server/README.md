# openvpn_server

Provision one or more community OpenVPN servers with EasyRSA PKI, per-client CCDs, and exported inline `.ovpn` bundles on the controller. The role assumes you want to:
- Stand up a server (or several) with minimal defaults.
- Onboard one or more gateway clients that may advertise a LAN behind them.
- Generate configs for roaming/local clients, including export-only clients that are not managed by Ansible.

## Variables

- `openvpn_config` (list, required): VPN definitions. Each entry supports:
  - `vpn_name` (required): logical VPN name; used for systemd unit/config filenames and certificate CNs.
  - `server_hostname` (required): inventory/host name that should host this VPN (matched against `inventory_hostname`, `ansible_hostname`, or `ansible_fqdn`).
  - `network` / `netmask` (required): VPN subnet.
  - `port` (default: `1194`), `proto` (default: `udp4`; valid options: `udp`, `udp4`, `udp6`, `tcp`, `tcp4`, `tcp6`).
  - `openvpn_remote_host` (string, required for clients): hostname/IP clients connect to (defaults to `server_hostname`).
  - `home_lan_network`, `home_lan_netmask` (optional): advertise a LAN behind a gateway; if set, the role emits `route`/`iroute`/pull-filter bits as appropriate for client types.
  - `openvpn_full_tunnel` (bool, default: `false`): push `redirect-gateway` to clients.
  - `openvpn_ca_passphrase` (required): passphrase to protect the CA key; no default.
  - `openvpn_mgmt_password` (required): password used to enable the management socket; the role writes a password file and adds a `management <bind> <port> <file>` line.
  - `openvpn_mgmt_port`, `openvpn_mgmt_bind` (optional): address/port for the management socket (only used when `openvpn_mgmt_password` is set; defaults: `127.0.0.1` / `7505`).
  - `openvpn_client_export_dir` (default: `/root/openvpn-clients`): server-side export path for generated client bundles.
  - `openvpn_server_dir` (default: `/etc/openvpn/server`; owned by `openvpn:openvpn`, 0750), `easyrsa_dir` (default: `/etc/openvpn/easy-rsa`), `ccd_dir` (default: `/etc/openvpn/ccd`; `openvpn:openvpn`, `0750`, CCD files `0640`).
  - `openvpn_client_to_client` (bool, default: `false`): enable `client-to-client` to allow traffic between VPN clients inside OpenVPN.
  - `clients` (list): client definitions. Fields: `name` (required), `type` (`gateway`|`roaming`|`local`, default `roaming`), `static_ip` (optional, for CCD if set), `managed` (bool, default `true`; set `false` to export only and skip client role).
- `openvpn_default_*` variables control defaults applied when the fields above are omitted:
  - `openvpn_default_port` (default: `1194`), `openvpn_default_proto` (default: `udp4`), `openvpn_default_full_tunnel` (default: `false`).
  - `openvpn_default_client_export_dir` (default: `/root/openvpn-clients`), `openvpn_default_server_dir` (default: `/etc/openvpn/server`), `openvpn_default_easyrsa_dir` (default: `/etc/openvpn/easy-rsa`), `openvpn_default_ccd_dir` (default: `/etc/openvpn/ccd`).
  - `openvpn_default_clients` (default: `[]`) if no clients list is set.
  - `openvpn_default_mgmt_port` (default: `7505`), `openvpn_default_mgmt_bind` (default: `127.0.0.1`).
- `openvpn_client_local_dir_base` (string, default: `{{ inventory_dir }}/artifacts`): base path on the controller for exported configs. Files land under `<base>/<vpn_name>/openvpn-clients/<vpn_name>_<client>.ovpn`.

Protocol note: we default to `udp4` to avoid IPv6 blackholes and keep connects quick; switch to `udp6`/`udp`/`tcp*` only if you need IPv6 or TCP traversal.

### Client types
- `gateway`: may serve a LAN behind it; CCD gets `iroute` for `home_lan_*`, and clients get LAN route guards/pull-filters accordingly. Gateway nodes also enable forwarding/rp_filter loosening in the client role.
- `roaming`: typical laptop/remote user; accepts pushed LAN routes and has no forwarding enabled.
- `local`: meant to stay on the home LAN; receives pull-filter to ignore LAN routes (prevents hairpin), but otherwise acts like roaming. Good for export-only static devices.

## Example vars

```yaml
openvpn_config:
  # Maximum example: shows every knob and multiple client types
  - vpn_name: home
    server_hostname: homeserver
    network: 10.200.0.0
    netmask: 255.255.255.0
    proto: udp4
    port: 1194
    home_lan_network: 10.35.0.0
    home_lan_netmask: 255.255.255.0
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
    clients:
      - { name: homegateway, type: gateway, static_ip: 10.200.0.10 }
      - { name: laptop1, type: roaming }
      - { name: fileserver, type: local, managed: false }  # export-only

  # Minimum example: only required fields, all defaults applied
  - vpn_name: lab
    server_hostname: labserver
    network: 10.210.0.0
    netmask: 255.255.255.0
    openvpn_remote_host: "lab.example.com"
    clients:
      - { name: laptop1 }
```

The role installs OpenVPN + EasyRSA, builds CA/server/client certs, writes `openvpn-server@<vpn_name>` configs under `openvpn_server_dir`, enforces forwarding/rp_filter sysctls, renders CCD files, and exports inline client bundles to the controller under `openvpn_client_local_dir_base`.

- A dedicated system user/group `openvpn` is created; the service runs as that user and owns runtime assets (configs, server keys, CCDs, export dir). "Other" has no access to these paths.

- Static IP guidance: place CCD/static addresses well outside your expected dynamic pool (e.g., `... .200` upward if you have only a handful of dynamic clients). OpenVPN does not reserve static ranges automatically, so avoid overlaps manually.

## Running multiple servers on the same host
Set unique values per VPN to avoid collisions:
- `openvpn_server_dir`: use a per-VPN directory (e.g., `/etc/openvpn/server-home`, `/etc/openvpn/server-lab`) so `server.crt/key`, `dh.pem`, `ta.key` don’t overwrite each other.
- `ccd_dir`: per-VPN CCD directories to avoid client-name clashes.
- `openvpn_client_export_dir`: per-VPN export path on the server, if you rely on server-side exports.
- `port` (and `proto`): ensure listener sockets don’t conflict.
- `openvpn_mgmt_port` (if management is enabled): unique per VPN.
