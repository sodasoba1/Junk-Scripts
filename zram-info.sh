#!/bin/bash
export TERM=xterm-256color
export LC_ALL=C

# Color Palette
W="\033[0m"; LG="\033[38;5;250m"; G="\033[38;5;120m"
Y="\033[38;5;215m"; R="\033[38;5;203m"; ICON_COL="\033[38;5;141m"
DIM="\033[2m"
bar_width=20

# Check if zramctl exists
if ! command -v zramctl >/dev/null 2>&1; then
    exit 0
fi

# Get ZRAM data
mapfile -t zrams < <(zramctl --bytes --output NAME,DISKSIZE,DATA,COMPR 2>/dev/null | tail -n+2)

if [ ${#zrams[@]} -eq 0 ]; then
    exit 0
fi

printf " %b󰞹 %b%-11s%b\n" "$ICON_COL" "$W" "ZRAM Stats:" "$W"

for line in "${zrams[@]}"; do
    # Parse line efficiently
    read -r name_path total used compr <<<"$line"
    name=${name_path##*/}

    # Get algorithm from sysfs
    algo="unknown"
    if [[ -f "/sys/block/$name/comp_algorithm" ]]; then
        algo=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^\[.*\]$/) {gsub(/[\[\]]/,"",$i); print $i}}' \
               "/sys/block/$name/comp_algorithm")
    fi

    # Calculate percentage used
    pct=0
    [[ "$total" -gt 0 ]] && pct=$(( 100 * used / total ))

    # Calculate Compression Ratio
    ratio="0.00"
    [[ "$compr" -gt 0 ]] && ratio=$(awk -v u="$used" -v c="$compr" 'BEGIN {printf "%.2f", u/c}')

    # Build Bar
    used_w=$(( (pct * bar_width) / 100 ))
    unused_w=$(( bar_width - used_w ))
    [[ "$pct" -gt 80 ]] && b_c=$R || b_c=$G

    bar="${b_c}"
    for ((i=0; i<used_w; i++)); do bar+="▆"; done
    bar+="${W}${DIM}"
    for ((i=0; i<unused_w; i++)); do bar+="▆"; done
    bar+="${W}"

    # Human readable sizes
    hr_used=$(numfmt --to=iec-i --suffix=B "$used")
    hr_total=$(numfmt --to=iec-i --suffix=B "$total")

    # Format Output line
    printf " %b %b %3s%% used out of %7s  %bRatio: %s:1 %b[%s]%b\n" \
        "$ICON_COL" "$bar" "$pct" "$hr_total" "$LG" "$ratio" "$DIM" "$algo" "$W"

    # Calculate and display RAM saved
    savings=$(( used - compr ))
    if (( compr > 0 && savings > 0 )); then
    hr_savings=$(numfmt --to=iec-i --suffix=B "$savings")
    savings_pct=$(( 100 * savings / used ))
    printf " %b󰄦 %bRAM saved: %s (%d%% compression efficiency)%b\n" \
        "$ICON_COL" "$LG" "$hr_savings" "$savings_pct" "$W"
    fi

    printf "\n"
done
