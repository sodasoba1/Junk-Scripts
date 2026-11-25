# Pi-hole / Unbound Dashboard

A local Flask dashboard that combines Unbound resolver statistics, Pi-hole API totals and Raspberry Pi/Linux host metrics. It also has optional support for a 128×64 SH1106 I²C OLED display.

## Main components

| File | Name | Purpose and functionality |
|---|---|---|
| `unbound_dashboard.py` | Unbound and Pi-hole Metrics Server | Runs a Flask web application on port 5000. A background thread polls Unbound `stats_noreset`, Pi-hole's `/api/stats/summary` endpoint and host metrics every 10 seconds. It calculates query rate and cache-hit history, then exposes dashboard data at `/api/data`. If the Luma OLED libraries are installed, a second worker renders resolver, CPU, temperature, memory, Pi-hole and uptime information on an SH1106 display at I²C address 0x3C. |
| `templates/dashboard.html` | Web Dashboard Interface | Displays Unbound cache hits/misses/ratio and query rate, Pi-hole blocked queries/clients/totals, plus system CPU, memory, temperature, disk and uptime metrics. JavaScript retrieves `/api/data` every five seconds and renders small history charts. |
| `etc/nginx/sites-available/dns-gateway` | Nginx Dashboard / Pi-hole Gateway | Routes the dashboard root and `/api/data` to Flask on 127.0.0.1:5000, and routes Pi-hole admin/API paths to the Pi-hole web server on 127.0.0.1:8080. |
| `etc/systemd/system/unbound_dashboard.service` | Dashboard systemd Unit | Example unit to start the Flask dashboard at boot and restart it if it exits. Replace the USER/GROUP and home-directory placeholders with the actual installation details. |
| `etc/unbound/unbound.conf.d/pi-hole.conf` | Unbound Resolver Configuration | Example Unbound server configuration for a local resolver on 127.0.0.1:5335, with statistics enabled, cache/prefetch settings, DNSSEC hardening and localhost remote control. |
| `etc/pihole/pihole.toml` | Pi-hole Configuration Fragment | Small Pi-hole configuration fragment included in this deployment layout. Review it against the installed Pi-hole version before applying. |

## Configuration before use

In `unbound_dashboard.py`:

1. Set `PIHOLE_API_URL` to the local Pi-hole API base URL.
2. Set `PIHOLE_API_TOKEN` to a valid Pi-hole API token. Do not commit a real token to a public repository.
3. Confirm `/usr/sbin/unbound-control` exists and can read Unbound statistics.
4. The script expects Unbound control access to work for its service user. The source comment gives a sudoers example for allowing `/usr/sbin/unbound-control`; review the exact command/permissions for your installation rather than granting broad sudo access.

The OLED worker is optional: missing Luma OLED/PIL imports disable OLED support while leaving the web dashboard available. The current code uses I²C port 1, address 0x3C and a SH1106 device.

## Runtime and endpoints

- Flask listens on `0.0.0.0:5000` in the current source.
- `/` serves the dashboard.
- `/api/data` returns the collected metrics and sparkline/trend values.
- Backend metric collection runs every 10 seconds.
- The browser refreshes dashboard data every five seconds.
- OLED rendering refreshes every 15 seconds.

## Requirements

- Python 3.
- Flask, psutil and requests.
- Unbound with `unbound-control` and statistics enabled.
- Pi-hole API access and a valid API token.
- Optional OLED: `luma.core`, `luma.oled` and Pillow, plus an SH1106 I²C display.
- Nginx and systemd for the supplied deployment configuration.

## Deployment notes and security

- The Nginx file assumes Pi-hole's web server is reachable at 127.0.0.1:8080. Verify this against the actual Pi-hole installation.
- The Flask development server is bound to all interfaces by the current code. Restrict access with firewall rules and/or use a production WSGI server for a persistent deployment.
- Keep API credentials out of version control. Consider loading secrets from a protected environment/config file.
- The supplied systemd unit contains placeholder user, group and paths; it is a template, not ready to install unchanged.
- The Unbound configuration binds resolver and control interfaces to loopback. Preserve that restriction unless you have a deliberate, secured reason to change it.
