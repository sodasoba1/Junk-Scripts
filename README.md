# Junk Scripts

A collection of Bash and Python utilities, Linux desktop configuration, server monitoring tools, media-management scripts, and Raspberry Pi / Pi-hole support files.

This repository is a practical toolbox rather than a single installable application. Each folder is independent; read its README before running or installing anything.

## Directory guide

| Folder / file | Purpose |
|---|---|
| [desktop-config/](desktop-config/README.md) | i3, Rofi, scratchpad, VPN-status and desktop housekeeping helpers |
| [media-management/](media-management/README.md) | Scan media streams, audit audio/subtitles, remux selected tracks and count media files |
| [security-admin/](security-admin/README.md) | Authentication-log threat summary and local account / network connection inspection |
| [system-monitoring/](system-monitoring/README.md) | Linux system, CPU, memory, disk, SMART and ZRAM reporting |
| [RPi3-ubuntu-TXRX/](RPi3-ubuntu-TXRX/README.md) | Raspberry Pi network traffic and packet-drop LED indicator, with systemd service |
| [unbound-piholedash/](unbound-piholedash/README.md) | Flask dashboard for Unbound, Pi-hole and host metrics, plus optional SH1106 OLED output |
| [Junk-Scripts/utilities/](Junk-Scripts/utilities/README.md) | Utility folder (currently no executable utility scripts are present) |
| [Fuzz.sh](Fuzz.sh) | HTTP endpoint/path and request-handling behaviour tester |
| [png-to-opening-bnr.py](png-to-opening-bnr.py) | Convert a PNG into a GameCube `opening.bnr` banner |

## Standalone root scripts

### `Fuzz.sh` — HTTP Request / Path Behaviour Tester

Accepts a base URL and target path, sends a baseline GET request, then tests URL/path variants, common proxy/rewrite headers, HTTP methods and POST bodies. It prints each response's HTTP status, downloaded byte count and elapsed time, highlighting differences from the baseline status/size. Requires `curl`.

Example (only against an endpoint you own or are authorised to test):

```bash
./Fuzz.sh https://example.com admin
```

This is a lightweight behaviour/fuzzing aid, not a complete vulnerability scanner. Its requests can reach application endpoints and may trigger side effects.

### `png-to-opening-bnr.py` — GameCube Banner Creator

Interactively asks for a PNG image, game title, developer, description and region. Resizes the image to 96×32, converts pixels into the GameCube tiled RGB5A3 texture representation, writes BNR1 (NTSC-U/J) or BNR2 (PAL) metadata and creates an `opening.bnr` file with the expected region-specific size. Requires Python 3 and Pillow.

Run it from the directory containing the source PNG:

```bash
python3 png-to-opening-bnr.py
```

## General requirements

Requirements vary by script. Common dependencies include Bash, Python 3, standard Linux command-line tools, `smartmontools`, `ffmpeg`/`ffprobe`, Flask, psutil, requests, and Pillow. The relevant folder README lists dependencies and usage for each tool.

## Safety and operating notes

- Inspect scripts and edit their configuration for your own system before running them.
- Some monitoring tools use `sudo` to query SMART data or system logs.
- `media-management/audio_cleaner.py` replaces source media files after a successful FFmpeg remux. Keep a backup until you have verified the output.
- `desktop-config/delete-thumbs.sh` deletes matching files; `delete-empty-folders.sh` asks for confirmation before removing empty directories.
- `Fuzz.sh` sends multiple HTTP requests, including POST and unusual methods/headers. Only run it against systems you own or are explicitly authorised to test.
- The Pi-hole dashboard needs a valid API URL/token and suitable local permissions. Do not commit real API credentials.

## Documentation

Each maintained folder has its own README describing the scripts/configuration, purpose, behaviour, dependencies and usage. Documentation is based on the current repository contents; where a script has no configurable CLI or usage text, the README says so rather than inventing options.
