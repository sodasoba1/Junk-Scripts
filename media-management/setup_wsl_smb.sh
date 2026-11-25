#!/usr/bin/env bash
# Discover or manually select an SMB server/share and mount it for media-management.
set -Eeuo pipefail

MOUNT_POINT="${MEDIA_MOUNT_POINT:-/mnt/media}"
CREDENTIALS_FILE="/etc/samba/credentials-media-management"

fail() { printf 'ERROR: %s\\n' "$*" >&2; exit 1; }

if [[ "${WSL_DISTRO_NAME:-}" == "" && ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
    printf 'WARNING: this does not appear to be a WSL environment. Continuing anyway.\\n' >&2
fi

for cmd in sudo mount.cifs smbclient smbtree; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing '$cmd'. Install dependencies with: sudo apt update && sudo apt install -y cifs-utils smbclient"
done

if mountpoint -q "$MOUNT_POINT"; then
    printf 'Already mounted at %s\\n' "$MOUNT_POINT"
    exit 0
fi

mkdir -p "$MOUNT_POINT"

printf '\\nSMB media-share setup\\n'
printf '1) Enter server IP/hostname manually\\n'
printf '2) Search for SMB servers on the network (may be limited by WSL networking)\\n'
read -r -p 'Choose [1/2]: ' choice
case "$choice" in
    1)
        read -r -p 'SMB server IP or hostname: ' SERVER
        [[ -n "$SERVER" ]] || fail 'No server was entered.'
        ;;
    2)
        printf '\\nSearching for browseable SMB servers...\\n'
        DISCOVERY_OUTPUT="$(smbtree -N 2>&1 || true)"
        if [[ -n "$DISCOVERY_OUTPUT" ]]; then
            printf '%s\\n' "$DISCOVERY_OUTPUT"
        else
            printf 'No browseable servers were returned. This is common when network browsing is blocked.\\n'
        fi
        printf '\\nEnter the server IP/hostname shown above, or enter it manually.\\n'
        read -r -p 'SMB server IP or hostname: ' SERVER
        [[ -n "$SERVER" ]] || fail 'No server was entered.'
        ;;
    *) fail 'Choose 1 or 2.' ;;
esac

read -r -p 'SMB username: ' SMB_USERNAME
[[ -n "$SMB_USERNAME" ]] || fail 'No username was entered.'
read -r -s -p 'SMB password: ' SMB_PASSWORD
printf '\\n'

# Keep credentials out of command-line arguments and shell history.
sudo install -d -m 700 /etc/samba
printf 'username=%s\\npassword=%s\\n' "$SMB_USERNAME" "$SMB_PASSWORD" | sudo sh -c 'umask 077; cat > "$1"' sh "$CREDENTIALS_FILE"
unset SMB_PASSWORD
sudo chmod 600 "$CREDENTIALS_FILE"

printf '\\nAvailable shares on %s:\\n' "$SERVER"
if ! smbclient -A "$CREDENTIALS_FILE" -L "//$SERVER"; then
    fail 'Could not list SMB shares. Check the server, credentials and network access.'
fi

read -r -p 'Share name (not a folder within the share): ' SHARE
[[ -n "$SHARE" && "$SHARE" != */* ]] || fail 'Enter a valid share name without slashes.'

printf '\\nMounting //%s/%s at %s ...\\n' "$SERVER" "$SHARE" "$MOUNT_POINT"
if ! sudo mount -t cifs "//$SERVER/$SHARE" "$MOUNT_POINT" \\
    -o "credentials=$CREDENTIALS_FILE,uid=$(id -u),gid=$(id -g),file_mode=0664,dir_mode=0775,iocharset=utf8"; then
    fail 'SMB mount failed. The credentials file remains protected at /etc/samba/credentials-media-management.'
fi

if ! mountpoint -q "$MOUNT_POINT"; then
    fail 'Mount command returned but the mountpoint is not active.'
fi

printf '\\nMounted successfully: //%s/%s -> %s\\n' "$SERVER" "$SHARE" "$MOUNT_POINT"
printf 'Check the media directory, then set MEDIA_ROOT if the library is inside a subfolder.\\n'
printf 'Example: MEDIA_ROOT=%s MEDIA_BUFFER=~/remux_buffer python3 media_manager.py\\n' "$MOUNT_POINT"
printf '\\nThe SMB password is stored in %s with root-only permissions (mode 600).\\n' "$CREDENTIALS_FILE"
