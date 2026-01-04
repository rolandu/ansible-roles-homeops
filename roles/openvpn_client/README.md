# openvpn_client

Install and configure an OpenVPN client from exported inline `.ovpn` profiles, handling both `openvpn-client@` and legacy `openvpn@` units. This role depends on the server role’s `openvpn_config` and the exported bundles it produces.

## Variables

- `openvpn_config` (list, required): same structure used by the server role. Each VPN entry’s `clients` list drives which hosts are managed here.
- `openvpn_client_name` (string, default: `inventory_hostname`): client key to match under each server definition.
- `openvpn_client_local_dir_base` (string, default: `{{ inventory_dir }}/artifacts`): where exported `<vpn_name>_<client>.ovpn` files live on the controller.

## Behavior

- Iterates over `openvpn_config`; skips any VPN where this client is not listed or is marked `managed: false` (export-only).
- Copies the exported bundle from the controller to `<conf_dir>/<vpn_name>_<client>.conf`, enables/starts the matching systemd unit, and restarts it after changes.
- Client roles (`gateway`/`roaming`/`local`) and their semantics are defined in the server README, since the server schema is the single source of truth.
