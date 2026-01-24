#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# USER CONFIGURATION
RICH_MODE=1        # 0 = basic, 1 = include PSI data [Requires kernel 4.20+ (most systems from 2019+)] PSU BARS (Bash 4.0+) lmsensors
ICON_MODE=2        # 0 = none, 1 = unicode, 2 = nerd-font
MAX_RUNTIME_MS=300

# Configuration Constants (can be overridden by environment variables)
TEMP_THRESHOLD_LOW=${TEMP_THRESHOLD_LOW:-45}
TEMP_THRESHOLD_MED=${TEMP_THRESHOLD_MED:-65}
PROC_THRESHOLD_LOW=${PROC_THRESHOLD_LOW:-50}
PROC_THRESHOLD_MED=${PROC_THRESHOLD_MED:-100}
PSI_THRESHOLD_LOW=${PSI_THRESHOLD_LOW:-0.1}
PSI_THRESHOLD_MED=${PSI_THRESHOLD_MED:-1.0}

# Terminal Capability Detection
TERM_OK=1
case "${TERM:-dumb}" in
    dumb|unknown|"") TERM_OK=0 ;;
esac
# If dumb terminal, disable rich mode and icons
if (( TERM_OK == 0 )); then
    RICH_MODE=0
    ICON_MODE=0
fi

# Colors
if (( TERM_OK )); then
    W="\033[0m"
    LG="\033[38;5;250m"
    ICON_COL="\033[38;5;141m"
    G="\033[38;5;120m"
    Y="\033[38;5;215m"
    R="\033[38;5;203m"
else
    # If dumb terminal, no colors
    W=""
    LG=""
    ICON_COL=""
    G=""
    Y=""
    R=""
fi

# Temperature Dynamic Color
temp_color() {
    local t=$(echo "${1:-0}" | tr -d -c '0-9')
    if   (( ${t:-0} < TEMP_THRESHOLD_LOW )); then echo "$G"
    elif (( ${t:-0} < TEMP_THRESHOLD_MED )); then echo "$Y"
    else                                          echo "$R"
    fi
}

# PSI Dynamic Color
psi_c() {
    awk -v v="${1:-0}" -v g="$G" -v y="$Y" -v r="$R" -v tl="$PSI_THRESHOLD_LOW" -v tm="$PSI_THRESHOLD_MED" \
        'BEGIN{if(v<tl)print g;else if(v<tm)print y;else print r}'
}

# Icons Nerdfont or Unicode
icon() {
    [[ "$ICON_MODE" == "0" ]] && return
    case "$1" in
        distro)
            if [[ "$ICON_MODE" == "2" ]]; then
                case "${OS_ID:-}" in
                    ubuntu)       printf " " ;;
                    debian)       printf " " ;;
                    arch)         printf "󰣇 " ;;
                    fedora)       printf " " ;;
                    kali)         printf " " ;;
                    raspbian)     printf " " ;;
                    alpine)       printf " " ;;
                    gentoo)       printf "󰣨 " ;;
                    centos)       printf " " ;;
                    *)            printf " " ;; # Generic Linux Icon
                esac
            else
                printf "🖫 " # Unicode fallback
            fi
            ;;
        kernel) [[ "$ICON_MODE" == "2" ]] && printf "󰌢 " || printf "🖳 " ;;
        user)   [[ "$ICON_MODE" == "2" ]] && printf "󰀄 " || printf "♙ " ;;
        uptime) [[ "$ICON_MODE" == "2" ]] && printf "󰃰 " || printf "⧖ " ;;
        load)   [[ "$ICON_MODE" == "2" ]] && printf " " || printf "🗘 " ;;
        cpu)    [[ "$ICON_MODE" == "2" ]] && printf " " || printf "❖ " ;;
        mem)    [[ "$ICON_MODE" == "2" ]] && printf " " || printf "🝚 " ;;
        proc)   [[ "$ICON_MODE" == "2" ]] && printf " " || printf "🗠 " ;;
        psi)    [[ "$ICON_MODE" == "2" ]] && printf "󰓅 " || printf "⚡" ;;
        *)      printf "• " ;;
    esac
}

# Prefix Formatting
PREFIX_FMT=" %b%b%b%-11s%b "

# Safe subsecond sleep function
safe_sleep() {
    local duration="$1"
    if sleep 0.1 2>/dev/null; then
        sleep "$duration"
    elif command -v perl >/dev/null 2>&1; then
        perl -e "select(undef, undef, undef, $duration)"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import time; time.sleep($duration)"
    else
        sleep 1
    fi
}

# Validate IP address
validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "invalid"
        return 1
    fi
    
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if ((octet > 255)); then
            echo "invalid"
            return 1
        fi
    done
    echo "$ip"
    return 0
}

# DATA HARVESTING

# Load Average
if [[ -r /proc/loadavg ]]; then
    read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg
else
    LOAD1="0.00"
    LOAD5="0.00"
    LOAD15="0.00"
fi
LOAD_INT=${LOAD1%.*}
LOAD_INT=${LOAD_INT:-0}

# CPU Information
CPU_CORES=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
# Prevent division by zero
[[ "$CPU_CORES" -eq 0 ]] && CPU_CORES=1

if [[ -r /proc/cpuinfo ]]; then
    CPU_NAME=$(awk -F: '/model name/ {sub(/^ /,"",$2); print $2; exit}' /proc/cpuinfo)
else
    CPU_NAME="Unknown CPU"
fi
[[ -z "$CPU_NAME" ]] && CPU_NAME="Unknown CPU"

# Memory & Swap - Consolidated AWK call
if [[ -r /proc/meminfo ]]; then
    read -r MEM_TOTAL MEM_AVAIL SWAP_TOTAL SWAP_FREE <<<"$(
        awk '/^MemTotal:/ {t=$2}
             /^MemAvailable:/ {a=$2}
             /^SwapTotal:/ {st=$2}
             /^SwapFree:/ {sf=$2}
             END {print t, a, st, sf}' /proc/meminfo
    )"
else
    MEM_TOTAL=0
    MEM_AVAIL=0
    SWAP_TOTAL=0
    SWAP_FREE=0
fi

# Ensure numeric values
MEM_TOTAL=${MEM_TOTAL:-0}
MEM_AVAIL=${MEM_AVAIL:-0}
SWAP_TOTAL=${SWAP_TOTAL:-0}
SWAP_FREE=${SWAP_FREE:-0}

MEM_USED_G=$(awk -v t="$MEM_TOTAL" -v a="$MEM_AVAIL" 'BEGIN {printf "%.1f", (t-a)/1024/1024}')
MEM_TOTAL_G=$(awk -v t="$MEM_TOTAL" 'BEGIN {printf "%.1f", t/1024/1024}')
SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))

# Safe swap percentage calculation
if (( SWAP_TOTAL > 0 )); then
    SWAP_PCT=$(( SWAP_USED * 100 / SWAP_TOTAL ))
else
    SWAP_PCT=0
fi

SWAP_USED_G=$(awk -v s="$SWAP_USED" 'BEGIN {printf "%.1f", s/1024/1024}')
SWAP_TOTAL_G=$(awk -v s="$SWAP_TOTAL" 'BEGIN {printf "%.1f", s/1024/1024}')

# Processes Breakdown (User vs Root via /proc status)
PROC_ROOT=0
PROC_USER=0
if [[ -d /proc ]]; then
    read -r PROC_ROOT PROC_USER <<<"$(
        awk '/^Uid:/ {if ($2 == 0) r++; else u++} END {print r+0, u+0}' /proc/[0-9]*/status 2>/dev/null
    )"
fi
PROC_ROOT=${PROC_ROOT:-0}
PROC_USER=${PROC_USER:-0}
PROC_ALL=$(( PROC_ROOT + PROC_USER ))

# Identity
if [[ -r /etc/os-release ]]; then
    DISTRO=$(awk -F= '/PRETTY_NAME/ {gsub(/"/,"",$2); print $2}' /etc/os-release)
    OS_ID=$(awk -F= '/^ID=/ {gsub(/"/,"",$2); print $2}' /etc/os-release)
else
    DISTRO="Linux"
    OS_ID="linux"
fi
[[ -z "$DISTRO" ]] && DISTRO="Linux"
[[ -z "$OS_ID" ]] && OS_ID="linux"

HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
# Sanitize hostname to prevent ANSI injection
HOSTNAME=$(echo "$HOSTNAME" | tr -cd '[:alnum:].-_')
[[ -z "$HOSTNAME" ]] && HOSTNAME="unknown"

KERNEL_VER=$(uname -r 2>/dev/null || echo "unknown")

if command -v uptime >/dev/null 2>&1; then
    UPTIME=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "unknown")
else
    UPTIME="unknown"
fi

LOGIN_USER=$(whoami 2>/dev/null || echo "unknown")

# Color Logic: Load
if   (( LOAD_INT < CPU_CORES / 2 )); then
    LOAD_COL="$G"
    STATE="LOW"
elif (( LOAD_INT < CPU_CORES )); then
    LOAD_COL="$Y"
    STATE="MED"
else
    LOAD_COL="$R"
    STATE="HIGH"
fi

# Color Logic: Processes (Pressure)
if (( PROC_ALL > 0 && CPU_CORES > 0 )); then
    PROC_PER_CORE=$(( PROC_ALL / CPU_CORES ))
else
    PROC_PER_CORE=0
fi

if   (( PROC_PER_CORE < PROC_THRESHOLD_LOW )); then
    PROC_COL="$G"
elif (( PROC_PER_CORE < PROC_THRESHOLD_MED )); then
    PROC_COL="$Y"
else
    PROC_COL="$R"
fi

# SSH Network Logic: Local green - Remote red
REMOTE_IP="local"
SSH_INFO="${SSH_CLIENT:-}"
if [[ -n "$SSH_INFO" ]]; then
    REMOTE_IP=${SSH_INFO%% *}
    REMOTE_IP=$(validate_ip "$REMOTE_IP" || echo "unknown")
fi

# Determine IP color based on type
if [[ "$REMOTE_IP" == "local" ]]; then
    IP_COL="$G"
elif [[ "$REMOTE_IP" == "unknown" ]] || [[ "$REMOTE_IP" == "invalid" ]]; then
    IP_COL="$LG"
    REMOTE_IP="unknown"
elif [[ "$REMOTE_IP" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]]; then
    IP_COL="$G"
else
    IP_COL="$Y"
fi

# OUTPUT
printf "\n"
printf "$PREFIX_FMT%s\n" "$ICON_COL" "$(icon distro)" "$W" "Distro....:" "$W" "$DISTRO"
printf "$PREFIX_FMT%s %s\n" "$ICON_COL" "$(icon kernel)" "$W" "Kernel....:" "$W" "$HOSTNAME" "$KERNEL_VER"
printf "$PREFIX_FMT%s %bfrom %b%s%b\n" "$ICON_COL" "$(icon user)" "$W" "Login.....:" "$W" "$LOGIN_USER" "$LG" "$IP_COL" "$REMOTE_IP" "$W"
printf "$PREFIX_FMT%s\n" "$ICON_COL" "$(icon uptime)" "$W" "Uptime....:" "$W" "$UPTIME"
printf "$PREFIX_FMT%b%s, %s, %s %b(%s)%b\n" "$ICON_COL" "$(icon load)" "$W" "Load......:" "$W" "$LOAD_COL" "$LOAD1" "$LOAD5" "$LOAD15" "$W" "$STATE" "$W"
printf "$PREFIX_FMT%s (%s vCPU)\n" "$ICON_COL" "$(icon cpu)" "$W" "CPU.......:" "$W" "$CPU_NAME" "$CPU_CORES"
printf "$PREFIX_FMT%sGi used / %sGi total %b(Swap: %sGi/%sGi %d%%)%b\n" "$ICON_COL" "$(icon mem)" "$W" "Memory....:" "$W" "$MEM_USED_G" "$MEM_TOTAL_G" "$LG" "$SWAP_USED_G" "$SWAP_TOTAL_G" "$SWAP_PCT" "$W"
printf "$PREFIX_FMT%b%s%b %b(Root: %s | User: %s)%b\n" "$ICON_COL" "$(icon proc)" "$W" "Processes.:" "$W" "$PROC_COL" "$PROC_ALL" "$W" "$LG" "$PROC_ROOT" "$PROC_USER" "$W"

# Rich Mode (Slower Loading) PSI Info (Pressure Stall Information)
if (( RICH_MODE )) && [[ -r /proc/pressure/cpu ]] && [[ -r /proc/pressure/memory ]]; then
    PSI_CPU=$(awk -F'=' '/avg10/ {split($2,a," "); print a[1]; exit}' /proc/pressure/cpu 2>/dev/null || echo "0.00")
    PSI_MEM=$(awk -F'=' '/avg10/ {split($2,a," "); print a[1]; exit}' /proc/pressure/memory 2>/dev/null || echo "0.00")
    printf "$PREFIX_FMT%bCPU %s%b | %bMEM %s%b\n" \
        "$ICON_COL" "$(icon psi)" "$W" "PSI.......:" "$W" \
        "$(psi_c "$PSI_CPU")" "$PSI_CPU" "$W" \
        "$(psi_c "$PSI_MEM")" "$PSI_MEM" "$W"
fi

# Load Core Usage Bars
if (( RICH_MODE )) && [[ -r /proc/stat ]]; then
    # Check if we have readarray (bash 4+)
    if command -v readarray >/dev/null 2>&1 || declare -F readarray >/dev/null 2>&1; then
        readarray -t CPU1 < <(awk '/^cpu[0-9]+ / {print}' /proc/stat)
        safe_sleep 0.25
        readarray -t CPU2 < <(awk '/^cpu[0-9]+ / {print}' /proc/stat)

        printf "$PREFIX_FMT" "$ICON_COL" "$(icon load)" "$W" "Load/core.:" "$W"
        for i in "${!CPU1[@]}"; do
            read -r _ u1 n1 s1 id1 io1 irq1 sirq1 st1 _ _ <<<"${CPU1[$i]}"
            read -r _ u2 n2 s2 id2 io2 irq2 sirq2 st2 _ _ <<<"${CPU2[$i]}"
            T1=$((u1+n1+s1+id1+io1+irq1+sirq1+st1))
            T2=$((u2+n2+s2+id2+io2+irq2+sirq2+st2))
            DT=$((T2 - T1))
            DI=$(( (id2+io2) - (id1+io1) ))
            (( DT <= 0 )) && DT=1
            USAGE=$(( (100 * (DT - DI)) / DT ))

            if   (( USAGE < 10 )); then BAR="▁"; COL="$LG"
            elif (( USAGE < 30 )); then BAR="▂"; COL="$G"
            elif (( USAGE < 60 )); then BAR="▄"; COL="$Y"
            else                        BAR="█"; COL="$R"; fi
            printf "%b%s%b   " "$COL" "$BAR" "$W"
        done
        printf "\n"

        # Core Number Physical & Virtual
        printf "$PREFIX_FMT" "$ICON_COL" "$(icon cpu)" "$W" "Core/num..:" "$W"
        for ((i=0; i<CPU_CORES; i++)); do
            printf "%-4d" "$i"
        done
        printf "\n"
    fi
fi

# Temperatures Physical Core & Socket (requires lm-sensors)
if (( RICH_MODE )) && command -v sensors >/dev/null 2>&1; then
    # Cache sensors output to avoid multiple calls
    SENSOR_DATA=$(sensors 2>/dev/null || echo "")
    
    if [[ -n "$SENSOR_DATA" ]]; then
        CORE_LINE=""
        PKG_VAL=$(echo "$SENSOR_DATA" | awk '/(Package id 0|Tdie|Tctl|temp1):/ {match($0, /\+([0-9]+)/, t); print t[1]; exit}')

        while IFS= read -r line; do
            core=$(echo "$line" | awk '{print $1}')
            temp=$(echo "$line" | awk '{print $2}')
            COL=$(temp_color "$temp")
            CORE_LINE+=$(printf "%b%d%b:%b%d°C%b " "$LG" "$core" "$W" "$COL" "$temp" "$W")
        done < <(echo "$SENSOR_DATA" | awk '/(Core|CPU) [0-9]+:/ {match($0, /\+([0-9]+)/, t); gsub(/[^0-9]/,"",$2); print $2, t[1]}')

        if [[ -n "$CORE_LINE" || -n "$PKG_VAL" ]]; then
            printf "$PREFIX_FMT" "$ICON_COL" "$(icon mem)" "$W" "Cores.....:" "$W"
            printf "%s" "$CORE_LINE"
            if [[ -n "$PKG_VAL" ]]; then
                PKG_COL=$(temp_color "$PKG_VAL")
                printf "%b(%b%bPkg:%b%d°C%b)" "$LG" "$ICON_COL" "$W" "$PKG_COL" "$PKG_VAL" "$W"
            fi
            printf "\n"
        fi
    fi
fi
printf "\n"
