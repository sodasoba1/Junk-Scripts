# Media Management

Automated media-stream audit and remux tools. The normal workflow is one command: scan the library, automatically remux only positively identified safe candidates, then review the reports and flagged files.

## Files

| File | Purpose |
|---|---|
| `media_manager.py` | Runs the complete scan-and-apply workflow. |
| `scan_media.py` | Inspects media and classifies automatic candidates, manual-review files and inspection errors. |
| `audio_cleaner.py` | Remuxes eligible files, validates output, atomically replaces originals and calculates actual space savings. |
| `media.sh` | Counts MKV, MP4 and AVI files. |

## Requirements and safety

- Python 3, FFmpeg (`ffmpeg` and `ffprobe`), Bash and GNU `find`.
- Read access to the media tree; write access to source directories and this script directory.
- Enough free space in `~/remux_buffer` for staging.
- Confirm the intended media volume is mounted at the configured `ROOT_DIRECTORY` (default `/media`) before running. The scripts cannot distinguish an empty mountpoint from the intended mounted volume.
- No backups are created. The validated remux is staged, checked, copied to a temporary file beside the source, and atomically replaced. This protects against partial replacement, not against later data loss.

## Automated workflow

Run from this directory:

```bash
python3 media_manager.py
```

The manager:
1. Runs a fresh scan and invalidates the previous audit.
2. Records per-file stream metadata, file size and nanosecond modification time.
3. Processes only files with a positively identified English audio track where at least one audio or subtitle stream can be removed under the rules below.
4. Leaves files without a positively identified English audio track in the manual-review queue.
5. Continues processing unaffected candidates when individual files fail inspection.
6. Validates each remux and replaces the original only when the output is smaller.
7. Writes `remux_report.txt` and the combined `media_run_report.txt`.

No dry-run approval is required for the automated command. The cleaner's standalone default remains dry-run; the manager explicitly invokes `--apply`.

## Track-selection rules

- All video streams are retained.
- If one or more English audio tracks are tagged, all English audio tracks are retained and non-English audio tracks are removed.
- If no English audio track is positively tagged, the file is not automatically changed; it is flagged for manual review.
- If one or more English subtitle tracks are tagged, all English subtitle tracks are retained and non-English subtitle tracks are removed.
- If no English subtitle track is positively tagged, all subtitle tracks are retained.
- MKV attachments and data streams are retained.
- Metadata and chapters are copied; streams are not re-encoded.
- A file is replaced only if FFprobe validation passes, the source fingerprint is unchanged, and the remuxed output is smaller than the original. Otherwise the original remains untouched.

Language tags include `eng`, `en`, `english` and regional forms beginning `en-`. Missing or ambiguous tags are not assumed to be English.

## Reports and manual review

- `media_audit.csv`: detailed scan data and action classification (`AUTO`, `REVIEW`, or `ERROR`).
- `remux_report.txt`: per-run processing summary, reclaimed bytes, failures and manual-review paths.
- `media_run_report.txt`: combined run report.

The report distinguishes actual reclaimed space from estimates. In automatic apply mode, reclaimed bytes are counted only after a smaller validated output has replaced the original. Files with no size reduction, validation failures, source changes, or processing errors are not counted as reclaimed.

Inspect the `MANUAL REVIEW REQUIRED` and `FAILURES` sections after automation completes. Review scan-error rows in the audit as well. A failed file does not prevent other eligible files from being processed. Generate a fresh audit on every run; `IN_PROGRESS`, `PARTIAL` and `PROCESSED` audits are not reusable.

## Individual commands

Scan only:

```bash
python3 scan_media.py
```

Dry-run the cleaner against the current audit (no source replacement):

```bash
python3 audio_cleaner.py
```

Apply the current audit:

```bash
python3 audio_cleaner.py --apply
```

Count common media types:

```bash
./media.sh
MEDIA_ROOT=/path/to/media ./media.sh
```

## Configuration

- Set `ROOT_DIRECTORY` in `scan_media.py` to the intended library root.
- Set `SSD_BUFFER` in `audio_cleaner.py` to the staging directory.
- Set `FFPROBE_TIMEOUT` in the Python scripts to change the per-file FFprobe timeout.

## Limitations

Output validation confirms FFprobe can read the output and that expected stream counts match; it is not a full decode or playback test. File fingerprints use size and modification time rather than cryptographic hashes. Non-MKV container-specific stream types other than video/audio/subtitle are not explicitly mapped. The workflow is manually launchable; no recurring scheduler is installed by these scripts.
