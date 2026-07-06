# ssh_root_client

Create one persistent SSH client identity for root, manage root's outbound SSH
configuration for one or more explicitly declared servers, install verified
server host keys, and export only the generated public key to controller
artifacts.

The role requires privileged execution (`become: true`). It never exports the
private key and never modifies a remote server.

## Requirements and behavior

- The managed host must provide `ssh` and `ssh-keygen` (normally from its
  OpenSSH client package).
- The play must use privilege escalation because all managed target paths
  belong to root.
- The controller user must be able to create the configured artifact
  directory.
- `/root/.ssh` is managed as `root:root` with mode `'0700'`.
- A key is generated without a passphrase only when its private key does not
  exist. Existing private keys are never replaced or rotated.
- The default filename is dedicated to this role, so an existing conventional
  `/root/.ssh/id_ed25519` identity is neither reused nor modified.
- A missing public key is recovered from the existing private key.
- The private and public key modes are `'0600'` and `'0644'`.
- Root's SSH config is rendered from `ssh_root_client_hosts` and supports
  multiple SSH servers.
- Every server entry includes an SSH alias, real hostname or address, remote
  username, optional custom port, and one or more verified host keys.
- Every managed server uses the generated identity with `IdentitiesOnly`,
  non-interactive batch mode, and strict host-key checking.
- Every managed server uses Borg's documented SSH keepalive example by
  default: `ServerAliveInterval 10` and `ServerAliveCountMax 30`. This detects
  an unresponsive connection after approximately five minutes; it does not
  limit the total connection or backup duration. Both values are overridable.
  See [Borg's SSH keepalive guidance](https://borgbackup.readthedocs.io/en/stable/usage/serve.html#ssh-keepalive).
- The role owns the complete files configured by
  `ssh_root_client_config_path` and `ssh_root_client_known_hosts_path` whenever
  at least one server is declared.
- The public key is exported to
  `{{ artifacts_dir }}/ssh_keys/root@<inventory_hostname>.pub` by default.
- Remote account creation, public-key authorization, repository creation, and
  remote access restrictions remain manual.

Actual OpenSSH public host-key material is required. A SHA-256 fingerprint can
verify a key but cannot populate `known_hosts`. Do not populate `host_keys`
from an unverified automated `ssh-keyscan` result.

## Variables

| Variable | Default behavior |
|---|---|
| `artifacts_dir` | Controller export base, normally `inventory/artifacts` |
| `ssh_root_client_key_type` | `ed25519` key passed to `ssh-keygen` |
| `ssh_root_client_key_filename` | Dedicated key filename below root's SSH directory |
| `ssh_root_client_key_comment` | `root@<inventory hostname>` |
| `ssh_root_client_ssh_dir` | `/root/.ssh` |
| `ssh_root_client_config_path` | Root SSH `config` below the managed SSH directory |
| `ssh_root_client_known_hosts_path` | Root `known_hosts` below the managed SSH directory |
| `ssh_root_client_artifact_dir` | `ssh_keys` below `artifacts_dir` |
| `ssh_root_client_artifact_filename` | `root@<inventory hostname>.pub` |
| `ssh_root_client_hosts` | Empty list of managed server mappings |
| `ssh_root_client_server_alive_interval` | Keepalive interval; defaults to Borg's documented 10-second example |
| `ssh_root_client_server_alive_count_max` | Unanswered keepalive limit; defaults to Borg's documented count of 30 |

Each `ssh_root_client_hosts` item accepts:

- `name`: safe SSH alias used by callers.
- `hostname`: real server DNS name or address.
- `user`: remote username.
- `port`: optional SSH port, default `22`.
- `host_keys`: verified values in `<algorithm> <base64-key>` format. A key
  comment may follow the key material.

## Example

```yaml
ssh_root_client_hosts:
  - name: borg-primary
    hostname: storage.example.net
    user: backup-account
    port: 2222
    host_keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
  - name: file-server
    hostname: files.example.net
    user: root-storage
    host_keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
```

After applying the role, manually install the exported public key on each
remote server with the appropriate server-side restrictions. Then test the
declared alias from the managed host before configuring software that depends
on it.
