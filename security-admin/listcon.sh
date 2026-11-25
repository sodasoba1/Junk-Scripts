#!/bin/bash
set -euo pipefail

if ! command -v netstat >/dev/null 2>&1; then
  echo "ERROR: netstat is not installed. Install the net-tools package." >&2
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "WARNING: run with sudo to show PID/program names; socket addresses may still be listed without it." >&2
fi

result=$(netstat -tulnp) || {
  echo "ERROR: netstat failed to list sockets." >&2
  exit 1
}

# netstat's UDP rows do not contain a TCP-style State column, so their
# PID/program field is column 6 rather than column 7.
printf '%s\n' "$result" | awk '
/^tcp/ {
  printf "Protocol: TCP\n"
  printf "Local Address: %s\n",$4
  printf "Foreign Address: %s\n",$5
  printf "State: %s\n",$6
  printf "PID/Program name: %s\n\n",$7
}
/^udp/ {
  printf "Protocol: UDP\n"
  printf "Local Address: %s\n",$4
  printf "Foreign Address: %s\n",$5
  printf "State: not applicable\n"
  printf "PID/Program name: %s\n\n",$6
}'
