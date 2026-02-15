#!/bin/bash
export TERM=xterm-256color
export LC_ALL=C.UTF-8

#Color Palette
W="\033[0m"
LG="\033[38;5;250m"
G="\033[38;5;120m"
Y="\033[38;5;215m"
R="\033[38;5;203m"
DIM="\033[2m"

max_usage=90
bar_width=20

mapfile -t dfs < <(df -x zfs -x squashfs -x tmpfs -x devtmpfs -x overlay -x efivarfs --output=source,target,pcent,size,used | tail -n+2 | grep -v '/boot/efi' | grep -v '/var/log')

total_kb=0; used_kb=0
declare -A DISK_CACHE_TEMP

for line in "${dfs[@]}"; do
    dev_ptr=$(echo "$line" | awk '{print $1}')
    mnt=$(echo "$line" | awk '{print $2}')
    usage=$(echo "$line" | awk '{print $3}' | tr -d '%')
    size_raw=$(echo "$line" | awk '{print $4}')
    used_raw=$(echo "$line" | awk '{print $5}')
    total_kb=$((total_kb + size_raw)); used_kb=$((used_kb + used_raw))

    # Parent Device detection for non-intrusive smartctl
    real_dev=$(lsblk -no PKNAME "$dev_ptr" | head -n1)
    [[ -z "$real_dev" ]] && dev_path="$dev_ptr" || dev_path="/dev/$real_dev"

    if [[ -z "${DISK_CACHE_TEMP[$dev_path]}" ]]; then
        if sudo smartctl -i -n standby "$dev_path" >/dev/null 2>&1; then
            temp=$(sudo smartctl -A -n standby "$dev_path" 2>/dev/null | awk '$1 == 194 || $1 == 190 {print $10; exit}')
            [[ -z "$temp" ]] && temp=$(sudo smartctl -A -n standby "$dev_path" 2>/dev/null | grep -i "Temp" | head -n1 | awk '{print $10}' | tr -dc '0-9')

            if [[ -n "$temp" ]]; then
                [[ "$temp" -lt 35 ]] && t_c=$G || { [[ "$temp" -lt 45 ]] && t_c=$W || t_c=$R; }
                DISK_CACHE_TEMP[$dev_path]="[ ${t_c}${temp}°C${W} ]"
                DISK_CACHE_ICON="${W}󰋊${W}"
            else
                DISK_CACHE_TEMP[$dev_path]="${DIM}[ ??°C ]${W}"
                DISK_CACHE_ICON="${W}󰋊${W}"
            fi
        else
            DISK_CACHE_TEMP[$dev_path]="${DIM}[ 󰒲 SLEEP ]${W}"
            DISK_CACHE_ICON="${DIM}󰋊${W}"
        fi
    fi

    # Bar Logic (Guaranteed 20 blocks total)
    used_width=$(( (usage * bar_width) / 100 ))
    unused_width=$(( bar_width - used_width ))
    [[ "${usage}" -ge "${max_usage}" ]] && b_c=$R || b_c=$G

    bar="${b_c}"
    for ((i=0; i<used_width; i++)); do bar+="▆"; done
    bar+="${W}${DIM}"
    for ((i=0; i<unused_width; i++)); do bar+="▆"; done
    bar+="${W}"

    hr_size=$(numfmt --to=iec-i --suffix=B $((size_raw * 1024)))
    printf " %b %b %3s%% used out of %7s  %-22s %b\n" "$DISK_CACHE_ICON" "$bar" "$usage" "$hr_size" "$mnt" "${DISK_CACHE_TEMP[$dev_path]}"
done

# --- Total Section ---
if [ "$total_kb" -gt 0 ]; then
    total_percent=$(( (used_kb * 100) / total_kb ))
    t_used_w=$(( (total_percent * bar_width) / 100 ))
    t_unused_w=$(( bar_width - t_used_w ))
    [[ "${total_percent}" -ge "${max_usage}" ]] && t_c=$R || t_c=$G

    t_bar="${t_c}"
    for ((i=0; i<t_used_w; i++)); do t_bar+="▆"; done
    t_bar+="${W}${DIM}"
    for ((i=0; i<t_unused_w; i++)); do t_bar+="▆"; done
    t_bar+="${W}"

    echo -e "\n Total Server disk space:"
    printf " 󰒍 %b  %s | %s%% used out of %s\n" "$t_bar" "$(numfmt --to=iec-i --suffix=B $((used_kb * 1024)))" "$total_percent" "$(numfmt --to=iec-i --suffix=B $((total_kb * 1024)))"
fi
