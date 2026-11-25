# Security Administration

Small Linux host-inspection scripts covering authentication events, listening network sockets and currently logged-in users.

## Files

| File | Name | Purpose and functionality |
|---|---|---|
| `check-logs.sh` | Authentication Threat Monitor | Requires root. Reads the last 48 hours of SSH/authentication events from `/var/log/auth.log*` or `/var/log/secure*`, falling back to the SSH systemd journal when no log files are found. Counts failed and successful logins by IPv4 address, adds simple risk scores for repeated failures, successful logins and fail-then-success patterns, and prints a LOW/MEDIUM/HIGH/CRITICAL summary. It also counts sudo/su log entries as context. |
| `listcon.sh` | Listening Connection / Socket Listing | Runs `netstat -tulnp` and formats TCP/UDP local address, foreign address, state and PID/program fields. |
| `listusers.sh` | Logged-in User and Privilege Listing | Reads usernames from `who`, then checks each user with `sudo -l -U` and labels root and users whose sudo rules contain `ALL`. |

## Usage

```bash
sudo ./check-logs.sh
sudo ./listcon.sh
./listusers.sh
```

The connection listing may require root to show process IDs/program names. The user listing invokes sudo to inspect privileges.

## Requirements

- Bash.
- `journalctl` or readable authentication log files for `check-logs.sh`.
- `netstat` (usually provided by `net-tools`) for `listcon.sh`.
- `who` and `sudo` for `listusers.sh`.

## Interpretation limits

These are local inspection/reporting helpers, not an intrusion-detection system or an automated response tool. The threat score is a heuristic, not proof of compromise. The log parser extracts IPv4 addresses only, and its scoring rules should be reviewed before relying on the risk labels. It does not block addresses or change firewall rules.
