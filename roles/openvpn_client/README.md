# openvpn_client

Install and configure an OpenVPN client from an exported `.ovpn` profile, handling both `openvpn-client@` and legacy `openvpn@` systemd units.

The role copies `<name>.ovpn` to `/etc/openvpn[/client]/<name>.conf`, ensures the service is enabled/started, and optionally turns on IPv4 forwarding.
