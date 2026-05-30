# automatic_updates_debian_ubuntu

Enable conservative automatic security updates on Debian and Ubuntu with the
native `unattended-upgrades` mechanism.

The role installs and configures `unattended-upgrades`, `apt-listchanges`, and
`needrestart` by default. It applies only security origins unless extra origins
are explicitly configured, restarts affected services automatically through
`needrestart`, and reboots immediately when `unattended-upgrades` finds
`/var/run/reboot-required`.

**This is an administrative role and it assumes privileged execution (`become:
true`) works on the target host.**

## Role Variables

- `automatic_updates_debian_ubuntu_enabled` (bool, default: `true`): enable APT periodic unattended update runs. When `false`, the role writes APT periodic intervals as `0` and disables APT timers on systemd hosts.
- `automatic_updates_debian_ubuntu_update_interval_days` (int, default: `1`): interval for `APT::Periodic::Update-Package-Lists`.
- `automatic_updates_debian_ubuntu_upgrade_interval_days` (int, default: `1`): interval for `APT::Periodic::Unattended-Upgrade`.
- `automatic_updates_debian_ubuntu_reboot_enabled` (bool, default: `true`): allow unattended-upgrades to reboot when `/var/run/reboot-required` exists.
- `automatic_updates_debian_ubuntu_reboot_time` (string, default: `"now"`): value passed to `Unattended-Upgrade::Automatic-Reboot-Time`; use `"now"`, `"HH:MM"`, or a shutdown offset such as `"+30"`.
- `automatic_updates_debian_ubuntu_reboot_with_users` (bool, default: `true`): allow automatic reboot even when users are logged in.
- `automatic_updates_debian_ubuntu_needrestart_enabled` (bool, default: `true`): install `needrestart` and configure automatic service restarts.
- `automatic_updates_debian_ubuntu_apt_listchanges_enabled` (bool, default: `true`): install `apt-listchanges`, log package NEWS/changelog entries to `/var/log/apt/listchanges.log`, and manage log rotation.
- `automatic_updates_debian_ubuntu_extra_origins_patterns` (list, default: `[]`): explicit opt-in `Unattended-Upgrade::Origins-Pattern` entries for non-security sources.
- `automatic_updates_debian_ubuntu_package_blacklist` (list, default: `[]`): Python regular expressions for packages to exclude from unattended upgrades.

Defaults live in `roles/automatic_updates_debian_ubuntu/defaults/main.yml`.

## Security Origins

The default origin policy is intentionally narrow:

- Ubuntu: `archive=${distro_codename}-security`, plus Ubuntu ESM security
  origins when available.
- Debian: `label=Debian-Security` for the installed release security origin.

The role does not enable Ubuntu regular updates, Debian stable updates,
backports, proposed pockets, PPAs, or vendor repositories by default.

To opt in to an extra origin, add a precise `Origins-Pattern` entry:

```yaml
automatic_updates_debian_ubuntu_extra_origins_patterns:
  - "origin=Ubuntu,archive=${distro_codename}-updates"
```

Check the effective origin metadata on a host with:

```bash
apt-cache policy
unattended-upgrade -v --dry-run
```

## Logging

`unattended-upgrades` writes its normal logs under
`/var/log/unattended-upgrades/`. `apt-listchanges` is configured with the `log`
frontend so package NEWS/changelog entries are appended to
`/var/log/apt/listchanges.log` without requiring local email delivery.

## Usage

```yaml
---
- name: Enable automatic security updates
  hosts: debian_ubuntu
  become: true
  gather_facts: false

  roles:
    - rolandu.homeops.automatic_updates_debian_ubuntu
```

Schedule reboots for a local maintenance window:

```yaml
automatic_updates_debian_ubuntu_reboot_time: "03:30"
```

Disable automatic service restarts, while keeping unattended security updates:

```yaml
automatic_updates_debian_ubuntu_needrestart_enabled: false
```
