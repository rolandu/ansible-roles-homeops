# docker_compose_project

Manage one caller-defined Docker Compose project without replacing Compose's
native configuration format.

The role creates explicitly declared directories, renders one Compose template
and additional configuration templates, copies static files, converges the
project with `community.docker.docker_compose_v2`, and can optionally install a
locked daily image-refresh job.

**This is an administrative role and assumes privileged execution
(`become: true`) works on the target host.**

## Boundaries

The caller owns:

- Compose and application configuration content;
- image names, tags, digests, and registry authentication;
- secrets and their Ansible Vault storage;
- application-specific health checks, backups, migrations, and rollback; and
- Docker Engine and Compose plugin installation.

The role does not define a second container schema, build images, prune images,
remove volumes, delete data directories, or interpret image tags as semantic
version ranges.

## Requirements

- Ansible 2.13 or newer.
- `community.docker` in the version range declared by the collection.
- Docker Engine and the Docker Compose v2 plugin on the target.
- Debian or Ubuntu when automatic-update package installation is enabled.
- Root registry authentication already configured when images require it.

The default Docker CLI path is `/usr/bin/docker`. Override
`docker_compose_project_docker_cli` when Docker is installed elsewhere.

## Role variables

### Project

- `docker_compose_project_name` (string, required): lowercase Compose project
  identifier matching `^[a-z0-9][a-z0-9_-]*$`.
- `app_root_dir` (string, default `/opt`): shared software root.
- `docker_compose_project_dir` (absolute path, default
  `{{ app_root_dir }}/{{ docker_compose_project_name }}`): Compose project
  directory.
- `docker_compose_project_dir_owner` / `_group` (default `root`): project
  directory ownership.
- `docker_compose_project_dir_mode` (default `'0750'`): project directory mode.
- `docker_compose_project_docker_cli` (absolute path, default
  `/usr/bin/docker`): Docker CLI used by Ansible convergence and validation.
- `docker_compose_project_teardown` (bool, default `false`): stop the project
  and remove scheduled execution resources without deleting application state.

### Compose definition

`docker_compose_project_compose` is a mapping:

```yaml
docker_compose_project_compose:
  src: "{{ playbook_dir }}/templates/example/compose.yml.j2"
  filename: compose.yml
  owner: root
  group: root
  mode: '0640'
  sensitive: false
```

- `src` is required during normal convergence and may be an absolute
  caller-owned template path.
- `filename` defaults to `compose.yml`, must be a simple YAML filename, and is
  installed directly below the project directory.
- `owner`, `group`, and `mode` default to `root`, `root`, and `'0640'`.
- `sensitive` defaults to `false`; when true, rendering and installation use
  `no_log: true` and `diff: false`.

### Additional directories

Every `docker_compose_project_directories` entry requires all four fields:

```yaml
docker_compose_project_directories:
  - path: /srv/example
    owner: root
    group: root
    mode: '0750'
```

Paths must be absolute. The role creates the project directory separately, so
do not repeat it in this list.

### Templates and static files

`docker_compose_project_templates` renders caller-owned Jinja templates.
`docker_compose_project_files` copies caller-owned static files. Each item
requires `src`, absolute `dest`, `owner`, `group`, and quoted `mode`, and may
set `sensitive: true`:

```yaml
docker_compose_project_templates:
  - src: "{{ inventory_dir }}/config_files/example/config.yaml.j2"
    dest: /srv/example/config.yaml
    owner: root
    group: root
    mode: '0640'
    sensitive: true

docker_compose_project_files:
  - src: "{{ inventory_dir }}/config_files/example/banner.txt"
    dest: /srv/example/banner.txt
    owner: root
    group: root
    mode: '0644'
```

The role intentionally accepts template sources outside itself. This keeps
environment-specific configuration in the caller repository.

### Deployment behavior

`docker_compose_project_deploy` supports:

```yaml
docker_compose_project_deploy:
  pull: always
  wait: true
  wait_timeout: 60
  remove_orphans: false
  down_on_compose_change: true
  recreate_on_managed_change: true
```

- `pull`: `always`, `missing`, `never`, or `policy`; default `always`.
- `wait`: wait for services to be running/healthy; default `true`.
- `wait_timeout`: Compose health wait timeout; default `60` seconds.
- `remove_orphans`: remove services not present in the current definition
  during `up`; default `false`.
- `down_on_compose_change`: when an installed Compose definition changes,
  validate the new candidate, run Compose down through the old file, then
  install the new file; default `true`.
- `recreate_on_managed_change`: force recreation when a managed Compose,
  template, or static file changed; default `true`.

The old-definition down step removes old containers and project networks when
service names or components change. It never passes volume or image removal
options. A first installation and an unchanged Compose definition do not run
down.

The new Compose definition is rendered to a root-only temporary candidate and
validated before the old project is disrupted. Failed candidate validation or
failed Compose down leaves the installed Compose file unchanged. Temporary
candidate state is removed on success and failure.

A changed bind-mounted configuration file is not necessarily visible as a
Compose model change. With `recreate_on_managed_change: true`, the role forces
recreation so the application loads the new configuration. Set it to `false`
only when the application reliably hot-reloads managed files.

Application-specific probes remain caller tasks. Compose reporting
running/healthy does not prove that an HTTP, DNS, or other application
interface works correctly.

### Automatic image refresh

Scheduling defaults to disabled:

```yaml
docker_compose_project_updates:
  enabled: false
  install_packages: true
  packages:
    - cron
    - logrotate
    - util-linux
  docker_cli: /usr/bin/docker
  cron:
    minute: '17'
    hour: '4'
    day: '*'
    month: '*'
    weekday: '*'
```

When enabled, the role manages:

- `/usr/local/sbin/docker-compose-project-<name>-update`, mode `'0750'`;
- `/etc/cron.d/docker-compose-project-<name>-update`, mode `'0644'`;
- `/var/log/docker-compose-project-<name>-update.log`, mode `'0640'`;
- `/etc/logrotate.d/docker-compose-project-<name>-update`, mode `'0644'`; and
- runtime lock `/run/docker-compose-project-<name>-update.lock`.

The update script acquires a non-blocking project-specific lock, validates the
installed Compose definition, pulls its configured images, and only after a
successful pull runs `compose up --detach --no-build --pull never`, adding the
configured wait options when `docker_compose_project_deploy.wait` is true.
It does not rewrite configuration, force-recreate unchanged services, remove
orphans, prune images, remove volumes, or implement rollback.

Disabling updates removes the script, cron file, and logrotate policy. It keeps
the existing update log and leaves the application running.

Docker tags are mutable references, not semantic-version constraints. A tag
such as `latest` or `stable` may cross major versions. Use a publisher-documented
major/minor channel only when its behavior is acceptable, or pin a digest and
update it through a repository workflow such as Renovate.

Validation-only command:

```bash
sudo /usr/bin/docker compose \
  --project-name example \
  --project-directory /opt/example \
  --file /opt/example/compose.yml \
  config --quiet
```

Manual real update:

```bash
sudo /usr/local/sbin/docker-compose-project-example-update
```

Inspect the update history:

```bash
sudo tail -n 100 /var/log/docker-compose-project-example-update.log
```

Enable scheduling only after a controlled convergence, application-specific
health verification, backup verification where applicable, and documentation
of the selected image channel and manual recovery procedure.

## Complete example

```yaml
---
- name: Deploy example Compose application
  hosts: example_hosts
  become: true

  tasks:
    - name: Deploy example project
      ansible.builtin.include_role:
        name: rolandu.homeops.docker_compose_project
      vars:
        docker_compose_project_name: example
        docker_compose_project_compose:
          src: "{{ playbook_dir }}/templates/example/compose.yml.j2"
          filename: compose.yml
          owner: root
          group: root
          mode: '0640'
          sensitive: false
        docker_compose_project_directories:
          - path: /srv/example
            owner: '1000'
            group: '1000'
            mode: '0750'
        docker_compose_project_templates:
          - src: "{{ inventory_dir }}/config_files/example/config.yaml.j2"
            dest: /srv/example/config.yaml
            owner: '1000'
            group: '1000'
            mode: '0640'
            sensitive: true
        docker_compose_project_updates:
          enabled: false
```

## Teardown

Set `docker_compose_project_teardown: true` with the same project name,
directory, Compose filename, and Docker CLI path. The role removes update
execution resources and uses `state: stopped`, equivalent to `docker compose
stop`.

Teardown preserves containers, volumes, images, Compose/configuration files,
declared directories, application data, and logs. It fails rather than guessing
container names when the installed Compose definition is missing.
