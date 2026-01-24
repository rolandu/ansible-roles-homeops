# openvpn_client

Install and configure an OpenVPN client from exported inline `.ovpn` profiles. This role depends on the server role’s `openvpn_config` and the exported bundles it produces. See the server role for shared schema and server-side behavior: [openvpn_server](../openvpn_server/README.md).

## Variables

- `openvpn_config` (list, required): same structure used by the server role. Each VPN entry’s `clients` list drives which hosts are managed here, including `prefer_vpn_dns` (bool, default `true`) to control whether pushed DNS is preferred.
- `openvpn_client_name` (string, default: `inventory_hostname`): client key to match under each server definition.
- `artifacts_dir` (string, default: `{{ inventory_dir }}/artifacts`): base path on the controller for downloaded artifacts.
- `openvpn_client_local_dir_base` (string, default: `{{ artifacts_dir }}`): where exported `<vpn_name>_<client>.ovpn` files live on the controller.
- `openvpn_client_nm_autoconnect_dispatcher` (bool, default: `true`): install a NetworkManager dispatcher script to bring up the VPN when internet connectivity is detected.

## Behavior

- Iterates over `openvpn_config`; skips any VPN where this client is not listed or is marked `managed: false` (export-only).
- Supports both OpenVPN systemd clients and NetworkManager-managed VPNs; the role auto-selects based on whether NetworkManager is installed.
- `openvpn-client`-path: drops the exported `.ovpn` as a systemd instance config, manages `openvpn-client@<vpn>_<client>`, and can install a systemd drop-in to prefer VPN DNS.
- *NetworkManager*-path: imports the `.ovpn` via `nmcli`, keeps the connection alive, and optionally installs a dispatcher auto-connect script.
- Copies the exported config bundle from the controller to `<conf_dir>/<vpn_name>_<client>.conf` and applies gateway sysctls when requested.
- Client roles (`gateway`/`roaming`/`local`) and their semantics are defined in the server's README, since the server schema is the single source of truth.

## DNS handling (OpenVPN vs NetworkManager)

This role treats DNS differently depending on how the client is managed:

- OpenVPN systemd clients: when `prefer_vpn_dns: true`, the role locates `update-resolv-conf` and installs a systemd drop-in that appends `--script-security 2 --up ... --down ...` to the unit’s `ExecStart`. This keeps the base unit intact and applies DNS updates at connect/disconnect time.
- NetworkManager clients: when `prefer_vpn_dns: true`, the connection is modified with `ipv4.ignore-auto-dns no` and a negative `ipv4.dns-priority` so VPN DNS takes precedence. When `prefer_vpn_dns: false`, the role leaves DNS settings alone (default behavior).
- Exported client configs: when `prefer_vpn_dns: false`, the role does not add any DNS-specific overrides; OpenVPN uses its default behavior.
