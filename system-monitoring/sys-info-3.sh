#!/usr/bin/env bash
export LC_ALL=C

#User Config
RICH_MODE=1
ICON_MODE=2

# Force detection if running in MOTD context
[[ -z "$TERM" || "$TERM" == "dumb" ]] && export TERM=xterm-256color

TERM_OK=1
case "${TERM}" in
    dumb|unknown|"") TERM_OK=0 ;;
esac
if (( TERM_OK == 0 )); then
    RICH_MODE=0; ICON_MODE=0
fi

# Colors
if (( TERM_OK )); then
    W="\033[0m"; LG="\033[38;5;250m"; ICON_COL="\033[38;5;141m"
    G="\033[38;5;120m"; Y="\033[38;5;215m"; R="\033[38;5;203m"
else
# If dumb No colors
    W=""; LG=""; ICON_COL=""; G=""; Y=""; R=""
fi

# Temperature Dynamic Color
temp_color() {
    local t=$(echo "${1:-0}" | tr -d -c '0-9')
    if   (( ${t:-0} < 45 )); then echo "$G"
    elif (( ${t:-0} < 65 )); then echo "$Y"
    else                         echo "$R"
    fi
}

# PSI Dynamic Color
psi_c() {
    awk -v v="${1:-0}" -v g="$G" -v y="$Y" -v r="$R" \
        'BEGIN{if(v<0.1)print g;else if(v<1)print y;else print r}'
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
                    *)            printf " " ;;
                esac
            else
                printf "🖫 "
            fi
            ;;
        kernel) [[ "$ICON_MODE" == "2" ]] && printf "󰌢 " || printf "🖳 " ;;
        user)   [[ "$ICON_MODE" == "2" ]] && printf "󰀄 " || printf "♙ " ;;
        uptime) [[ "$ICON_MODE" == "2" ]] && printf "󰃰 " || printf "⧖ " ;;
        load)   [[ "$ICON_MODE" == "2" ]] && printf " " || printf "🗘 " ;;
        cpu)    [[ "$ICON_MODE" == "2" ]] && printf " " || printf "❖ " ;;
        mem)    [[ "$ICON_MODE" == "2" ]] && printf "󰢶 " || printf "🝚 " ;;
        proc)   [[ "$ICON_MODE" == "2" ]] && printf " " || printf "🗠 " ;;
        psi)    [[ "$ICON_MODE" == "2" ]] && printf "󰓅 " || printf "⚡" ;;
        alert)  [[ "$ICON_MODE" == "2" ]] && printf " " || printf "⚠ " ;;
        *)      printf "• " ;;
    esac
}

PREFIX_FMT=" %b%b%b%-11s%b "

# Data Harvesting
read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg
LOAD_INT=${LOAD1%.*}
CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
CPU_NAME=$(awk -F: '/model name/ {sub(/^ +/,"",$2); print $2; exit}' /proc/cpuinfo)

# Memory & Swap
read -r MEM_TOTAL MEM_AVAIL SWAP_TOTAL SWAP_FREE <<<"$(
awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} /^SwapTotal:/ {st=$2} /^SwapFree:/ {sf=$2} END {print t, a, st, sf}' /proc/meminfo
)"
SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))
SWAP_PCT=$(( SWAP_TOTAL > 0 ? (SWAP_USED * 100 / SWAP_TOTAL) : 0 ))

read -r MEM_USED_G MEM_TOTAL_G SWAP_USED_G SWAP_TOTAL_G <<<"$(
awk -v mt="$MEM_TOTAL" -v ma="$MEM_AVAIL" -v su="$SWAP_USED" -v st="$SWAP_TOTAL" \
'BEGIN {
    printf "%.1f %.1f %.1f %.1f",
    (mt-ma)/1024/1024, mt/1024/1024, su/1024/1024, st/1024/1024
}'
)"

# Virtualization Detection
VIRT_TYPE=""
if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT=$(systemd-detect-virt 2>/dev/null)
    [[ "$VIRT" != "none" ]] && VIRT_TYPE=" ${LG}(VM: $VIRT)${W}"
elif [[ -f /proc/cpuinfo ]]; then
    grep -qi hypervisor /proc/cpuinfo && VIRT_TYPE=" ${LG}(Virtual)${W}"
fi

FAILED_SERVICES=0
if command -v systemctl >/dev/null 2>&1; then
    FAILED_SERVICES=$(systemctl --failed --quiet --no-pager | grep -c "loaded" 2>/dev/null || echo 0)
fi

# Processes Breakdown (User vs Root)
read -r PROC_ROOT PROC_USER <<<"$(
    awk '
    BEGIN {r=0; u=0}
    /^Uid:/ {
        if ($2 == 0) r++
        else u++
    }
    END {print r, u}
    ' /proc/[0-9]*/status 2>/dev/null
)"
# Ensure numeric values even if awk fails
PROC_ROOT=${PROC_ROOT:-0}
PROC_USER=${PROC_USER:-0}
# Make sure they contain only digits
PROC_ROOT=$(( PROC_ROOT + 0 ))
PROC_USER=$(( PROC_USER + 0 ))
PROC_ALL=$(( PROC_ROOT + PROC_USER ))

FAILED_SERVICES=$(systemctl --failed --quiet --no-pager | grep -c "loaded" 2>/dev/null || echo 0)
FAILED_SERVICES=${FAILED_SERVICES//[^0-9]/0}
FAILED_SERVICES=$((FAILED_SERVICES + 0))

# Identity
DISTRO="Linux $(uname -r | cut -d- -f1)"
HOSTNAME=$(cat /proc/sys/kernel/hostname)
KERNEL_VER=$(uname -r)
UPTIME=$(awk '{
    s=int($1)
    d=int(s/86400); s=s%86400
    h=int(s/3600); s=s%3600
    m=int(s/60)
    if(d>0) printf "%dd %dh %dm", d, h, m
    else if(h>0) printf "%dh %dm", h, m
    else printf "%dm", m
}' /proc/uptime)
REBOOT_REQUIRED=""
[[ -f /var/run/reboot-required ]] && REBOOT_REQUIRED="${R}⚠ Reboot Required${W}"
[[ -f /run/reboot-required ]] && REBOOT_REQUIRED="${R}⚠ Reboot Required${W}"
LOGIN_USER=${USER:-$(id -un)}
USERS_COUNT=$(who | wc -l)
USERS_LIST=$(who | awk '{print $1}' | sort -u | paste -sd, -)
# Color Logic: Load
if   (( LOAD_INT < CPU_CORES / 2 )); then LOAD_COL=$G; STATE="LOW"
elif (( LOAD_INT < CPU_CORES ));     then LOAD_COL=$Y; STATE="MED"
else                                      LOAD_COL=$R; STATE="HIGH"; fi
# Color Logic: Processes (Pressure)
PROC_PER_CORE=$(( CPU_CORES > 0 ? PROC_ALL / CPU_CORES : 0 ))
if   (( PROC_PER_CORE < 50 ));  then PROC_COL=$G
elif (( PROC_PER_CORE < 100 )); then PROC_COL=$Y
else                             PROC_COL=$R; fi
# SSH Network Logic Local green - Remote red
REMOTE_IP="local"
SSH_INFO="${SSH_CLIENT:-}"
[[ -n "$SSH_INFO" ]] && REMOTE_IP=${SSH_INFO%% *}
[[ "$REMOTE_IP" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]] && IP_COL=$G || IP_COL=$Y
[[ "$REMOTE_IP" == "local" ]] && IP_COL=$G
# OUTPUT
printf "\n"
printf "$PREFIX_FMT%s\n" "$ICON_COL" "$(icon distro)" "$W" "Distro....:" "$W" "$DISTRO"
LAST_UPDATE=""
if [[ -f /var/lib/apt/periodic/update-success-stamp ]]; then
    UPDATE_AGE=$(( ($(date +%s) - $(stat -c %Y /var/lib/apt/periodic/update-success-stamp)) / 86400 ))
    (( UPDATE_AGE > 7 )) && LAST_UPDATE=" ${Y}(Updates: ${UPDATE_AGE}d ago)${W}"
fi
printf "$PREFIX_FMT%s %s\n" "$ICON_COL" "$(icon kernel)" "$W" "Kernel....:" "$W" "$HOSTNAME" "$KERNEL_VER"
printf "$PREFIX_FMT%s %bfrom %b%s%b\n" "$ICON_COL" "$(icon user)" "$W" "Login.....:" "$W" "$LOGIN_USER" "$LG" "$IP_COL" "$REMOTE_IP" "$W"
printf "$PREFIX_FMT%s %b(%d session%s)%b\n" \
    "$ICON_COL" "$(icon user)" "$W" "Users.....:" "$W" \
    "$USERS_LIST" "$LG" "$USERS_COUNT" "$([[ $USERS_COUNT -ne 1 ]] && echo s)" "$W"
printf "$PREFIX_FMT%s\n" "$ICON_COL" "$(icon uptime)" "$W" "Uptime....:" "$W" "$UPTIME"
[[ -n "$REBOOT_REQUIRED" ]] && printf "$PREFIX_FMT%s\n" \
    "$ICON_COL" "$(icon uptime)" "$W" "Status....:" "$W" "$REBOOT_REQUIRED"
printf "$PREFIX_FMT%b%s, %s, %s %b(%s)%b\n" "$ICON_COL" "$(icon load)" "$W" "Load......:" "$W" "$LOAD_COL" "$LOAD1" "$LOAD5" "$LOAD15" "$W" "$STATE" "$W"
printf "$PREFIX_FMT%s (%s vCPU)%s\n" \
    "$ICON_COL" "$(icon cpu)" "$W" "CPU.......:" "$W" \
    "$CPU_NAME" "$CPU_CORES" "$VIRT_TYPE"
printf "$PREFIX_FMT%sGi used / %sGi total %b(Swap: %sGi/%sGi %d%%)%b\n" "$ICON_COL" "$(icon mem)" "$W" "Memory....:" "$W" "$MEM_USED_G" "$MEM_TOTAL_G" "$LG" "$SWAP_USED_G" "$SWAP_TOTAL_G" "$SWAP_PCT" "$W"
printf "$PREFIX_FMT%b%s%b %b(Root: %s | User: %s)%b\n" "$ICON_COL" "$(icon proc)" "$W" "Processes.:" "$W" "$PROC_COL" "$PROC_ALL" "$W" "$LG" "$PROC_ROOT" "$PROC_USER" "$W"
if (( FAILED_SERVICES > 0 )); then
    printf "$PREFIX_FMT%b%d failed%b\n" \
        "$ICON_COL" "$(icon alert)" "$W" "Services..:" "$W" \
        "$R" "$FAILED_SERVICES" "$W"
fi
# Rich Mode (Slower Loading)
#Top CPU Programs
if (( RICH_MODE )); then
    CPU_LIST=""
    while IFS= read -r line; do
        PID=$(echo "$line" | awk '{print $1}')
        CPU=$(echo "$line" | awk '{print $NF}')
        CMD=$(echo "$line" | awk '{$1=""; $NF=""; print}' | xargs | cut -c1-20)

        CPU_INT=${CPU%.*}
        if (( CPU_INT < 5 )); then
            CPU_COL=$G
        elif (( CPU_INT < 15 )); then
            CPU_COL=$Y
        else
            CPU_COL=$R
        fi

        [[ -n "$CPU_LIST" ]] && CPU_LIST+=" | "
        CPU_LIST+="${CMD}: ${CPU_COL}${CPU}%${W}"
    done < <(ps -eo pid,args,%cpu --sort=-%cpu | head -n 4 | tail -n 3)

    printf "$PREFIX_FMT" "$ICON_COL" "$(icon proc)" "$W" "Top CPU...:" "$W"
    echo -e "${LG}(${CPU_LIST})${W}"
#Top Memory
    MEM_LIST=""
    while IFS= read -r line; do
        PID=$(echo "$line" | awk '{print $1}')
        MEM=$(echo "$line" | awk '{print $NF}')
        CMD=$(echo "$line" | awk '{$1=""; $NF=""; print}' | xargs | cut -c1-20)

        MEM_INT=${MEM%.*}
        if (( MEM_INT < 5 )); then
            MEM_COL=$G
        elif (( MEM_INT < 15 )); then
            MEM_COL=$Y
        else
            MEM_COL=$R
        fi

        [[ -n "$MEM_LIST" ]] && MEM_LIST+=" | "
        MEM_LIST+="${CMD}: ${MEM_COL}${MEM}%${W}"
    done < <(ps -eo pid,args,%mem --sort=-%mem | head -n 4 | tail -n 3)

    printf "$PREFIX_FMT" "$ICON_COL" "$(icon mem)" "$W" "Top Mem...:" "$W"
    echo -e "${LG}(${MEM_LIST})${W}"
fi
#CPU Pressure
if (( RICH_MODE )) && [[ -r /proc/pressure/cpu ]]; then
    PSI_CPU=$(awk -F'=' '/avg10/ {split($2,a," "); print a[1]; exit}' /proc/pressure/cpu)
    PSI_MEM=$(awk -F'=' '/avg10/ {split($2,a," "); print a[1]; exit}' /proc/pressure/memory)
    printf "$PREFIX_FMT%bCPU %s%b | %bMEM %s%b\n" \
        "$ICON_COL" "$(icon psi)" "$W" "PSI.......:" "$W" \
        "$(psi_c "$PSI_CPU")" "$PSI_CPU" "$W" \
        "$(psi_c "$PSI_MEM")" "$PSI_MEM" "$W"
fi
# Load Core Useage Bars
if (( RICH_MODE )) && [[ -r /proc/stat ]]; then
    readarray -t CPU1 < <(awk '/^cpu[0-9]+ / {print}' /proc/stat)
    sleep 0.25
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

        if   (( USAGE < 10 )); then BAR="▁"; COL=$LG
        elif (( USAGE < 30 )); then BAR="▂"; COL=$G
        elif (( USAGE < 60 )); then BAR="▄"; COL=$Y
        else                       BAR="█"; COL=$R; fi
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
# Temperatures Physical Core & Socket
if (( RICH_MODE )) && command -v sensors >/dev/null 2>&1; then
    CORE_LINE=""
    PKG_VAL=$(sensors | awk '/(Package id 0|Tdie|Tctl|temp1):/ {match($0, /\+([0-9]+)/, t); print t[1]; exit}')
    while read -r core temp; do
        COL=$(temp_color "$temp")
        CORE_LINE+=$(printf "%b%d%b:%b%d°C%b " "$LG" "$core" "$W" "$COL" "$temp" "$W")
    done < <(sensors | awk '/(Core|CPU) [0-9]+:/ {match($0, /\+([0-9]+)/, t); match($2, /[0-9]+/, c); print c[0], t[1]}')
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
printf "\n"
