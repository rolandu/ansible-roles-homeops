# ssh_user_keys_generate

Generate an SSH keypair for the current SSH connection user and export the public key to the controller.

- Generates `~/.ssh/<filename>` and `~/.ssh/<filename>.pub`.
- Exports the public key to `{{ ssh_user_keys_generate_local_dir }}/<current_user>@<inventory_hostname>.pub`.
- Does not require sudo; tasks are executed with `become: false`.

**This role operates at user scope and intentionally runs without privileged access (`become: false`), so it only manages SSH material for the currently connected user.**

## Role Variables

- `ssh_user_keys_generate_key_type` (string, default `ed25519`): key type passed to `ssh-keygen`.
- `ssh_user_keys_generate_key_filename` (string, default `id_ed25519`): filename under `~/.ssh`.
- `ssh_user_keys_generate_key_comment` (string, default `<current_user>@<inventory_hostname>`): key comment for generated keypairs.
- `ssh_user_install_basic_ssh_config` (bool, default `true`): create `~/.ssh/config` when no config file exists. The generated config sets `Host *` to use `~/.ssh/<ssh_user_keys_generate_key_filename>` by default and never overwrites an existing file.
- `artifacts_dir` (string, default `{{ inventory_dir }}/artifacts`): shared controller artifact base path.
- `ssh_user_keys_generate_local_dir` (string, default `{{ artifacts_dir }}/ssh_keys`): controller-side export path for public keys.

Defaults are defined in `roles/ssh_user_keys_generate/defaults/main.yml`.

## Usage

```yaml
---
- name: Generate and export SSH keys
  hosts: all
  gather_facts: false
  become: false

  roles:
    - rolandu.homeops.ssh_user_keys_generate
```
