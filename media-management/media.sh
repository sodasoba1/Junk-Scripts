#!/usr/bin/env bash
set -uo pipefail

ROOT_DIRECTORY="${MEDIA_ROOT:-/media}"
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

if [[ ! -d "$ROOT_DIRECTORY" ]]; then
    printf 'ERROR: media directory does not exist: %s\n' "$ROOT_DIRECTORY" >&2
    exit 1
fi

if [[ ! -r "$ROOT_DIRECTORY" || ! -x "$ROOT_DIRECTORY" ]]; then
    printf 'ERROR: media directory is not readable/searchable: %s\n' "$ROOT_DIRECTORY" >&2
    exit 1
fi

count_files() {
    local pattern="$1"
    local result
    if ! result=$(find "$ROOT_DIRECTORY" -type f -iname "$pattern" -printf '.' 2>/dev/null | wc -c); then
        return 1
    fi
    printf '%s' "$result"
}

printf 'Counting media files under %s...\n' "$ROOT_DIRECTORY"

if ! mkv_count=$(count_files '*.mkv') ||
   ! mp4_count=$(count_files '*.mp4') ||
   ! avi_count=$(count_files '*.avi'); then
    printf 'ERROR: one or more counts failed; results may be incomplete.\n' >&2
    exit 1
fi

total_count=$((mkv_count + mp4_count + avi_count))

if [[ -t 1 ]]; then
    printf 'MKV files: %b%s%b\n' "$GREEN" "$mkv_count" "$NC"
    printf 'MP4 files: %b%s%b\n' "$GREEN" "$mp4_count" "$NC"
    printf 'AVI files: %b%s%b\n' "$GREEN" "$avi_count" "$NC"
    printf 'Total media files: %b%s%b\n' "$GREEN" "$total_count" "$NC"
else
    printf 'MKV files: %s\nMP4 files: %s\nAVI files: %s\nTotal media files: %s\n' \
        "$mkv_count" "$mp4_count" "$avi_count" "$total_count"
fi
