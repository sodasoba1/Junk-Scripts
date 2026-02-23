#!/bin/bash

# Directory to start the search (use current directory by default)
TARGET_DIR="${1:-.}"

# Find and delete all Thumbs.db files in the specified directory and subdirectories
find "$TARGET_DIR" -type f -name "Thumbs.db" -exec rm -f {} \;

echo "All Thumbs.db files have been deleted from $TARGET_DIR and its subfolders."
