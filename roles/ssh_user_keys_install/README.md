# ssh_user_keys_install

Install `~/.ssh/authorized_keys` for the current SSH connection user.

- Installs keys from inline values and/or controller-side files.
- Relative file paths resolve from `ssh_user_keys_install_local_dir`.
- Does not require sudo; tasks are executed with `become: false`.

**This role operates at user scope and intentionally runs without privileged access (`become: false`), so it only manages SSH material for the currently connected user.**

## Role Variables

- `ssh_user_keys_install_authorized_keys` (list, default `[]`): inline public keys to write to `authorized_keys`.
- `ssh_user_keys_install_authorized_key_files` (list, default `[]`): controller-side files containing public keys.
- `artifacts_dir` (string, default `{{ inventory_dir }}/artifacts`): shared controller artifact base path.
- `ssh_user_keys_install_local_dir` (string, default `{{ artifacts_dir }}/ssh_keys`): base path for relative entries in `ssh_user_keys_install_authorized_key_files`.

Defaults are defined in `roles/ssh_user_keys_install/defaults/main.yml`.

## Usage

```yaml
---
- name: Install authorized_keys for current SSH users
  hosts: all
  gather_facts: false
  become: false

  roles:
    - rolandu.homeops.ssh_user_keys_install
```
