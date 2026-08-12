# openvpn_client

Install and configure an OpenVPN client from exported inline `.ovpn` profiles. This role depends on the server role’s `openvpn_config` and the exported bundles it produces. See the server role for shared schema and server-side behavior: [openvpn_server](../openvpn_server/README.md).

**This is an administrative role and it assumes privileged execution (`become: true`) works on the target host.**

## Variables

- `openvpn_config` (list, required): same structure used by the server role. Each VPN entry’s `clients` list drives which hosts are managed here, including `prefer_vpn_dns` (bool, default `true`) to control whether pushed DNS is preferred.
- `openvpn_client_name` (string, default: `{{ inventory_hostname }}`): client key to match under each server definition.
- `artifacts_dir` (string, default: `{{ inventory_dir }}/artifacts`): base path on the controller for downloaded artifacts.
- `openvpn_client_local_dir_base` (string, default: `{{ artifacts_dir }}/openvpn-clients`): where exported `<vpn_name>_<client>.ovpn` files live on the controller; final paths are `<base>/<vpn_name>/<vpn_name>_<client>.ovpn`.
- `openvpn_client_nm_autoconnect_dispatcher` (bool, default: `true`): install a NetworkManager dispatcher script to bring up the VPN when internet connectivity is detected.
- Each managed client entry also supports:
  - `watchdog_enabled` (bool, default: `false`): install a NetworkManager connection watchdog for this client.
  - `watchdog_interval` (string, default: `*/5 * * * *`): five-field cron schedule for the watchdog.
  - `watchdog_dig_target` (string, optional): hostname that must resolve; defaults to the VPN entry's effective `openvpn_remote_host`.
  - `watchdog_ping_target` (string, optional): address that must respond to ping; defaults to the first `openvpn_dns_servers` value.
- DNS values are taken from each VPN entry in `openvpn_config` (`openvpn_dns_servers`, `openvpn_dns_domain`). The client role does not define its own DNS defaults; if the server entry omits DNS, the client leaves DNS untouched.

## Behavior

- Iterates over `openvpn_config`; skips any VPN where this client is not listed or is marked `managed: false` (export-only).
- Supports both OpenVPN systemd clients and NetworkManager-managed VPNs; the role auto-selects only when NetworkManager is installed *and running*.
- `openvpn-client`-path: drops the exported `.ovpn` as a systemd instance config, manages `openvpn-client@<vpn>_<client>`, and always installs a systemd drop-in to pass OpenVPN’s pushed DNS data to the active resolver:
  - If `systemd-resolved` is running, the role installs `openvpn-systemd-resolved` and wires `update-systemd-resolved` via `--up/--down --down-pre`.
- Otherwise it falls back to `update-resolv-conf`. A custom script path provided via `dns_helper_script_override` is used directly (skipping discovery) and works for either resolver helper.
- *NetworkManager*-path: imports the `.ovpn` via `nmcli`, keeps the connection alive, and optionally installs a dispatcher auto-connect script.
- An optional per-client NetworkManager watchdog checks both DNS resolution and VPN-internal reachability. If either check fails, it cycles the exact `nmcli` connection.
- Copies the exported config bundle from the controller to `<conf_dir>/<vpn_name>_<client>.conf` and applies gateway sysctls when requested.
- Client roles (`gateway`/`roaming`/`local`) and their semantics are defined in the server's README, since the server schema is the single source of truth.

## DNS handling (OpenVPN vs NetworkManager)

This role treats DNS differently depending on how the client is managed:

- If the server definition omits `openvpn_dns_servers`, no DNS changes are applied on the client side (both OpenVPN and NetworkManager paths).
- OpenVPN systemd clients: DNS pushed by the server is always applied. The role auto-detects `systemd-resolved` (uses `update-systemd-resolved` with `--down-pre`) and otherwise uses `update-resolv-conf`.
- Custom script path override: `dns_helper_script_override` (from the server config) is used directly; when unset, standard helper locations are probed per resolver.
- NetworkManager clients: `prefer_vpn_dns` still controls priority; when `true` the connection is modified with `ipv4.ignore-auto-dns no` and a negative `ipv4.dns-priority`. When `false`, the role leaves DNS settings alone (default behavior).
- NetworkManager + systemd-resolved split-tunnel fix: when VPN DNS servers are defined, the role also sets `ipv4.dns-search`/`ipv6.dns-search` to the routing domains from `openvpn_dns_domain` (default `~.`) so `systemd-resolved` scopes DNS to the VPN link even without a default route. Multiple scopes are supported (e.g., `["~corp.example", "~internal.lan"]`).
- Exported client configs: no DNS-specific edits are added; the helper scripts simply honor what the server pushes at connect/disconnect time.

## NetworkManager watchdog

The watchdog is disabled by default. For a normally configured client, enable it with only:

```yaml
clients:
  - name: gateway1
    type: gateway
    watchdog_enabled: true
```

Every five minutes by default, the watchdog resolves the effective OpenVPN endpoint with `dig` and pings the first configured VPN DNS server. Both checks must pass. Failure of either check runs `nmcli connection down` followed by `nmcli connection up` for the role-derived `<vpn_name>_<client>` connection. Every completed run writes a timestamped success, failure, or repair result to the dedicated log.

Override the derived targets or schedule only when needed:

```yaml
clients:
  - name: gateway1
    type: gateway
    watchdog_enabled: true
    watchdog_interval: "*/10 * * * *"
    watchdog_dig_target: vpn.example.com
    watchdog_ping_target: 10.200.0.1
```

For connection `<vpn_name>_<client>`, the role manages:

- `/usr/local/sbin/<vpn_name>_<client>_watchdog.sh`
- `/etc/cron.d/openvpn-client-<vpn_name>_<client>_watchdog`
- `/var/log/openvpn-client-<vpn_name>_<client>_watchdog.log`
- `/etc/logrotate.d/openvpn-client-<vpn_name>_<client>_watchdog`

The script is managed as `root:root` with mode `0700`; only root can read or execute its network-repair logic. It uses a per-connection lock under `/run`, so scheduled and manual runs cannot overlap. All watchdog-owned output passes through the timestamped logger, while raw `dig`, `ping`, and `nmcli` output is suppressed; detailed connection diagnostics remain available in the NetworkManager journal. Disabling the watchdog removes its script, cron file, and logrotate policy without changing the VPN connection.

To inspect and exercise a configured watchdog:

```bash
sudo /usr/local/sbin/<vpn_name>_<client>_watchdog.sh
sudo tail -n 100 /var/log/openvpn-client-<vpn_name>_<client>_watchdog.log
cat /etc/cron.d/openvpn-client-<vpn_name>_<client>_watchdog
dig <effective-dig-target> A +short
ping -c 1 <effective-ping-target>
sudo nmcli connection down "<vpn_name>_<client>"
sudo nmcli connection up "<vpn_name>_<client>"
```

A healthy manual run prints one timestamped success line. Cron appends the same line to the dedicated log, providing positive evidence of each completed scheduled check.
