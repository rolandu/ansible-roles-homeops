# ssh_users

Manage local SSH users and authorized keys.

## Role Variables

- `ssh_users`: list of user dicts to create. Each item supports:
  - `name` (string, required): account name.
  - `home` (string, optional): home directory path; defaults to `/home/<name>`.
  - `extra_groups` (list, optional): extra groups to append (e.g., sudo, docker).
  - `initial_password_hash` (string, optional): pre-hashed password (e.g. `{{ 'changeme' | password_hash('sha512') }}`) to set on first creation. Passwords are never rotated afterwards.
  - `force_password_reset` (bool, optional, default `true` when an initial password is provided): expire the password after the first creation so the user must change it on first login.
  - `authorized_keys` (list, optional): SSH public keys to place in `~/.ssh/authorized_keys`.

Defaults are defined in `roles/ssh_users/defaults/main.yml`.

## Usage

Include the role and set `ssh_users` as needed.

## Example config

```yaml
ssh_users:
  - name: ops
    # full example:
    state: present            # optional, defaults to present
    create_home: true         # optional, defaults to true
    home: /home/ops           # optional
    shell: /bin/bash          # optional, defaults to /bin/bash
    extra_groups:             # optional extra groups, added to any that are already set
      - sudo
      - docker
    initial_password_hash: "{{ 'TempPassword123!' | password_hash('sha512') }}"
    force_password_reset: true  # optional; default true when initial_password_hash is set
    authorized_keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... roland@laptop"

  - name: backup
    # minimal example:
    # state omitted → present
    # create_home omitted → true
    # home omitted → /home/backup
    # shell omitted → /bin/bash
    # authorized_keys → none
```

