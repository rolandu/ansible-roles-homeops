# ops_user_setup

Create/maintain the primary ops user, install its SSH keys, and harden sshd by disabling password auth and root login.

## Role Variables

- `ops_user` (string, default: `ops`): account to manage.
- `ops_authorized_keys` (list, default: `[]`): SSH public keys to add for the user.
- `ssh_disable_password_auth` (bool, default: true): set `PasswordAuthentication no` in `sshd_config`.
- `ssh_disable_root_login` (bool, default: true): set `PermitRootLogin no`.
- `sshd_config_path` (string, default: `/etc/ssh/sshd_config`): path to the sshd config.

## Example

```yaml
- hosts: all
  roles:
    - role: ops_user_setup
      vars:
        ops_user: ops
        ops_authorized_keys:
          - "ssh-ed25519 AAAA... admin@laptop"
```

The role ensures the user exists, manages its `~/.ssh/authorized_keys`, updates sshd settings, restarts SSH if needed, and forces an Ansible reconnection to verify access.
