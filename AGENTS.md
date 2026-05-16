# AGENTS.md

This repository is a reusable Ansible role collection for home or small office
infrastructure. Treat it as role-first, not as a standalone deployment project:
there are no production inventories, caller playbooks, Molecule scenarios, or
CI jobs in this repo.

## Layout

- Collection metadata and shared docs live at the repo root:
  - `README.md`
  - `galaxy.yml`
- Roles live under `roles/<role_name>/` and generally contain:
  - `defaults/main.yml`
  - `tasks/main.yml` plus small included task files
  - `handlers/main.yml` when needed
  - `templates/*.j2` when needed
  - `meta/main.yml`
  - `README.md`
- Tests and helper scripts live under `tests/`.

Current roles: `adguardhome_docker`, `certbot_hetzner`, `openvpn_client`,
`openvpn_server`, `ssh_user_keys_generate`, `ssh_user_keys_install`,
`ssh_users`, `update_debian_ubuntu`.

## Core Rules

- Keep changes role-local unless behavior is intentionally shared.
- When role inputs or behavior change, update all relevant places in the same
  patch: `defaults/main.yml`, task validation/assertions, and the role README.
- Prefer small task files with `include_tasks` for distinct workflows. Existing
  examples: `ssh_users` and `openvpn_*`.
- Preserve explicit `owner`, `group`, and `mode` on managed files/directories,
  especially security-sensitive assets.
- Quote file modes as strings: `'0755'`, `'0640'`, `'2770'`.
- Add validation near role entrypoints and fail fast on invalid inputs.
- Keep `meta/main.yml` aligned with the repo baseline:
  `min_ansible_version: 2.13`; no dependencies unless actually needed.
- Keep YAML syntax clean and task includes wired correctly.

## Shared Paths

Keep shared path conventions stable unless there is a clear reason to change
them. If they change, update the root `README.md`.

- `artifacts_dir`: controller-side exports/downloads, usually
  `{{ inventory_dir }}/artifacts`
- `app_root_dir`: software/runtime install root, usually `/opt`
- `data_root_dir`: persistent service data root, usually `/srv`
- `docker_app_base_dir`
- `docker_data_base_dir`

Path taxonomy:

- Software/runtime assets: `{{ app_root_dir }}/<app>`
- Persistent service data: `{{ data_root_dir }}/<app>`
- Controller exports/downloads: `{{ artifacts_dir }}/<feature>`

Existing examples:

- SSH key exports: `{{ artifacts_dir }}/ssh_keys`
- OpenVPN client bundles: `{{ artifacts_dir }}/openvpn-clients`
- AdGuard app/data split across Docker app/data base dirs

## Cross-Role Coupling

- `openvpn_server` and `openvpn_client` share the `openvpn_config` structure.
- `openvpn_server` exports client bundles to
  `{{ artifacts_dir }}/openvpn-clients`; `openvpn_client` consumes them.
- If changing OpenVPN client types, DNS behavior, export paths, or config field
  names, review/update both OpenVPN roles and both READMEs.
- In SSH user workflows, key generation/export happens before authorized-key
  installation. Preserve that ordering unless deliberately redesigning it.

## Operational Conventions

- Prefer capability-driven branching over static assumptions:
  detect packages/services first, then choose implementation path.
- For disable/remove behavior, use an explicit teardown boolean instead of
  deleting resources implicitly. Example: `adguard_teardown`.
- When a change can break connectivity, flush handlers before verification
  steps. Existing pattern: `meta: flush_handlers` before SSH/DNS checks.
- Use deterministic names for generated artifacts and connection IDs, e.g.
  `<vpn_name>_<client>` and `<user>@<inventory_hostname>.pub`.

## Scheduling

Use `/etc/cron.d/<role>-<purpose>` for recurring work unless there is a strong
reason to require systemd timers. When adding scheduled work:

- expose the schedule as a role variable
- write an explicit cron file under `/etc/cron.d`
- call a role-managed script/entrypoint, not an inline one-liner
- write output to a dedicated log file with managed permissions
- document dry-run and real-run commands in the role README

## Secrets

This repo handles SSH keys, authorized keys, Hetzner tokens, OpenVPN secrets,
password hashes, and privileged local access.

- Do not debug-print secrets.
- Use `no_log: true` where secret material may appear in args or failure output.
- Keep secret file permissions restrictive.
- Do not move secrets into world-readable paths.

## Documentation

- Each role README is the source of truth for variables, defaults, examples, and
  operational notes.
- Keep examples minimal but valid.
- Update the root `README.md` when adding/removing roles or changing
  collection-wide conventions.
- Keep detailed scenario-test mechanics in `tests/scenarios/README.md`; keep
  `AGENTS.md` focused on rules and workflow.

## Validation

Available helpers:

- `tests/lint-roles.sh`: run `ansible-lint` role by role.
- `tests/lint-roles.sh --report`: refresh `tests/lint-report.txt`.
- `tests/lint-roles.sh --report-file <path>`: write a custom report path.
- `tests/scenarios/<role>/run.sh`: run Docker-backed scenario tests where they
  exist.

Lint reports are generated working backlogs. Treat current `ansible-lint` output
as source of truth and regenerate reports after fixes.

Docker scenarios require Docker access for the current user. If Docker or group
membership just changed, the user may need to log out and back in before
`/var/run/docker.sock` is accessible.

There are no committed production inventories, caller playbooks, Molecule
scenarios, or CI jobs. Do not claim Molecule, runtime integration, or CI
coverage unless that tooling is actually added.

If local caller playbooks or inventories exist outside this repo,
`ansible-playbook --syntax-check` or a targeted dry run may be useful. If
meaningful validation cannot be run, say so plainly.

## Agent Workflow

When modifying this repo:

1. Read the target role `README.md`, `defaults/main.yml`, and `tasks/main.yml`.
2. Search for changed variable names, paths, and schemas across other roles.
3. Make the smallest change that preserves existing conventions.
4. Update docs in the same patch.
5. Run relevant validation:
   - role lint via `tests/lint-roles.sh` when available
   - scenario tests for roles with `tests/scenarios/<role>/run.sh`
   - syntax checks if a usable caller playbook/inventory exists
6. Summarize what changed and any validation that could not be run.
