#!/bin/bash
# config
max_usage=90
bar_width=20
# colors
white="\e[39m"
green="\e[92m"
red="\e[91m"
dim="\e[38;5;233m"
undim="\e[0m"
grey="\e[8m"

# disk usage: ignore zfs, squashfs & tmpfs
mapfile -t dfs < <(df -H -x zfs -x squashfs -x tmpfs -x devtmpfs -x overlay --output=target,pcent,size | tail -n+2)
printf="\n"

for line in "${dfs[@]}"; do
    # get disk usage
    usage=$(echo "$line" | awk '{print $2}' | sed 's/%/ /')
    used_width=$((($usage*$bar_width)/100))
    # color is green if usage < max_usage, else red
    if [ "${usage}" -ge "${max_usage}" ]; then
        color=$red
    else
        color=$green
    fi
    # print green/red bar until used_width
    bar="${color}"
    for ((i=0; i<$used_width; i++)); do
        bar+="▆"
    done
    # print dimmmed bar until end
    bar+="${white}${dim}"
    for ((i=$used_width; i<$bar_width; i++)); do
        bar+="▆"
    done
    bar+="${undim}"
    # print usage line & bar
    echo -en "󰋊 ${bar}" | sed -e 's/^/ /'
    echo "${line}" | awk '{ printf("%20-s%+1s used out of %+4s\n", $1, $2, $3); }' | sed -e 's/^/ /'
done

# Get total and used disk space for all mounted partitions
total_space=$(df -h --total | grep total | awk '{print $2}')
used_space=$(df -h --total | grep total | awk '{print $3}')

# Calculate the percentage of used space
percentage_used=$(echo "scale=0; ($used_space * 100) / $total_space" | bc)

# Display total used disk space in percentage
printf="\n"
echo ""
printf " 󰒍   Total Server disk space used:   $red $used_space$white |$red $percentage_used%%$white used out of$green $total_space$white\n"
