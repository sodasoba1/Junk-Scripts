#!/bin/bash

# Color codes
GREEN='\033[0;32m' # Green color
NC='\033[0m'       # No color

# Function to count files with a specific extension
count_files() {
    local extension="$1"
    find /media -type f -name "*.$extension" | wc -l
}

# Count total number of MKV files
echo "Counting MKV files..."
mkv_count=$(count_files mkv)
echo -e "MKV files found: ${GREEN}$mkv_count${NC}"

# Count total number of MP4 files
echo "Counting MP4 files..."
mp4_count=$(count_files mp4)
echo -e "MP4 files found: ${GREEN}$mp4_count${NC}"

# Count total number of AVI files
echo "Counting AVI files..."
avi_count=$(count_files avi)
echo -e "AVI files found: ${GREEN}$avi_count${NC}"

# Calculate the total count
total_count=$((mkv_count + mp4_count + avi_count))

# Display the results
echo -e "Total number of MKV files: ${GREEN}$mkv_count${NC}"
echo -e "Total number of MP4 files: ${GREEN}$mp4_count${NC}"
echo -e "Total number of AVI files: ${GREEN}$avi_count${NC}"
echo -e "Total number of all media files: ${GREEN}$total_count${NC}"
