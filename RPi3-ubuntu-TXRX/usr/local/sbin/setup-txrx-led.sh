#!/usr/bin/env bash
# First-run configuration for the Raspberry Pi TX/RX LED monitor.
set -Eeuo pipefail

CONFIG_FILE="/etc/default/txrx-led"
LED_GREEN="/sys/class/leds/ACT"
LED_RED="/sys/class/leds/PWR"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "Run this script with sudo: sudo $0"
command -v ip >/dev/null 2>&1 || fail "'ip' is missing. Install it with: sudo apt install iproute2"

# Confirm the LED class devices expected by this Raspberry Pi installation.
for led in "$LED_GREEN" "$LED_RED"; do
    [[ -d "$led" ]] || fail "LED device not found: $led (available devices: $(printf '%s ' /sys/class/leds/* 2>/dev/null || true))"
    [[ -e "$led/brightness" ]] || fail "Missing brightness control: $led/brightness"
    [[ -w "$led/brightness" ]] || fail "Brightness control is not writable: $led/brightness (run with sudo)"
done

printf 'LED checks passed:\n  Green: %s\n  Red:   %s\n' "$LED_GREEN" "$LED_RED"

# Prefer the interface selected by the kernel for the default route.
detected_iface="$(ip -o route show default 2>/dev/null | awk '
    { for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }
')"

# Build a list of present, non-loopback interfaces.
mapfile -t interfaces < <(
    for entry in /sys/class/net/*; do
        name="${entry##*/}"
        [[ "$name" == "lo" ]] || printf '%s\n' "$name"
    done
)

(("${#interfaces[@]}" > 0)) || fail "No non-loopback network interfaces were found."

if [[ -n "$detected_iface" && -d "/sys/class/net/$detected_iface" ]]; then
    printf 'Detected default-route interface: %s\n' "$detected_iface"
    read -r -p "Use this interface? [Y/n] " answer
    case "${answer,,}" in
        n|no) detected_iface="" ;;
        ""|y|yes) ;;
        *) printf 'Unrecognised response; using %s.\n' "$detected_iface" ;;
    esac
fi

if [[ -z "$detected_iface" ]]; then
    printf '\nAvailable interfaces:\n'
    select choice in "${interfaces[@]}"; do
        if [[ -n "${choice:-}" ]]; then
            detected_iface="$choice"
            break
        fi
        printf 'Select a number from the list.\n'
    done
fi

# Validate the selected name before writing a system environment file.
[[ "$detected_iface" =~ ^[A-Za-z0-9_.:-]+$ ]] || fail "Invalid interface name: $detected_iface"
[[ -d "/sys/class/net/$detected_iface" ]] || fail "Interface disappeared: $detected_iface"

install -d -m 0755 /etc/default
tmp_file="$(mktemp /etc/default/txrx-led.XXXXXX)"
trap 'rm -f "$tmp_file"' EXIT
printf 'IFACE=%s\n' "$detected_iface" > "$tmp_file"
chmod 0644 "$tmp_file"
mv "$tmp_file" "$CONFIG_FILE"
trap - EXIT

printf '\nConfiguration saved to %s\n' "$CONFIG_FILE"
printf 'Interface: %s\n' "$detected_iface"
printf '\nNext steps:\n'
printf '  sudo systemctl daemon-reload\n'
printf '  sudo systemctl enable --now txrx-led.service\n'
