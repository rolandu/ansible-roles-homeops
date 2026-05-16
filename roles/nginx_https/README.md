# nginx_https

Install nginx and manage HTTPS reverse proxy and static site vhosts with explicit certificate paths.

The role installs nginx, ensures the service is enabled and started, removes the packaged default site by default, optionally joins the nginx user to a certificate group, deploys shared TLS/proxy/security snippets, creates an optional HTTP to HTTPS catch-all redirect, renders configured HTTPS vhosts, applies pending handlers, and verifies local HTTPS reachability.

## Requirements

- Debian or Ubuntu target host.
- Valid certificate files already present on the target host.
- DNS records already pointing at the target host.
- If certificate files are group-readable, `nginx_cert_group` should match that group.

## Role Variables

Defaults are defined in `defaults/main.yml`.

- `nginx_user` (string, default `www-data`): OS user running nginx.
- `nginx_cert_group` (string, default `certificates`): group granted read access to certificate files.
- `nginx_manage_cert_group` (bool, default `true`): create `nginx_cert_group` and append `nginx_user` to it.
- `nginx_remove_default_site` (bool, default `true`): remove `/etc/nginx/sites-enabled/default`.
- `nginx_prune_enabled_sites` (bool, default `true`): disable `.conf` entries in `/etc/nginx/sites-enabled` that are not listed in this role config. Files in `/etc/nginx/sites-available` are left in place.
- `nginx_enable_http_redirect_catchall` (bool, default `true`): manage a default port 80 server that redirects all traffic to HTTPS.
- `nginx_ssl_protocols` (string, default `TLSv1.2 TLSv1.3`): enabled TLS protocols.
- `nginx_ssl_session_timeout`, `nginx_ssl_session_cache`, `nginx_ssl_session_tickets`: shared TLS session settings.
- `nginx_enable_hsts` (bool, default `false`): enable HSTS header in managed vhosts.
- `nginx_hsts_value` (string, default `max-age=31536000`): HSTS header value.
- `nginx_client_max_body_size` (string, default `25m`): default upload limit for reverse proxy sites.
- `nginx_verify_sites` (bool, default `true`): probe managed HTTPS vhosts locally after nginx configuration is applied.
- `nginx_verify_local_host` (string, default `127.0.0.1`): local address used for HTTPS probes.
- `nginx_verify_timeout` (int, default `10`): timeout in seconds for each local HTTPS probe.
- `nginx_verify_status_codes` (list[int], default `[200, 204, 301, 302, 307, 308, 401, 403]`): default acceptable response codes for local HTTPS probes.
- `nginx_reverse_proxy_sites` (list, default `[]`): HTTPS reverse proxy vhosts.
- `nginx_static_sites` (list, default `[]`): HTTPS static file vhosts.

Each `nginx_reverse_proxy_sites` item needs:

- `name`: safe file/log name, using letters, numbers, `_`, `.`, or `-`.
- `server_name`: nginx `server_name`.
- `backend`: upstream URL for `proxy_pass`, for example `http://127.0.0.1:5000`.
- `ssl_certificate` and `ssl_certificate_key`: absolute paths.
- `client_max_body_size` (optional): per-site override.
- `websocket` (bool, optional, default `false`): enable websocket upgrade headers.
- `verify` (bool, optional, default `true`): include this site in local HTTPS verification.
- `verify_path` (string, optional, default `/`): path to request during local HTTPS verification.
- `verify_host` (string, optional, default first name from `server_name`): Host header used during local HTTPS verification.
- `verify_timeout` (int, optional): per-site verification timeout.
- `verify_status_codes` (list[int], optional): per-site acceptable response codes.

Each `nginx_static_sites` item needs:

- `name`: safe file/log name, using letters, numbers, `_`, `.`, or `-`.
- `server_name`: nginx `server_name`.
- `root`: absolute document root.
- `ssl_certificate` and `ssl_certificate_key`: absolute paths.
- `index` (optional, default `index.html`): nginx `index` value.
- `verify` (bool, optional, default `true`): include this site in local HTTPS verification.
- `verify_path` (string, optional, default `/`): path to request during local HTTPS verification.
- `verify_host` (string, optional, default first name from `server_name`): Host header used during local HTTPS verification.
- `verify_timeout` (int, optional): per-site verification timeout.
- `verify_status_codes` (list[int], optional): per-site acceptable response codes.

## Example

```yaml
---
- name: Configure nginx HTTPS sites
  hosts: proxy
  become: true

  roles:
    - role: rolandu.homeops.nginx_https
      vars:
        nginx_reverse_proxy_sites:
          - name: myapp
            server_name: app.example.com
            backend: http://127.0.0.1:5000
            ssl_certificate: /srv/certificates/live/example.com/fullchain.pem
            ssl_certificate_key: /srv/certificates/live/example.com/privkey.pem
            websocket: false
        nginx_static_sites:
          - name: docs
            server_name: docs.example.com
            root: /var/www/docs
            ssl_certificate: /srv/certificates/live/example.com/fullchain.pem
            ssl_certificate_key: /srv/certificates/live/example.com/privkey.pem
```

## Operational Notes

Handlers run `nginx -t` before reloading or restarting nginx. The role flushes handlers before verification, then validates the active configuration, ensures nginx is started, and probes each managed HTTPS vhost at `https://127.0.0.1/` with the configured `server_name` as the Host header. DNS is not used for this check, and certificate validation is disabled because the probe is local.

Site activation follows Debian nginx conventions: rendered vhost files live in `/etc/nginx/sites-available`, and active sites are symlinked from `/etc/nginx/sites-enabled`. With `nginx_prune_enabled_sites: true`, only the HTTP redirect catch-all and vhosts currently listed in role variables remain active.

The role does not create certificates or DNS records. Pair it with `certbot_hetzner` and `certificates_replicate` when certificates are issued on a different host.

This role does not include a Docker scenario test. Useful runtime validation requires real certificate files and DNS/server names.
