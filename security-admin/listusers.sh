#!/usr/bin/env bash
set -euo pipefail
if ! command -v sudo >/dev/null 2>&1; then
  echo "ERROR: sudo is required to inspect sudo policy." >&2
  exit 1
fi
echo "=== ACTIVE LOGIN SESSIONS (who) ==="
if command -v who >/dev/null 2>&1; then
  who -u || true
else
  echo "who is unavailable"
fi
echo
echo "=== ACCOUNTS FROM NSS (getent passwd) ==="
if ! command -v getent >/dev/null 2>&1; then
  echo "ERROR: getent is required." >&2
  exit 1
fi
while IFS=: read -r username _ uid gid gecos home shell; do
  [[ -n "$username" ]] || continue
  if [[ "$uid" -eq 0 ]]; then
    kind="UID 0 (root-equivalent)"
  elif [[ -n "$shell" && "$username" != "nobody" && "$shell" != */nologin && "$shell" != */false ]]; then
    kind="interactive-shell account"
  else
    continue
  fi
  printf '\nUser: %s | UID: %s | %s | shell: %s\n' "$username" "$uid" "$kind" "$shell"
  if [[ "$uid" -eq 0 ]]; then
    echo "Privilege: UID 0; this account has root identity."
  else
    if policy=$(sudo -n -l -U "$username" 2>&1); then
      printf '%s\n' "$policy" | awk '
        /may run the following commands/ { in_rules=1; next }
        in_rules && /^[[:space:]]*\(/ { print "Sudo rule: " $0; found=1 }
        END { if (!found) print "Sudo rule: no command specification reported (inspect sudo output if needed)." }
      '
      if printf '%s\n' "$policy" | awk '
        /^[[:space:]]*\(/ {
          line=$0
          sub(/^[[:space:]]*\([^)]*\)[[:space:]]*/, "", line)
          sub(/^([A-Z_]+:[[:space:]]*)+/, "", line)
          if (line == "ALL") found=1
        }
        END { exit !found }
      '; then
        echo "Classification: ALL-command rule detected; review RunAs scope and tags above."
      else
        echo "Classification: no ALL-command rule detected; restricted rules may still grant powerful access."
      fi
    else
      echo "Sudo policy query unavailable: $policy"
    fi
  fi
done < <(getent passwd)
echo
echo "Note: NSS accounts are not necessarily local accounts. This is a review aid, not a complete privilege-escalation audit."
