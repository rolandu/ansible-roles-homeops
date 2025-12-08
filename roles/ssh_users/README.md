# ssh_users

Manage local SSH users and authorized keys.

## Role Variables

- `ssh_users`: list of user dicts to create. Each item supports:
  - `name` (string, required): account name.
  - `home` (string, optional): home directory path; defaults to `/home/<name>`.
  - `extra_groups` (list, optional): extra groups to append (e.g., sudo, docker).
  - `authorized_keys` (list, optional): SSH public keys to place in `~/.ssh/authorized_keys`.

Defaults are defined in `roles/ssh_users/defaults/main.yml`.

## Example

```yaml
ssh_users:
  - name: ops
    home: /home/ops
    extra_groups:
      - sudo
      - docker
    authorized_keys:
      - "ssh-ed25519 AAAA... roland@laptop"

  - name: backup
    authorized_keys:
      - "ssh-ed25519 AAAA... backup@nas"
```

## Usage

Include the role and set `ssh_users` as needed:

```yaml
- hosts: all
  roles:
    - role: ssh_users
      vars:
        ssh_users: "{{ ssh_users }}"
```
