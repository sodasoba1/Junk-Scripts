# Desktop Configuration and Helpers

Configuration and small command-line helpers for an i3-based Linux desktop. The folder includes an i3 configuration, Rofi launcher wrapper, scratchpad shortcuts, headset battery reporting, NordVPN status output and file-cleanup scripts.

## Files

| File | Name | Purpose and functionality |
|---|---|---|
| `i3config` | i3 Window Manager Configuration | Main i3 configuration: defines desktop/window-manager behaviour, key bindings, workspace and application rules, appearance and related commands. Review the file before using it as your own configuration. |
| `i3popup` | i3 Scratchpad Popup Launcher | Accepts `-a`, `-b`, `-c` or `-p` to open scratchpad windows for afetch, bunnyfetch, calendar or battery details via upower. Uses `i3-scratchpad`. |
| `rofi-launcher` | Rofi / dmenu Launcher | Option-driven launcher for a power menu (`-p`), Rofi application/file browser (`-d`), bottom dmenu runner (`-b`), i3 desktop menu (`-m`), calculator (`-c`) and NordVPN menu (`-n`). Loads colour variables from pywal's shell colours. |
| `hs70.sh` | Headset Battery Status | Reads the battery percentage reported by `headsetcontrol -b`; prints the percentage when a battery value is available, otherwise prints nothing. Intended for py3status. |
| `nordvpn-status` | NordVPN Status Indicator | Checks `nordvpn status` and prints a compact checkmark/VPN indicator only when connected. |
| `delete-empty-folders.sh` | Empty Directory Cleanup | Lists empty directories below the supplied path (defaults to the current directory), asks for confirmation, then removes empty directories with `rmdir`. |
| `delete-thumbs.sh` | Windows Thumbnail Cache Cleanup | Finds and deletes files named `Thumbs.db` below the supplied path (defaults to the current directory). No confirmation prompt. |

## Usage

Run executable scripts from this directory, for example:

```bash
./i3popup -a
./rofi-launcher -d
./hs70.sh
./nordvpn-status
./delete-empty-folders.sh /path/to/inspect
./delete-thumbs.sh /path/to/inspect
```

If execute permission is not set, use `bash script-name` or `sh script-name` as appropriate.

## Dependencies and environment

- i3, `i3-scratchpad`, Rofi, dmenu and i3-dmenu-desktop for the relevant launcher functions.
- pywal colour files at `~/.cache/wal/colors.sh`; the Rofi theme is expected at `~/.cache/wal/colors-rofi-dark.rasi`.
- `headsetcontrol` for headset battery status.
- `nordvpn` and the `rofi-nordvpn` helper for VPN status/menu functions.
- `upower` for battery information.
- `afetch`, `kawaiifetch` and `cal` for the matching scratchpad shortcuts.

## Caution

`delete-thumbs.sh` permanently removes every matching `Thumbs.db` file beneath its target. Check the target path before running it. The i3 and Rofi files are environment-specific configuration, not universal drop-in defaults.
