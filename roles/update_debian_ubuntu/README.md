# update_debian_ubuntu

Update Debian/Ubuntu hosts by refreshing apt metadata, applying full upgrades, cleaning leftover packages, and rebooting if the kernel requests it.

## Role Variables

- `update_debian_ubuntu_cache_valid_time` (default: `3600`): Seconds apt metadata is considered fresh when refreshing the cache.
- `update_debian_ubuntu_upgrade_type` (default: `dist`): Upgrade strategy passed to the apt module (e.g., `dist`, `full`, `safe`).
- `update_debian_ubuntu_reboot_timeout` (default: `900`): Seconds to wait for the node to return after triggering a reboot.
- `perform_reboot_if_needed` (default: `true`): Controls whether the host should reboot automatically when `/var/run/reboot-required` exists.

Defaults live in `roles/update_debian_ubuntu/defaults/main.yml`.

## Usage

Include the role directly in a playbook wherever routine updates are required; e.g.

```yaml
---
- name: Update & upgrade Debian-based hosts
  hosts: ubuntu:debian
  become: true
  gather_facts: false

  roles:
    - rolandu.homeops.ssh_users
```
