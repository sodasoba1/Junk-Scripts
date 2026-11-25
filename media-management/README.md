# Media Management

Scripts for inventorying media files, inspecting audio/subtitle streams, remuxing selected tracks and counting common video formats.

## Files

| File | Name | Purpose and functionality |
|---|---|---|
| `scan_media.py` | Media Stream Auditor | Recursively scans `/media` for MKV, MP4, AVI, MOV and M4V files. Uses ffprobe to inspect streams and writes `media_audit.csv` beside the script. Files with exactly one English audio stream are skipped; other files with audio are flagged and their audio/subtitle stream metadata is recorded. The CSV is marked `UNPROCESSED` for the remux stage. |
| `audio_cleaner.py` | Audio / Subtitle Remux Cleaner | Reads the audit CSV, chooses English audio/subtitle streams when present (otherwise retains the available streams), and uses FFmpeg stream-copy remuxing to create a cleaner stream layout. It stages files in `~/remux_buffer`, replaces the original only when FFmpeg succeeds, updates the CSV processing state and writes `remux_report.txt`. |
| `media.sh` | Media File Counter | Counts `.mkv`, `.mp4` and `.avi` files recursively under `/media`, then prints per-format and combined totals. |

## Typical workflow

1. Ensure the media is mounted at `/media`.
2. Install FFmpeg (which provides both `ffprobe` and `ffmpeg`).
3. Run the scanner to generate the audit CSV:

   ```bash
   python3 scan_media.py
   ```

4. Review `media_audit.csv` before remuxing. The cleaner expects this generated file and its state header.
5. Run the remux cleaner:

   ```bash
   python3 audio_cleaner.py
   ```

6. Count common video files, when needed:

   ```bash
   ./media.sh
   ```

## Requirements

- Python 3.
- FFmpeg / ffprobe.
- Read/write access to the media files and the script directory.
- Enough free space in `~/remux_buffer` for a staged copy of the file being remuxed.
- Bash for `media.sh`.

## Important behaviour and cautions

- The scanner's media root is currently hard-coded as `/media`; edit `ROOT_DIRECTORY` in `scan_media.py` to change it.
- The CSV is generated beside the scripts as `media_audit.csv`. The cleaner will stop if it is missing, marked `IN_PROGRESS`, or already marked `PROCESSED`.
- The cleaner currently has `DRY_RUN = False`. It copies each source to the buffer, remuxes using stream copy, and removes/replaces the original after a successful FFmpeg exit. Keep an independent backup and inspect the CSV before running it against valuable media.
- The scan skips files with no audio and files that contain exactly one English audio stream. It records audio and subtitle streams for flagged files.
- `media.sh` counts only MKV, MP4 and AVI; the scanner supports additional extensions.
