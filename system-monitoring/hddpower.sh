#!/bin/bash

# This script automatically discovers hard drives on the system and reports their
# "Device Model", "User Capacity", "Power On Hours" (converted to days and years)
# in a tab-separated format, suitable for piping to 'column -t'.
# how to use this script
# sudo ./hddpower.sh | column -t -s $'\t'

# Ensure 'bc' is installed for floating-point calculations
if ! command -v bc &> /dev/null
then
    echo "Error: 'bc' command not found. Please install it (e.g., sudo apt install bc)."
    exit 1
fi

# Automatically discover disk devices (HDDs/SSDs).
# 'lsblk -dno KNAME,TYPE' lists block devices, their names (KNAME), and types (TYPE).
# 'awk '$2=="disk"{print "/dev/"$1}'' filters for lines where the type is "disk" and prints the name.
DEVICES=$(lsblk -dno KNAME,TYPE | awk '$2=="disk"{print "/dev/"$1}')

# Print header row
# Added '--' to explicitly tell printf to treat the next argument as the format string.
printf -- "Device\tModel\tCapacity\tPower_On_Hours\tDays_On\tYears_On\n"
printf -- "------\t-----\t--------\t--------------\t-------\t--------\n"

# Loop through each discovered device
for DEVICE in $DEVICES; do
    DEVICE_NAME=$(basename "$DEVICE")
    DEVICE_MODEL="N/A"
    USER_CAPACITY="N/A"
    POWER_ON_HOURS_RAW="N/A"
    POWER_ON_DAYS="N/A"
    POWER_ON_YEARS="N/A"

    # Check if the device exists and is a block device
    if [ -b "$DEVICE" ]; then
        # Retrieve Device Model
        MODEL_OUTPUT=$(sudo smartctl --info "$DEVICE" 2>/dev/null | grep -E "Device Model:" | awk '{$1=$2=""; print $0}' | xargs)
        if [[ -n "$MODEL_OUTPUT" ]]; then
            DEVICE_MODEL="$MODEL_OUTPUT"
        fi

        # Retrieve User Capacity
        CAPACITY_OUTPUT=$(sudo smartctl --info "$DEVICE" 2>/dev/null | grep -E "User Capacity:" | awk '{$1=$2=""; print $0}' | xargs)
        if [[ -n "$CAPACITY_OUTPUT" ]]; then
            USER_CAPACITY="$CAPACITY_OUTPUT"
        fi

        # Retrieve Power On Hours and perform calculations
        # First, get the full output of the 10th field (RAW_VALUE)
        HOURS_OUTPUT_FULL=$(sudo smartctl --attributes "$DEVICE" 2>/dev/null | grep -E "Power_On_Hours" | awk '{print $10}')

        # Now, extract only the numeric part for calculation.
        # This handles cases like "97h+05m+42.522s" by extracting "97",
        # or a simple number like "12345" by extracting "12345".
        if [[ "$HOURS_OUTPUT_FULL" =~ ^([0-9]+)h ]]; then
            POWER_ON_HOURS_RAW="${BASH_REMATCH[1]}"
        elif [[ "$HOURS_OUTPUT_FULL" =~ ^([0-9]+)$ ]]; then
            POWER_ON_HOURS_RAW="${BASH_REMATCH[1]}"
        else
            POWER_ON_HOURS_RAW="" # Set to empty if no valid number format found
        fi

        # Perform calculations only if a valid numeric hours value was extracted
        if [[ -n "$POWER_ON_HOURS_RAW" ]]; then
            POWER_ON_DAYS=$(echo "scale=2; $POWER_ON_HOURS_RAW / 24" | bc -l)
            POWER_ON_YEARS=$(echo "scale=2; $POWER_ON_HOURS_RAW / (24 * 365.25)" | bc -l)
        fi
    fi

    # Print data for the current device, tab-separated
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$DEVICE_NAME" \
        "$DEVICE_MODEL" \
        "$USER_CAPACITY" \
        "$POWER_ON_HOURS_RAW" \
        "$POWER_ON_DAYS" \
        "$POWER_ON_YEARS"
done
