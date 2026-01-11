# ssh_users

- Manage local SSH users and authorized keys.
- Set up an "ops" user to be used by ansible with passwordless sudo.
- SSH hardening (including restart of SSH server and confirmation of connection afterwards)
- Generate per-user SSH keypairs and export public keys to the controller.
- Key generation/export runs before authorized_keys installation across the play.

## Role Variables

- `ssh_users`: list of user dicts to create. Each item supports:
  - `name` (string, required): account name.
  - `home` (string, optional): home directory path; defaults to `/home/<name>`.
  - `extra_groups` (list, optional): extra groups to append (e.g., sudo, docker).
  - `initial_password_hash` (string, optional): pre-hashed password (e.g. `{{ 'changeme' | password_hash('sha512') }}`) to set on first creation. Passwords are never rotated afterwards.
  - `force_password_reset` (bool, optional, default `true` when an initial password is provided): expire the password after the first creation so the user must change it on first login.
  - `authorized_keys` (list, optional): SSH public keys to place in `~/.ssh/authorized_keys`.
  - `authorized_key_files` (list, optional): file paths on the controller containing SSH public keys. Relative paths are resolved from `ssh_users_key_local_dir`.
  - `generate_ssh_key` (bool, optional): generate a keypair for the user and export the public key; defaults to `ssh_users_generate_keys`.
  - `ssh_key_type` (string, optional): key type for generated keys; defaults to `ssh_users_key_type`.
  - `ssh_key_filename` (string, optional): filename for generated keys under `~/.ssh`; defaults to `ssh_users_key_filename`.
  - `ssh_key_comment` (string, optional): comment for generated keys; defaults to `<user>@<inventory_hostname>`.

- `ssh_users_generate_keys` (bool, default `true`): generate SSH keys for each managed user.
- `ssh_users_key_type` (string, default `ed25519`): SSH key type for generated keys.
- `ssh_users_key_filename` (string, default `id_ed25519`): SSH key filename for generated keys.
- `ssh_users_key_local_dir` (string, default `{{ inventory_dir }}/artifacts/ssh_keys`): local controller path for exported public keys. Files are written as `<user>@<inventory_hostname>.pub`.

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
    authorized_key_files:
      - "artifacts/ssh_keys/ops@bastion.pub"
    generate_ssh_key: true
    ssh_key_type: ed25519
    ssh_key_filename: id_ed25519
    ssh_key_comment: "ops@my-inventory-host"

  - name: backup
    # minimal example:
    # state omitted → present
    # create_home omitted → true
    # home omitted → /home/backup
    # shell omitted → /bin/bash
    # authorized_keys → none
    # authorized_key_files → none
    # generate_ssh_key → true (global default)

# define an ops-user that will be used by ansible (passwordless sudo)
# the user must be contained in the list above!
ops_user: ops
```
