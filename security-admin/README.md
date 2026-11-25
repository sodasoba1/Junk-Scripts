# Security Administration

Linux host-inspection tools for reviewing authentication activity, network sockets, login sessions and sudo policy. These scripts are read-only reporting helpers: they do not block addresses, change firewall rules, terminate sessions or modify account permissions.

## Contents

| File | Purpose |
|---|---|
| `check-logs.sh` | Compatibility launcher for the Python authentication-event analyser. |
| `check-logs.py` | Parses SSH/PAM authentication events, reports IPv4/IPv6 sources and flags time-correlated failure patterns. |
| `listcon.sh` | Lists listening TCP/UDP sockets and established TCP connections using `ss`, with a legacy `netstat` fallback. |
| `listusers.sh` | Lists active sessions and NSS accounts, identifies UID-0 accounts and displays sudo command specifications where available. |
| `tests/test_security_admin.py` | Parser regression tests using synthetic log entries. |

## Requirements

- Bash.
- Python 3.8+ for authentication analysis.
- systemd `journalctl` is preferred; authentication log files are used as a fallback.
- `iproute2` (`ss`) for network inspection; `net-tools` (`netstat`) is an optional fallback.
- `sudo`, `getent` and `who` for account/session inspection.

Debian/Ubuntu:

```bash
sudo apt update
sudo apt install -y bash python3 systemd iproute2 sudo
# Optional legacy network fallback:
sudo apt install -y net-tools
```

## Installation

```bash
git clone https://github.com/sodasoba1/Junk-Scripts.git
cd Junk-Scripts/security-admin
chmod +x check-logs.sh check-logs.py listcon.sh listusers.sh
```

## Usage

Run from this directory.

### Authentication activity

```bash
sudo ./check-logs.sh                 # last 48 hours
sudo ./check-logs.sh --hours 24      # last 24 hours
sudo ./check-logs.sh --json          # machine-readable JSON
sudo ./check-logs.sh --hours 12 --json
```

The analyser prefers the systemd journal and asks it for the selected time range. Traditional syslog timestamps are interpreted in the host's local timezone. If the journal query fails or contains no matching authentication records, it reads current and rotated `/var/log/auth.log*` and `/var/log/secure*` files, including gzip-compressed rotations, and applies the same timestamp window. File entries without a recognised timestamp are counted as undated and excluded rather than silently mixed into the report. Unreadable files are reported as warnings.

It recognises common OpenSSH accepted/failed password, public-key, keyboard-interactive, hostbased, GSSAPI and `none` authentication messages, invalid-user probes (reported separately from confirmed failed attempts), and PAM authentication failures containing an `rhost`. Near-identical PAM/sshd records for the same IP, username and outcome within three seconds are suppressed to reduce duplicate counting. It extracts the source address from the relevant SSH/PAM field and validates it as IPv4 or IPv6. It does not guess an IP from an arbitrary part of a log line.

The report includes per-address failed/successful counts, invalid-user probes, usernames, recent event evidence, duplicate-line suppression, unparsed/undated candidate counts, and alert timelines for:
- At least 8 failures for the same source IP and username in a rolling 10-minute window.
- At least 15 failures from one source IP across accounts in a rolling 10-minute window (password-spray pattern).
- At least 8 invalid-user probes from one source IP in a rolling 10-minute window.
- At least 5 failures for the same source IP and username in the 30 minutes before a successful authentication.

These are deliberately transparent pattern alerts, not risk scores, probability estimates or proof of compromise. They may miss attacks that use different usernames, distributed source addresses, unsupported log formats or authentication systems outside the parsed SSH/PAM messages. Review original logs and correlate with account/session activity.

### Network sockets

```bash
sudo ./listcon.sh
```

Uses `ss -lntup` to show listening TCP/UDP sockets and `ss -ntup state established` to show established TCP connections. Process ownership may be unavailable for some sockets. If `ss` is unavailable, the script falls back to `netstat -tulnp`; that legacy fallback only reports listening sockets. A listening socket does not prove internet reachability: firewall, routing, NAT and interface binding also matter.

### Sessions and account privileges

```bash
sudo ./listusers.sh
```

Shows sessions reported by `who -u`, then reviews accounts returned by the system's Name Service Switch (`getent passwd`). It includes all UID-0 accounts and accounts with an interactive login shell (excluding `nobody`), and prints sudo command specifications where `sudo -l -U` permits the query.

An ALL-command rule is highlighted, but restricted sudo rules can still be powerful. Review the complete sudo output, RunAs scope, command paths, tags and included sudoers policy. NSS accounts can come from local files, LDAP or other configured identity providers; they are not necessarily local accounts. This is not a complete audit of capabilities, setuid programs, groups, polkit, containers or other privilege paths.

## Tests

Run parser regression tests with:

```bash
python3 -m unittest discover -s tests -v
```

The tests use synthetic log lines and do not require root, a running journal or access to real authentication logs.

## Limitations

- Detection depends on log messages being present and matching supported SSH/PAM formats. The script is not an IDS and does not monitor events in real time.
- Journal data may be volatile or incomplete; file logs may be rotated, missing or inaccessible.
- Events without a parseable timestamp or source address are not included in the per-IP event table; the report exposes undated/unparsed counts.
- The analyser only recognises the listed authentication message families. It does not parse every service's authentication logs.
- Source IPs may represent NAT gateways, VPN endpoints, bastions or proxies rather than the original person/device.
- Socket inspection is a point-in-time view and does not assess service vulnerabilities or firewall exposure.
- Account inspection is a review aid, not a full security audit.
- None of the scripts automatically changes host configuration or blocks activity.
