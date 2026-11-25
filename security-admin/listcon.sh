#!/usr/bin/env bash
set -euo pipefail
if [[ ${EUID} -ne 0 ]]; then
  echo "WARNING: run with sudo to see all process owners." >&2
fi
if command -v ss >/dev/null 2>&1; then
  echo "=== LISTENING TCP/UDP SOCKETS (ss) ==="
  ss -H -lntup || { echo "ERROR: ss failed." >&2; exit 1; }
  echo
  echo "=== ESTABLISHED TCP CONNECTIONS ==="
  ss -H -ntup state established || { echo "ERROR: ss connection query failed." >&2; exit 1; }
elif command -v netstat >/dev/null 2>&1; then
  echo "WARNING: iproute2/ss unavailable; using legacy netstat. Output is listening sockets only."
  netstat -tulnp
else
  echo "ERROR: neither ss (iproute2) nor netstat (net-tools) is installed." >&2
  exit 1
fi
