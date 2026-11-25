# Security Administration

Small Linux host-inspection scripts for reviewing authentication activity, listening TCP/UDP sockets and currently logged-in users. They are read-only reporting helpers: they do not block addresses, change firewall rules, terminate sessions or modify account permissions.

## Contents

| File | Name | Purpose |
|---|---|---|
| `check-logs.sh` | Authentication Threat Monitor | Reads authentication-related log events, counts matched failed and successful login events by IPv4 address, reports sudo/su event counts as host-level context, and assigns heuristic risk scores. |
| `listcon.sh` | Listening Connection / Socket Listing | Runs `netstat -tulnp` and displays listening TCP and UDP sockets, local and foreign addresses, TCP state where applicable, and PID/program information when permissions allow. |
| `listusers.sh` | Logged-in User and Privilege Listing | Lists usernames returned by `who` and checks each logged-in account with `sudo -l -U`. It marks root and accounts whose sudo listing contains `ALL`. |

## Requirements

The scripts target Linux distributions with Bash.

| Requirement | Used by | Package / command |
|---|---|---|
| Bash | All scripts | `bash` |
| Authentication logs or systemd journal | `check-logs.sh` | `/var/log/auth.log*`, `/var/log/secure*`, or `journalctl` |
| Compressed-log reader | `check-logs.sh` | `zgrep` (normally supplied by `gzip`) |
| Standard text and system utilities | All scripts | `grep`, `awk`, `head`, `tail`, `date`, `hostname`, `who` |
| Network socket listing | `listcon.sh` | `netstat` (provided by `net-tools`) |
| Sudo policy inspection | `listusers.sh` | `sudo` |

### Install on Debian / Ubuntu

```bash
sudo apt update
sudo apt install -y bash coreutils grep gawk gzip net-tools sudo
```

On systems using systemd, `journalctl` is normally provided by the systemd package. The log monitor requires root because it reads protected authentication logs and the system journal.

## Installation

Clone the repository or download and extract it. From the repository root:

```bash
git clone https://github.com/sodasoba1/Junk-Scripts.git
cd Junk-Scripts/security-admin
chmod +x check-logs.sh listcon.sh listusers.sh
```

If you already have the repository, change into its `security-admin` directory and run the `chmod` command if the scripts are not executable.

## Usage

Run the commands from the `security-admin` directory.

### 1. Authentication activity and risk summary

```bash
sudo ./check-logs.sh
```

The script requires root. It searches for `/var/log/auth.log*` and `/var/log/secure*` first, including rotated files that match those names. If none are found, it falls back to `journalctl` and searches journal entries from the last 48 hours.

The report contains:
- Hostname and report-generation time in UTC.
- Counts of matched failed-authentication events and accepted SSH password/public-key logins.
- A count of matched sudo/su log entries, shown as host-level context.
- An IPv4 table with failed count, successful count, heuristic score and risk label.

**Important time-window distinction:** the script identifies the selected source in its output. The systemd journal fallback uses the 48-hour window. The file-log path searches the available current and rotated authentication logs and limits each matched search to its last 5,000 lines; it does not filter those file entries by timestamp. Consequently, file-mode results may include events older than 48 hours. Only journal-mode results are bounded to the stated 48-hour period.

The parser extracts the first plausible IPv4 address from each matching event. It does not parse IPv6 addresses. Failed-event matching includes `Failed password`, `Invalid user` and `authentication failure`; successful-event matching includes `Accepted password` and `Accepted publickey`.

#### Risk-score calculation

The score is a simple prioritisation heuristic, not a probability or a confirmed incident classification:

| Event pattern | Score change |
|---|---:|
| Each matched failed event for an IP | +2 |
| More than 40 matched failed events for an IP | +20 additional |
| At least one matched successful login for an IP | +20 |
| The same IP appears in both failed and successful event sets | +50 additional |
| Successful login from an RFC1918 private IPv4 address | +15 additional |

The same-IP failed/successful rule checks whether both types appear in the collected results; it does **not** establish that the failed attempts occurred before the successful login. Routine private-network logins can also receive the private-address bonus. These rules can therefore produce false positives and should be interpreted alongside the original authentication logs.

Risk labels are assigned from the final score:
- **LOW:** below 20.
- **MEDIUM:** 20–49.
- **HIGH:** 50–89.
- **CRITICAL:** 90 or higher.

Sudo/su entries are counted separately as host-level context. They are not attributed to a remote source IP and do not increase an IP's score. A sudo or su log entry is not, by itself, proof of privilege escalation or malicious activity.

### 2. Listening network sockets

```bash
sudo ./listcon.sh
```

This runs `netstat -tulnp`:
- `-t`: TCP sockets.
- `-u`: UDP sockets.
- `-l`: listening sockets.
- `-n`: numeric addresses and ports; no DNS/service-name lookups.
- `-p`: process ID and program name where permissions allow.

TCP rows include their connection state (normally `LISTEN`). UDP does not have a TCP-style state, so the script prints “not applicable” and reads the PID/program field from the correct UDP output column. Run with `sudo` to maximise process visibility. A blank or unavailable PID/program field does not prove that no process owns the socket.

### 3. Logged-in users and sudo rules

```bash
sudo ./listusers.sh
```

The script:
1. Gets the usernames currently represented in `who` output.
2. Prints `root (root)` for a root session.
3. Runs `sudo -l -U USERNAME` for each other logged-in username.
4. Adds `(sudo)` when that command's output contains the text `ALL`.

This is a quick indicator, not a complete sudo-policy parser. It only checks users with sessions shown by `who`; it does not enumerate every local account. The text match can be broader than a full interpretation of the user's effective sudo rules. For an authoritative per-user view, inspect the output of:

```bash
sudo -l -U USERNAME
```

Multiple active sessions for the same username may cause that username to be listed more than once.

## Suggested review workflow

1. Run `sudo ./check-logs.sh` and note any IPs with HIGH or CRITICAL scores.
2. Inspect the underlying authentication log entries for those addresses and check whether a successful login was expected.
3. Review sudo/su event counts separately; correlate them with the relevant system log entries and account activity.
4. Run `sudo ./listcon.sh` and investigate listening ports and processes that are not expected on the host.
5. Run `sudo ./listusers.sh` and inspect any unexpected logged-in accounts or sudo grants.
6. Verify findings against the host's firewall, SSH configuration, account records and service configuration. These scripts do not perform those checks automatically.

## Interpretation and security limits

- These scripts are local inspection/reporting helpers, not an intrusion-detection system, security audit framework or automated response tool.
- The authentication monitor uses text-pattern matching and IPv4 extraction. Different distributions, PAM configurations, SSH logging formats and custom log destinations may produce events it does not recognise.
- The file-log path may include older rotated entries and is capped at 5,000 matching lines per search. The journal fallback is time-filtered to 48 hours.
- IPv6 authentication sources are not included in the threat table.
- A failed event and a successful event from the same IP do not prove a compromise or establish event order.
- Private IPv4 addresses are not inherently suspicious; the private-address score bonus is only a configurable heuristic.
- Sudo/su log counts are contextual. They do not establish that privilege escalation occurred or identify the remote IP responsible.
- Socket listings show listening sockets only. They do not establish whether a service is vulnerable, externally reachable through the firewall/NAT, or safe to expose.
- The user listing only covers sessions reported by `who`; it does not show every account or every active process.
- No script blocks IP addresses, changes firewall rules, disables accounts, kills processes or modifies system configuration.

Review source logs and host configuration before taking action based on a score or label.
