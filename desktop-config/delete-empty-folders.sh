#!/bin/bash

# Directory to start the search (use current directory by default)
TARGET_DIR="${1:-.}"

# Find and list empty directories in the specified directory and subdirectories
echo "Empty directories to be deleted:"
find "$TARGET_DIR" -type d -empty -print

# Confirm before deletion
read -p "Do you want to delete these empty directories? (y/n): " confirmation

if [[ "$confirmation" == "y" || "$confirmation" == "Y" ]]; then
    find "$TARGET_DIR" -type d -empty -exec rmdir {} \;
    echo "All empty directories have been deleted."
else
    echo "No directories were deleted."
fi
