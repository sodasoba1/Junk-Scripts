#!/usr/bin/env bash
set -euo pipefail

# ==============================================
# Home Lab Authentication Threat Monitor
# Optimized for small environments
# ==============================================

if [[ $EUID -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

WINDOW="48 hours ago"
HOST=$(hostname)
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "================================================="
echo " Home Lab Authentication Monitor"
echo " Host: $HOST"
echo " Window: last 48 hours"
echo " Generated (UTC): $NOW"
echo "================================================="
echo

# -------------------------------------------------
# Log Source Detection
# -------------------------------------------------

LOG_FILES=()
for f in /var/log/auth.log* /var/log/secure*; do
  [[ -e "$f" ]] && LOG_FILES+=("$f")
done

USE_JOURNAL=false
if [[ ${#LOG_FILES[@]} -eq 0 ]]; then
  if command -v journalctl >/dev/null 2>&1; then
    USE_JOURNAL=true
  else
    echo "No authentication logs found."
    exit 1
  fi
fi

search_logs() {
  local pattern="$1"
  if [[ "$USE_JOURNAL" == true ]]; then
    journalctl -u ssh -u sshd --since "$WINDOW" --no-pager 2>/dev/null \
      | grep -E "$pattern" || true
  else
    zgrep -hE "$pattern" "${LOG_FILES[@]}" 2>/dev/null | tail -n 5000 || true
  fi
}

FAILED="Failed password|Invalid user|authentication failure"
SUCCESS="Accepted password|Accepted publickey"
SUDO="sudo:"
SU="su:"

FAILED_LOGS=$(search_logs "$FAILED")
SUCCESS_LOGS=$(search_logs "$SUCCESS")
SUDO_LOGS=$(search_logs "$SUDO")
SU_LOGS=$(search_logs "$SU")

declare -A FAIL_COUNT
declare -A SUCCESS_COUNT
declare -A SCORE

extract_ip() {
  grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' || true
}

# -------------------------------------------------
# Parse Failed Attempts
# -------------------------------------------------

while read -r line; do
  [[ -z "$line" ]] && continue
  ip=$(echo "$line" | extract_ip)
  [[ -z "$ip" ]] && continue
  ((FAIL_COUNT["$ip"]++))
done <<< "$FAILED_LOGS"

# -------------------------------------------------
# Parse Success Attempts
# -------------------------------------------------

while read -r line; do
  [[ -z "$line" ]] && continue
  ip=$(echo "$line" | extract_ip)
  [[ -z "$ip" ]] && continue
  ((SUCCESS_COUNT["$ip"]++))
done <<< "$SUCCESS_LOGS"

PRIV_ESC_TOTAL=$(echo -e "$SUDO_LOGS\n$SU_LOGS" | wc -l)

# -------------------------------------------------
# Threat Scoring (Home Lab Tuned)
# -------------------------------------------------
# Philosophy:
# - Internet scanners are normal.
# - Real risk = fail→success or internal suspicious access.
# - High brute counts matter less unless followed by success.

is_private_ip() {
  [[ "$1" =~ ^10\. ]] ||
  [[ "$1" =~ ^192\.168\. ]] ||
  [[ "$1" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]
}

for ip in "${!FAIL_COUNT[@]}"; do
  SCORE["$ip"]=$(( FAIL_COUNT["$ip"] * 2 ))

  # Brute threshold
  if (( FAIL_COUNT["$ip"] > 40 )); then
    SCORE["$ip"]=$(( SCORE["$ip"] + 20 ))
  fi
done

for ip in "${!SUCCESS_COUNT[@]}"; do
  SCORE["$ip"]=$(( ${SCORE["$ip"]:-0} + 20 ))

  # Fail → Success pattern (very suspicious)
  if [[ -n "${FAIL_COUNT[$ip]:-}" ]]; then
    SCORE["$ip"]=$(( SCORE["$ip"] + 50 ))
  fi

  # Internal IP with unexpected success
  if is_private_ip "$ip"; then
    SCORE["$ip"]=$(( SCORE["$ip"] + 15 ))
  fi
done

# Privilege escalation context
if (( PRIV_ESC_TOTAL > 0 )); then
  for ip in "${!SCORE[@]}"; do
    SCORE["$ip"]=$(( SCORE["$ip"] + 10 ))
  done
fi

classify() {
  local s=$1
  if (( s >= 90 )); then
    echo "CRITICAL"
  elif (( s >= 50 )); then
    echo "HIGH"
  elif (( s >= 20 )); then
    echo "MEDIUM"
  else
    echo "LOW"
  fi
}

# -------------------------------------------------
# Output
# -------------------------------------------------

echo "Summary:"
printf "  Failed Attempts:       %s\n" "$(echo "$FAILED_LOGS" | wc -l)"
printf "  Successful Logins:     %s\n" "$(echo "$SUCCESS_LOGS" | wc -l)"
printf "  Privilege Escalations: %s\n" "$PRIV_ESC_TOTAL"
echo

echo "Threat Table:"
echo "------------------------------------------------------------"
printf "%-16s %-7s %-7s %-7s %-10s\n" \
"IP Address" "Fails" "Success" "Score" "Risk"
echo "------------------------------------------------------------"

for ip in "${!SCORE[@]}"; do
  printf "%-16s %-7s %-7s %-7s %-10s\n" \
    "$ip" \
    "${FAIL_COUNT[$ip]:-0}" \
    "${SUCCESS_COUNT[$ip]:-0}" \
    "${SCORE[$ip]}" \
    "$(classify "${SCORE[$ip]}")"
done

echo "------------------------------------------------------------"
echo

echo "Home Lab Guidance:"
echo " - LOW: internet noise."
echo " - MEDIUM: brute force source."
echo " - HIGH: possible credential compromise."
echo " - CRITICAL: fail→success pattern or internal misuse."
echo
