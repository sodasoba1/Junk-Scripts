#!/bin/bash
export LC_ALL=C
W="\e[0m"
LG="\e[38;5;250m"      # light grey
ICON="\e[38;5;141m"    # purple
G="\e[38;5;120m"
Y="\e[38;5;215m"
R="\e[38;5;203m"

temp_color() {
    local t=$1
    if   (( t < 45 )); then echo "$G"
    elif (( t < 65 )); then echo "$Y"
    else                  echo "$R"
    fi
}

# LOAD
read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg
LOAD_INT=${LOAD1%.*}

# MEMORY & SWAP (authoritative)
read -r MEM_TOTAL MEM_USED MEM_FREE MEM_AVAIL <<<"$(
awk '
/^MemTotal:/     {t=$2}
/^MemAvailable:/ {a=$2}
END {
    used=t-a
    printf "%d %d %d %d\n", t, used, a, a
}' /proc/meminfo
)"

read -r SWAP_TOTAL SWAP_FREE <<<"$(
awk '
/^SwapTotal:/ {t=$2}
/^SwapFree:/  {f=$2}
END { printf "%d %d\n", t, f }
' /proc/meminfo
)"

MEM_TOTAL_G=$(( MEM_TOTAL / 1024 / 1024 ))
MEM_USED_G=$(( MEM_USED / 1024 / 1024 ))
MEM_FREE_G=$(( MEM_FREE / 1024 / 1024 ))

SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))
SWAP_USED_G=$(( SWAP_USED / 1024 / 1024 ))
SWAP_TOTAL_G=$(( SWAP_TOTAL / 1024 / 1024 ))
SWAP_PCT=$(( SWAP_TOTAL > 0 ? (SWAP_USED * 100 / SWAP_TOTAL) : 0 ))


# PROCESS COUNTS
PROC_ROOT=$(ps -eo user= | grep -c '^root$')
PROC_ALL=$(ps -e --no-headers | wc -l)
PROC_USER=$(( PROC_ALL - PROC_ROOT ))


# SYSTEM INFO
CPU_NAME=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | xargs)
CPU_CORES=$(nproc)
UPTIME=$(uptime -p | sed 's/^up //')
DISTRO=$(awk -F= '/PRETTY_NAME/ {gsub(/"/,"",$2); print $2}' /etc/os-release)
KERNEL="$(hostname) $(uname -r)"


# LOAD STATE
if   (( LOAD_INT < CPU_CORES / 2 )); then LOAD_COL=$G; STATE="LOW"
elif (( LOAD_INT < CPU_CORES )); then     LOAD_COL=$Y; STATE="MED"
else                                      LOAD_COL=$R; STATE="HIGH"
fi


# HEADER
echo -e " ${ICON}${W} Distro....:   ${W}${DISTRO}${W}"
echo -e " ${ICON}󰻠${W} Kernel....:   ${W}${KERNEL}${W}"
echo -e " ${ICON}󱘖${W} Login.....:   ${W}$(whoami) from ${SSH_CLIENT%% *}${W}"
echo -e " ${ICON}󰃰${W} Uptime....:   ${W}${UPTIME}${W}"
echo -e " ${ICON}${W} Load......:   ${LOAD_COL}${LOAD1}, ${LOAD5}, ${LOAD15} (${STATE})${W}"
echo -e " ${ICON}${W} Processes.:   ${W}${PROC_ROOT}${W} (root), ${LG}${PROC_USER}${W} (user), ${LG}${PROC_ALL}${W} (total)"
echo -e " ${ICON}${W} CPU.......:   ${W}${CPU_NAME} (${CPU_CORES} vCPU)${W}"
echo -e " ${ICON}${W} Memory....:   ${W}${MEM_USED_G}Gi used, ${MEM_FREE_G}Gi free, ${MEM_TOTAL_G}Gi total (Swap: ${SWAP_USED_G}Gi/${SWAP_TOTAL_G}Gi ${SWAP_PCT}%)${W}"

# TEMPERATURES (coretemp only)
if command -v sensors >/dev/null 2>&1; then
    CORE_LINE=""
    while read -r core temp; do
        COL=$(temp_color "$temp")
        CORE_LINE+="${W}${core} ${COL}${temp}°C${W}  "
    done < <(
        sensors |
        awk '/^Core [0-9]+:/ {
            gsub(/[^0-9]/,"",$2)
            match($0, /\+([0-9]+)/, t)
            print $2, t[1]
        }'
    )

    PKG_TEMP=$(sensors | awk '/Package id 0:/ {match($0, /\+([0-9]+)/, t); print t[1]}')
    PKG_COL=$(temp_color "$PKG_TEMP")

    [[ -n "$CORE_LINE" ]] && \
    echo -e " ${ICON}${W} Cores.....:   ${CORE_LINE}(${ICON}${W} Package ${PKG_COL}${PKG_TEMP}°C${W})"
fi

# PER-CORE LOAD BARS
readarray -t CPU1 < <(awk '/^cpu[0-9]+ / {print}' /proc/stat)
sleep 0.25
readarray -t CPU2 < <(awk '/^cpu[0-9]+ / {print}' /proc/stat)

BAR_LINE=""
NUM_LINE=""

for i in "${!CPU1[@]}"; do
    read -r _ u1 n1 s1 id1 io1 irq1 sirq1 st1 _ _ <<<"${CPU1[$i]}"
    read -r _ u2 n2 s2 id2 io2 irq2 sirq2 st2 _ _ <<<"${CPU2[$i]}"

    T1=$((u1+n1+s1+id1+io1+irq1+sirq1+st1))
    T2=$((u2+n2+s2+id2+io2+irq2+sirq2+st2))
    DT=$((T2 - T1))
    DI=$(( (id2+io2) - (id1+io1) ))
    (( DT <= 0 )) && DT=1

    USAGE=$(( (100 * (DT - DI)) / DT ))

    if   (( USAGE < 10 )); then SYM=" ▁ "; COL=$LG
    elif (( USAGE < 30 )); then SYM=" ▂ "; COL=$G
    elif (( USAGE < 60 )); then SYM=" ▄ "; COL=$Y
    else                        SYM=" █ "; COL=$R
    fi

    BAR_LINE+=$(printf "%b%-3s%b" "$COL" "$SYM" "$W")
    NUM_LINE+=$(printf "%b%-3s%b" "$LG" " $i" "$W")
done

echo -e " ${ICON}󰈐${W} Load/core.:  ${BAR_LINE}"
echo -e " ${ICON}󱎉${W} Core/num..:  ${NUM_LINE}"
