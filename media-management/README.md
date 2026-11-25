# Media Management

Automated media-stream audit and remux tools. The normal workflow is one command: scan the library, automatically remux only positively identified safe candidates, then review the reports and flagged files.

## Files

| File | Purpose |
|---|---|
| `media_manager.py` | Runs the complete scan-and-apply workflow. |
| `scan_media.py` | Inspects media and classifies automatic candidates, manual-review files and inspection errors. |
| `audio_cleaner.py` | Remuxes eligible files, verifies encoded video packet SHA-256 hashes, validates output, atomically replaces originals and calculates actual space savings. |
| `setup_wsl_smb.sh` | Interactively discovers or accepts an SMB server, lists shares and mounts the selected share for WSL2. |
| `media.sh` | Counts MKV, MP4 and AVI files. |

## Requirements and safety

- Python 3 and FFmpeg (`ffmpeg` and `ffprobe`).
- Read access to the media tree; write/delete/rename access in each source directory and write access to this script directory.
- Enough free space in the local SSD staging directory.
- On Windows, set `MEDIA_ROOT` to a mapped drive or UNC path before running. On Linux, the default media root remains `/media`.
- In WSL2, the manager verifies that `MEDIA_ROOT` is inside a mounted CIFS/SMB share and checks write/delete access before scanning. It refuses to run against an unmounted local mountpoint.
- A run lock prevents two manager instances from scanning/replacing files concurrently.
- No backups are created. The validated remux is staged, checked, copied to a temporary file beside the source, and atomically replaced. This protects against partial replacement, not against later data loss.

## Automated workflow

Run from this directory.

**Windows PowerShell — mapped drive:**

```powershell
$env:MEDIA_ROOT = 'Z:\Media'
$env:MEDIA_BUFFER = 'D:\RemuxBuffer'
py .\media_manager.py
```

**Windows PowerShell — UNC path:**

```powershell
$env:MEDIA_ROOT = '\\SERVER\Media'
$env:MEDIA_BUFFER = 'D:\RemuxBuffer'
py .\media_manager.py
```

**Linux:**

```bash
MEDIA_ROOT=/media MEDIA_BUFFER=/path/to/local-ssd/remux_buffer python3 media_manager.py
```

`MEDIA_ROOT` accepts either a mapped drive or UNC path on Windows. `MEDIA_BUFFER` should point to a local SSD directory, not the network share.

**Network-I/O policy:** media content is read from the share once per candidate to create the local working copy. All subsequent probing, hashing and remuxing use that local copy and its local output. Apply mode necessarily writes the result to a temporary file beside the original, then reads that staged network copy once for end-to-end verification before atomic replacement. No full-file hash pass is performed against the original network file.

The manager:
1. Runs a fresh scan and invalidates the previous audit.
2. Records per-file stream metadata, file size and nanosecond modification time.
3. Processes only files with a positively identified English audio track where at least one audio or subtitle stream can be removed under the rules below.
4. Leaves files without a positively identified English audio track in the manual-review queue.
5. Continues processing unaffected candidates when individual files fail inspection.
6. Copies each candidate from the network share to the local SSD once. FFprobe inspection, source hashing, remuxing and output hashing then run against local files. The local source and remux video packet SHA-256 hashes must match. For apply runs, the remux is copied back to a temporary sibling on the share and that staged copy is probed and hashed against the already-validated local remux before the original is replaced.
7. Writes `remux_report.txt` and the combined `media_run_report.txt`.

No dry-run approval is required for the automated command. The cleaner's standalone default remains dry-run; the manager explicitly invokes `--apply`.

**WSL2 Ubuntu — direct SMB mount (recommended for a Windows PC using WSL2):**

Install the mount and discovery tools:

```bash
sudo apt update
sudo apt install -y cifs-utils smbclient
```

Run the interactive SMB setup:

```bash
chmod +x ./setup_wsl_smb.sh
./setup_wsl_smb.sh
```

The setup offers both manual server IP/hostname entry and a browseable-network discovery attempt. Discovery depends on SMB browsing and WSL networking; manual entry is the reliable fallback. It then lists shares, prompts for the share name and credentials, and mounts the selected share at `/mnt/media`.

The SMB credentials are stored separately from the scripts in `/etc/samba/credentials-media-management`, owned by root and restricted to mode `600`. This is a plaintext credentials file protected by Linux permissions; anyone with root access to the WSL distribution can read it. The script does not configure an automatic/persistent mount.

Run the manager after checking the mounted path. If the library is in a subfolder of the share, set `MEDIA_ROOT` to that subfolder:

```bash
MEDIA_ROOT=/mnt/media MEDIA_BUFFER=~/remux_buffer python3 media_manager.py
```

Keep `MEDIA_BUFFER` inside WSL's Linux filesystem (for example, `~/remux_buffer`), not on the SMB mount or under `/mnt/c`.

## Track-selection rules

- All video streams are retained.
- If one or more English audio tracks are tagged, all English audio tracks are retained and non-English audio tracks are removed.
- If no English audio track is positively tagged, the file is not automatically changed; it is flagged for manual review.
- If one or more English subtitle tracks are tagged, all English subtitle tracks are retained and non-English subtitle tracks are removed.
- If no English subtitle track is positively tagged, all subtitle tracks are retained.
- MKV attachments and data streams are retained.
- Metadata and chapters are copied; streams are not re-encoded.
- A file is replaced only if FFprobe validation passes, every retained video stream's encoded packet SHA-256 matches the staged source, the source fingerprint is unchanged, the network-side replacement copy passes the same checks, and the remuxed output is smaller than the original. Otherwise the original remains untouched.

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

- Set `MEDIA_ROOT` to the intended library root. On Windows, this is mandatory and may be a mapped drive (for example `Z:\Media`) or UNC path (for example `\\SERVER\Media`). On Linux, it defaults to `/media`.
- Set `MEDIA_BUFFER` to the local SSD staging directory. It defaults to `~/remux_buffer`.
- Set `FFPROBE_TIMEOUT` in the Python scripts to change the per-file FFprobe timeout.

## Limitations

Output validation confirms FFprobe can read the output and that expected stream counts match. The SHA-256 comparison verifies the encoded video packet payloads are unchanged by remuxing; it does not prove that the video decodes correctly or that the source was not already corrupt. It is not a full decode or playback test. The completed temporary copy on the share is probed before replacement; after the same-directory replacement, the final path and file size are checked before counting reclaimed space. The source-change fingerprint uses size and modification time; video packet SHA-256 is used separately to prove the video payload survives the remux unchanged. Windows/SMB replacement can fail when another process has the file open or the share denies delete/rename access; in that case the original is left in place. On SMB, the replacement may inherit the containing directory/share ACL rather than preserving an explicit per-file ACL. Test this against a representative folder before running across the full library. Non-MKV container-specific stream types other than video/audio/subtitle are not explicitly mapped. The workflow is manually launchable; no recurring scheduler is installed by these scripts.
