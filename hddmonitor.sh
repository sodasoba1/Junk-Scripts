#!/bin/bash
# config
max_usage=90
bar_width=20

# colors
white="\e[39m"
green="\e[1;92m"
yellow="\e[1;93m"
orange="\e[38;5;208m"
red="\e[1;91m"
dim="\e[2m"
undim="\e[0m"

echo -e "${white}--- Server Vitals ---${undim}"

# 1. CPU Temps
if command -v sensors > /dev/null; then
    temps=$(sensors | grep "Core" | awk '{print $3}' | tr -d '+')
    printf "  CPU: "
    for t in $temps; do printf "%s  " "$t"; done
    echo ""
fi

# 2. IO Wait
iowait=$(top -bn1 | grep "Cpu(s)" | awk '{print $10}')
printf " 󱘖 IO Wait: ${yellow}%s%%${undim}\n" "$iowait"

echo -e "\n${white}--- Storage & Health ---${undim}"

# disk usage
mapfile -t dfs < <(df -x zfs -x squashfs -x tmpfs -x devtmpfs -x overlay -x efivarfs --output=source,target,pcent,size,used | tail -n+2 | grep -v '/boot/efi')

for line in "${dfs[@]}"; do
    dev=$(echo "$line" | awk '{print $1}')
    mnt=$(echo "$line" | awk '{print $2}')
    usage=$(echo "$line" | awk '{print $3}' | tr -d '%')
    size_raw=$(echo "$line" | awk '{print $4}')

    # --- Sleep Check ---
    check_sleep=$(sudo smartctl -i -n standby "$dev")
    ret_code=$?

    if [ $ret_code -eq 2 ]; then
        # DRIVE IS ASLEEP
        icon="${dim}󰋊${undim}"
        temp_display="${dim}[ 󰒲 SLEEP ]${undim}"
        is_asleep=true
    else
        # DRIVE IS AWAKE
        icon="${white}󰋊${undim}"
        is_asleep=false
        hdd_temp=$(sudo smartctl -A -n standby "$dev" | awk '$1 == 194 || $1 == 190 {print $10; exit}')
        if [ -z "$hdd_temp" ]; then hdd_temp=$(sudo smartctl -A -n standby "$dev" | grep -i "Temp" | head -n1 | awk '{print $10}' | tr -dc '0-9'); fi

        if [ -z "$hdd_temp" ]; then
            temp_display="${dim}[ ??°C ]${undim}"
        else
            if [ "$hdd_temp" -lt 35 ]; then t_color=$green;
            elif [ "$hdd_temp" -lt 41 ]; then t_color=$white;
            elif [ "$hdd_temp" -lt 46 ]; then t_color=$yellow;
            else t_color=$red; fi
            temp_display="[ ${t_color}${hdd_temp}°C${undim} ]"
        fi
    fi

    # Build Usage Bar (Always bright unless we want it dimmed)
    used_width=$(( (usage * bar_width) / 100 ))
    if [ "${usage}" -ge "${max_usage}" ]; then bar_color=$red; else bar_color=$green; fi

    # Optional: If you WANT the bars dimmed for sleeping drives, uncomment the next line:
    # if [ "$is_asleep" = true ]; then bar_color=$dim; fi

    bar="${bar_color}"
    for ((i=0; i<$used_width; i++)); do bar+="▆"; done
    bar+="${undim}${dim}" # This dim is only for the "empty" part of the bar
    for ((i=$used_width; i<$bar_width; i++)); do bar+="▆"; done
    bar+="${undim}"

    hr_size=$(numfmt --to=iec-i --suffix=B $((size_raw * 1024)))

    # Resulting Line with fixed padding
    printf " %b %b %3s%% of %7s %-22s %b\n" "$icon" "$bar" "$usage" "$hr_size" "$mnt" "$temp_display"
done
# Ignore boot-up mounts and only show actual hardware/link issues
errors=$(sudo dmesg | tail -n 100 | grep -iE "exception|Emask|failed|SStatus|link reset|checksum" | grep -v "link up")
