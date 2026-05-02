# AGENTS.md

This repository contains reusable Ansible roles for home or small office infrastructure. Treat it as a role collection first, not as a standalone deployable project: there are no inventory files, playbooks, Molecule scenarios, or CI jobs in this repo. The repo does include a lightweight lint helper under `tests/`.

## Scope and Layout

- Root files:
  - `README.md`: collection-level overview and shared path conventions.
  - `galaxy.yml`: collection metadata.
- Roles live under `roles/<role_name>/` and generally follow the same layout:
  - `defaults/main.yml`
  - `tasks/main.yml` plus small included task files when the role has multiple workflows
  - `handlers/main.yml` when needed
  - `templates/*.j2` when rendering managed files
  - `meta/main.yml`
  - `README.md`

Current roles:

- `adguardhome_docker`
- `certbot_hetzner`
- `openvpn_client`
- `openvpn_server`
- `ssh_user_keys_generate`
- `ssh_user_keys_install`
- `ssh_users`
- `update_debian_ubuntu`

## Repo Conventions

- Keep changes role-local unless the behavior is intentionally shared.
- When a role’s inputs or behavior change, update all of:
  - `defaults/main.yml`
  - task assertions / validation
  - the role `README.md`
- Prefer small task files with `include_tasks` for distinct workflows. This repo already uses that pattern heavily in `ssh_users` and `openvpn_*`.
- Preserve explicit ownership, group, and mode settings on remote files and directories. These roles manage security-sensitive assets.
- Quote file modes as strings in YAML, e.g. `'0755'`, `'0640'`, `'2770'`.
- Add validation near the role entrypoint. This repo consistently fails fast on invalid inputs.
- Keep `meta/main.yml` in sync with repo baseline: `min_ansible_version: 2.13` and no role dependencies unless there is a real need.

## Shared Variables and Paths

Several roles rely on shared path conventions from the root `README.md`:

- `artifacts_dir`: controller-side download/export area, typically `{{ inventory_dir }}/artifacts`
- `app_root_dir`: default app install root, usually `/opt`
- `data_root_dir`: default persistent data root, usually `/srv`
- `docker_app_base_dir`
- `docker_data_base_dir`

## Convention

Keep these conventions stable unless there is a clear reason to change them, and update the root `README.md` if they move.

Path taxonomy used across the repo:

- Software/runtime assets (scripts, compose files, managed binaries): `{{ app_root_dir }}/<app>`
- Persistent service data: `{{ data_root_dir }}/<app>`
- Controller-side exports/downloads: `{{ artifacts_dir }}/<feature>`

Examples already used:

- `ssh_users` exports keys under `{{ artifacts_dir }}/ssh_keys`
- OpenVPN exports client bundles under `{{ artifacts_dir }}/openvpn-clients`
- AdGuard stack/config/data split across `docker_app_base_dir` and `docker_data_base_dir`

## Cross-Role Coupling

Some roles are intentionally coupled. Be careful when changing shared schemas.

- `openvpn_server` and `openvpn_client` share the `openvpn_config` structure.
- `openvpn_server` exports client bundles to `{{ artifacts_dir }}/openvpn-clients`, and `openvpn_client` consumes them from the controller.
- If you change client types, DNS behavior, export paths, or config field names in one OpenVPN role, review and update the other role and both READMEs in the same change.
- In `ssh_users`, key generation/export happens before authorized key installation across the play. Preserve that ordering unless you are deliberately redesigning the flow.

## Operational Conventions

- Prefer capability-driven branching over static assumptions:
  - detect installed packages/services first
  - then choose implementation path (for example, NetworkManager vs `openvpn-client`, `systemd-resolved` vs `resolvconf`)
- Where a role offers disable/remove behavior, model it as an explicit boolean teardown switch instead of deleting role resources implicitly.
  - current pattern: `adguard_teardown` stops services and restores resolver settings without removing persistent data
- For changes that can break current connectivity, apply handlers immediately before verification steps.
  - current patterns: `meta: flush_handlers` before SSH reconnect check and before live DNS verification
- Use deterministic naming for generated artifacts and connection IDs so server/client roles can interoperate without extra mapping layers.
  - examples: `<vpn_name>_<client>`, `<user>@<inventory_hostname>.pub`

## Scheduling Convention

Only one role currently schedules recurring work (`certbot_hetzner`), and it uses `/etc/cron.d`.

To keep behavior consistent across roles, standardize on cron jobs in `/etc/cron.d/<role>-<purpose>` for periodic tasks unless there is a strong reason to require `systemd` timers.

When adding scheduled work:

- expose schedule as a role variable (cron expression)
- write an explicit cron file under `/etc/cron.d`
- call a role-managed script/entrypoint, not an inline one-liner
- send output to a dedicated log file with managed permissions
- document manual dry-run and real-run commands in the role README

## Secrets and Sensitive Data

This repo handles secrets and privileged access:

- SSH authorized keys and generated key material
- Hetzner API tokens
- OpenVPN CA passphrases and management passwords
- Password hashes for local users and AdGuard

When touching tasks involving secret values:

- avoid `debug` output of secrets
- use `no_log: true` where secret material may appear in task args or failure output
- keep file permissions restrictive
- do not move secret values into world-readable paths

## Documentation Expectations

- Each role README is the source of truth for variables, defaults, and usage examples.
- Keep examples minimal but valid.
- If a role gains a new required variable, default behavior, or operational note, document it in that role README.
- Update the root `README.md` when adding/removing roles or changing collection-wide conventions.

## Validation and Testing

There is a lightweight project-wide lint helper:

- `tests/lint-roles.sh`: discovers each direct role under `roles/` and runs `ansible-lint` role by role.
- `tests/lint-roles.sh --report`: writes the same output to `tests/lint-report.txt` while streaming it to the terminal.
- `tests/lint-roles.sh --report-file <path>`: writes the report to a custom path. Relative paths resolve from the repo root.

The lint report is a generated working backlog for cleanup. Treat the current
`ansible-lint` output as the source of truth and regenerate the report after
fixing findings.

The script prints the role currently being checked before each lint run. It
continues through all roles and exits non-zero if any role has lint failures.

There are still no committed inventories, caller playbooks, Molecule scenarios,
or CI jobs in this repository. Do not claim Molecule, runtime integration test,
or CI coverage unless you add that tooling explicitly.

When making changes:

- inspect the impacted role’s `defaults`, `tasks`, `templates`, `handlers`, and `README.md`
- run `tests/lint-roles.sh` for broad lint feedback when `ansible-lint` is available
- run `tests/lint-roles.sh --report` when you want to refresh the agent-friendly lint backlog
- keep YAML syntax clean and task includes wired correctly
- if you have a local caller playbook or inventory outside this repo, `ansible-playbook --syntax-check` or a targeted dry run is useful, but that validation usually depends on external files not present here
- if you cannot run meaningful validation, state that plainly

## Change Strategy for Agents

When asked to modify this repo:

1. Read the target role’s `README.md`, `defaults/main.yml`, and `tasks/main.yml` first.
2. Search for the variable names or paths across other roles before changing shared behavior.
3. Make the smallest change that preserves existing conventions.
4. Update documentation in the same patch, not as a follow-up.
5. Summarize any validation you could not perform because the repo does not include runnable playbooks or test harnesses.
