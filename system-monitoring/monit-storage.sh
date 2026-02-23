#!/bin/bash

# Get physical drives
mapfile -t dfs < <(df -h | grep -E '^/dev/sd|^/dev/nvme' | grep -v 'efi')

echo "Storage Report:"
for line in "${dfs[@]}"; do
    dev=$(echo "$line" | awk '{print $1}')
    short_dev=$(echo "$dev" | sed 's|/dev/||')
    mnt=$(echo "$line" | awk '{print $6}' | sed 's|/media/||')
    usage=$(echo "$line" | awk '{print $5}')

    if [ "$mnt" == "/" ]; then
        state="⚡"
    else
        # 1. Check for real-time activity in diskstats
        # This looks at the 10th column (milliseconds spent doing I/O)
        io_start=$(awk -v d="$short_dev" '$3==d {print $13}' /proc/diskstats)
        sleep 0.1 # Very brief pause to see if it changes
        io_end=$(awk -v d="$short_dev" '$3==d {print $13}' /proc/diskstats)

        if [ "$io_start" -ne "$io_end" ]; then
            state="⚡" # It's moving data RIGHT NOW
        else
            # 2. If no immediate activity, check power state silently
            smartctl -i -n standby "$dev" > /dev/null
            if [ $? -eq 2 ]; then
                state="🌙"
            else
                state="⚡"
            fi
        fi
    fi

    printf "%-15s %-5s %s\n" "$mnt" "$usage" "$state"
done
