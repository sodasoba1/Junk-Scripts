#!/usr/bin/env python3
"""Build a reliable, atomic media stream audit for audio_cleaner.py."""

import csv
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

# ---------------- CONFIG ----------------
ROOT_DIRECTORY = "/media"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(SCRIPT_DIR, "media_audit.csv")
VIDEO_EXTENSIONS = (".mkv", ".mp4", ".avi", ".mov", ".m4v")
FFPROBE_TIMEOUT = 90
# ----------------------------------------

FIELDNAMES = [
    "Filename", "Location", "File_Size", "File_Mtime_NS",
    "Inspection_Status", "Stream_Index", "Stream_Type", "Language",
    "Codec", "Title", "Disposition_Default",
]


def invalidate_previous_audit():
    """Prevent an older successful audit being applied after a failed new scan."""
    if not os.path.isfile(CSV_PATH):
        return
    fd, temporary_path = tempfile.mkstemp(
        prefix=".media_audit_stale.", dir=SCRIPT_DIR, text=True
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output, open(CSV_PATH, encoding="utf-8") as source:
            for line in source:
                if line.startswith("# MEDIA_AUDIT_STATE="):
                    output.write("# MEDIA_AUDIT_STATE=STALE\\n")
                else:
                    output.write(line)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary_path, CSV_PATH)
    except Exception:
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
        raise


def is_english(language):
    value = (language or "").strip().lower().replace("_", "-")
    return value in ("eng", "en", "english") or value.startswith("en-")


def ffprobe_streams(path):
    """Return stream metadata or raise a useful error; never disguise failures."""
    command = [
        "ffprobe", "-v", "error", "-print_format", "json",
        "-show_streams", path,
    ]
    try:
        result = subprocess.run(
            command, check=False, capture_output=True, text=True,
            timeout=FFPROBE_TIMEOUT,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"ffprobe timed out after {FFPROBE_TIMEOUT}s") from exc
    except OSError as exc:
        raise RuntimeError(f"could not run ffprobe: {exc}") from exc

    if result.returncode:
        raise RuntimeError((result.stderr or "unknown ffprobe error").strip()[-600:])
    try:
        return json.loads(result.stdout).get("streams", [])
    except (json.JSONDecodeError, AttributeError) as exc:
        raise RuntimeError(f"invalid ffprobe JSON: {exc}") from exc


def error_row(path, message):
    return {
        "Filename": os.path.basename(path),
        "Location": os.path.dirname(path),
        "File_Size": "",
        "File_Mtime_NS": "",
        "Inspection_Status": "ERROR",
        "Stream_Index": "",
        "Stream_Type": "ERROR",
        "Language": "",
        "Codec": "",
        "Title": message,
        "Disposition_Default": "",
    }


def scan():
    try:
        invalidate_previous_audit()
    except OSError as exc:
        print(f"ERROR: could not invalidate the previous audit: {exc}", file=sys.stderr)
        return 1

    if shutil.which("ffprobe") is None:
        print("ERROR: ffprobe not found. Install FFmpeg first.", file=sys.stderr)
        return 1
    if not os.path.isdir(ROOT_DIRECTORY):
        print(f"ERROR: media root does not exist or is not a directory: {ROOT_DIRECTORY}", file=sys.stderr)
        return 1

    generated_at = datetime.now(timezone.utc).isoformat()
    scanned = flagged = failed = 0
    rows = []
    traversal_errors = []

    def on_walk_error(exc):
        traversal_errors.append(str(exc))

    for root, _, filenames in os.walk(ROOT_DIRECTORY, onerror=on_walk_error):
        for name in filenames:
            if not name.lower().endswith(VIDEO_EXTENSIONS):
                continue

            scanned += 1
            full_path = os.path.join(root, name)
            try:
                if os.path.islink(full_path):
                    raise RuntimeError("symbolic-link media files are not eligible for remuxing")
                before = os.stat(full_path)
                streams = ffprobe_streams(full_path)
                after = os.stat(full_path)
                if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                    raise RuntimeError("file changed while it was being scanned")
            except (OSError, RuntimeError) as exc:
                failed += 1
                rows.append(error_row(full_path, str(exc)))
                print(f"ERROR: {full_path}: {exc}", file=sys.stderr)
                continue

            audio = [stream for stream in streams if stream.get("codec_type") == "audio"]
            subtitles = [stream for stream in streams if stream.get("codec_type") == "subtitle"]
            if not audio:
                continue

            languages = [
                str(stream.get("tags", {}).get("language", "und")).strip().lower()
                for stream in audio
            ]
            # Keep the original policy: one English audio track is already clean.
            if len(audio) == 1 and is_english(languages[0]):
                continue

            flagged += 1
            for stream in audio + subtitles:
                rows.append({
                    "Filename": name,
                    "Location": root,
                    "File_Size": after.st_size,
                    "File_Mtime_NS": after.st_mtime_ns,
                    "Inspection_Status": "OK",
                    "Stream_Index": stream.get("index", ""),
                    "Stream_Type": stream.get("codec_type", ""),
                    "Language": str(stream.get("tags", {}).get("language", "und")).upper(),
                    "Codec": stream.get("codec_name", "unknown"),
                    "Title": stream.get("tags", {}).get("title", ""),
                    "Disposition_Default": stream.get("disposition", {}).get("default", 0),
                })

            if scanned % 50 == 0:
                print(f"Scanned: {scanned} | Flagged: {flagged} | Inspection errors: {failed}", end="\r")

    if traversal_errors:
        failed += len(traversal_errors)
        for message in traversal_errors:
            print(f"ERROR: directory traversal: {message}", file=sys.stderr)

    # Publish only a complete CSV; an interrupted scan leaves the previous audit intact.
    fd, temporary_path = tempfile.mkstemp(
        prefix=".media_audit.", suffix=".csv", dir=SCRIPT_DIR, text=True
    )
    try:
        with os.fdopen(fd, "w", newline="", encoding="utf-8") as handle:
            handle.write("# MEDIA_AUDIT_VERSION=2\n")
            handle.write("# MEDIA_AUDIT_STATE=UNPROCESSED\n")
            handle.write(f"# SCAN_ERRORS={failed}\n")
            handle.write(f"# GENERATED_AT={generated_at}\n")
            handle.write("# GENERATED_BY=scan_media.py\n")
            writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
            writer.writeheader()
            writer.writerows(rows)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, CSV_PATH)
    except Exception:
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
        raise

    print("\nScan complete.")
    print(f"Media files inspected: {scanned}")
    print(f"Files flagged for remux review: {flagged}")
    print(f"Inspection/traversal errors: {failed}")
    print(f"Audit written to: {CSV_PATH}")
    if failed:
        print("WARNING: resolve inspection errors before running the remux cleaner.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(scan())
