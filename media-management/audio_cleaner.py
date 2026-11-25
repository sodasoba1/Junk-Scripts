#!/usr/bin/env python3
"""Safely remux selected audio/subtitle tracks from a scanner-generated audit."""

import argparse
import csv
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from collections import defaultdict

# ---------------- CONFIG ----------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(SCRIPT_DIR, "media_audit.csv")
REPORT_PATH = os.path.join(SCRIPT_DIR, "remux_report.txt")
SSD_BUFFER = os.path.expanduser("~/remux_buffer")
MIN_FREE_SPACE_MARGIN = 64 * 1024 * 1024
FFPROBE_TIMEOUT = 90
# ----------------------------------------

RESET = "\033[0m"
ITALIC = "\033[3m"
PURPLE = "\033[38;5;141m"
ORANGE = "\033[38;5;208m"
CYAN = "\033[38;5;81m"
GREEN = "\033[38;5;82m"
FG = "\033[38;5;252m"
USE_COLOUR = sys.stdout.isatty()


def colour(code):
    return code if USE_COLOUR else ""


def progress_color(percent):
    if percent < 25:
        return PURPLE
    if percent < 50:
        return ORANGE
    if percent < 75:
        return CYAN
    return GREEN


def read_audit(path):
    if not os.path.isfile(path):
        raise RuntimeError(f"audit CSV not found: {path}")

    with open(path, encoding="utf-8") as handle:
        metadata = {}
        for line in handle:
            if not line.startswith("#"):
                break
            if "=" in line:
                key, value = line[2:].strip().split("=", 1)
                metadata[key] = value

    if metadata.get("MEDIA_AUDIT_VERSION") != "2":
        raise RuntimeError("unsupported or old audit format; run scan_media.py again")
    state = metadata.get("MEDIA_AUDIT_STATE")
    if state != "UNPROCESSED":
        raise RuntimeError(
            f"audit state is {state or 'missing'}; only UNPROCESSED audits can run. "
            "Review the report and generate a fresh scan."
        )
    try:
        scan_errors = int(metadata.get("SCAN_ERRORS", "-1"))
    except ValueError:
        scan_errors = -1
    if scan_errors != 0:
        raise RuntimeError(
            f"audit reports {scan_errors if scan_errors >= 0 else 'unknown'} scan error(s); "
            "fix the scan problem and run scan_media.py again"
        )

    with open(path, newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(line for line in handle if not line.startswith("#"))
        required = {
            "Filename", "Location", "File_Size", "File_Mtime_NS",
            "Inspection_Status", "Stream_Index", "Stream_Type", "Language",
            "Codec", "Title", "Disposition_Default",
        }
        if not required.issubset(set(reader.fieldnames or [])):
            raise RuntimeError("audit CSV is missing required columns; run scan_media.py again")
        rows = list(reader)

    errors = [row for row in rows if row.get("Inspection_Status") != "OK"]
    if errors:
        raise RuntimeError(f"audit contains {len(errors)} inspection error row(s); scan again")
    return rows


def update_audit_state(path, new_state):
    fd, temporary_path = tempfile.mkstemp(
        prefix=".media_audit_state.", dir=os.path.dirname(path), text=True
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output, open(path, encoding="utf-8") as source:
            for line in source:
                if line.startswith("# MEDIA_AUDIT_STATE="):
                    output.write(f"# MEDIA_AUDIT_STATE={new_state}\n")
                else:
                    output.write(line)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary_path, path)
    except Exception:
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
        raise


def probe(path):
    command = ["ffprobe", "-v", "error", "-print_format", "json", "-show_streams", path]
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=FFPROBE_TIMEOUT, check=False
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(f"ffprobe failed: {exc}") from exc
    if result.returncode:
        raise RuntimeError((result.stderr or "ffprobe failed").strip()[-600:])
    try:
        return json.loads(result.stdout).get("streams", [])
    except (json.JSONDecodeError, AttributeError) as exc:
        raise RuntimeError(f"invalid ffprobe output: {exc}") from exc


def is_english(language):
    value = (language or "").strip().lower().replace("_", "-")
    return value in ("eng", "en", "english") or value.startswith("en-")


def validate_output(output_path, expected_counts):
    if not os.path.isfile(output_path) or os.path.getsize(output_path) == 0:
        raise RuntimeError("FFmpeg produced no usable output file")
    output_streams = probe(output_path)
    actual_counts = defaultdict(int)
    for stream in output_streams:
        actual_counts[stream.get("codec_type", "")] += 1
    for stream_type, expected in expected_counts.items():
        if actual_counts[stream_type] != expected:
            raise RuntimeError(
                f"output validation failed for {stream_type}: expected {expected}, "
                f"found {actual_counts[stream_type]}"
            )


def remux_one(path, rows, work_dir, apply_changes):
    if os.path.islink(path) or not os.path.isfile(path):
        raise RuntimeError("source is not a regular file (symlinks are not replaced)")
    source_stat = os.stat(path)
    expected_size = int(rows[0]["File_Size"])
    expected_mtime = int(rows[0]["File_Mtime_NS"])
    if source_stat.st_size != expected_size or source_stat.st_mtime_ns != expected_mtime:
        raise RuntimeError("source changed since the audit; run scan_media.py again")

    source_streams = probe(path)
    audio_rows = [row for row in rows if row["Stream_Type"] == "audio"]
    subtitle_rows = [row for row in rows if row["Stream_Type"] == "subtitle"]
    if not audio_rows:
        raise RuntimeError("audit contains no audio stream entries for this file")

    english_audio = [row for row in audio_rows if is_english(row["Language"])]
    keep_audio = english_audio if english_audio else audio_rows
    english_subtitles = [row for row in subtitle_rows if is_english(row["Language"])]
    keep_subtitles = english_subtitles if english_subtitles else subtitle_rows

    selected_indexes = {int(row["Stream_Index"]) for row in keep_audio + keep_subtitles}
    if any(index < 0 or index >= len(source_streams) for index in selected_indexes):
        raise RuntimeError("audit stream indexes no longer match the source file")

    extension = os.path.splitext(path)[1]
    is_matroska = extension.lower() == ".mkv"
    mapping = ["-map", "0:v?"]
    for index in sorted(selected_indexes):
        mapping.extend(["-map", f"0:{index}"])
    if is_matroska:
        # Retain embedded fonts/images and data streams in Matroska containers.
        mapping.extend(["-map", "0:t?", "-map", "0:d?"])

    expected_counts = defaultdict(int)
    for stream in source_streams:
        stream_type = stream.get("codec_type", "")
        if stream_type == "video":
            expected_counts["video"] += 1
        elif is_matroska and stream_type in ("attachment", "data"):
            expected_counts[stream_type] += 1
    expected_counts["audio"] = len(keep_audio)
    expected_counts["subtitle"] = len(keep_subtitles)

    extension = extension or ".media"
    temp_input = os.path.join(work_dir, "source" + extension)
    temp_output = os.path.join(work_dir, "remuxed" + extension)
    shutil.copy2(path, temp_input)

    copied_stat = os.stat(temp_input)
    if copied_stat.st_size != expected_size or copied_stat.st_mtime_ns != expected_mtime:
        raise RuntimeError("source changed while it was being staged; run the scan again")

    # The input copy already occupies one file-size worth of buffer space.
    required_space = os.path.getsize(temp_input) + MIN_FREE_SPACE_MARGIN
    free_space = shutil.disk_usage(work_dir).free
    if free_space < required_space:
        raise RuntimeError(
            f"insufficient buffer space: need about {required_space} additional bytes, "
            f"have {free_space} bytes"
        )

    command = [
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-i", temp_input, *mapping,
        "-map_metadata", "0", "-map_chapters", "0", "-c", "copy",
        temp_output,
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError((result.stderr or f"FFmpeg exited {result.returncode}").strip()[-1000:])

    validate_output(temp_output, expected_counts)
    if not apply_changes:
        return

    # Recheck the original immediately before replacement to avoid overwriting concurrent edits.
    latest_stat = os.stat(path)
    if latest_stat.st_size != expected_size or latest_stat.st_mtime_ns != expected_mtime:
        raise RuntimeError("source changed during remux; original has been left untouched")

    # Stage the validated result on the source filesystem, then atomically replace.
    source_dir = os.path.dirname(path)
    fd, sibling_temp = tempfile.mkstemp(
        prefix=".remux-replacement-", suffix=extension, dir=source_dir
    )
    try:
        with os.fdopen(fd, "wb") as destination, open(temp_output, "rb") as remuxed:
            shutil.copyfileobj(remuxed, destination)
            destination.flush()
            os.fsync(destination.fileno())
        shutil.copystat(path, sibling_temp)
        os.replace(sibling_temp, path)
    except Exception:
        try:
            os.unlink(sibling_temp)
        except OSError:
            pass
        raise


def write_report(lines):
    fd, temporary_path = tempfile.mkstemp(
        prefix=".remux_report.", dir=SCRIPT_DIR, text=True
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, REPORT_PATH)
    except Exception:
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
        raise


def main():
    parser = argparse.ArgumentParser(description="Safely remux selected media tracks.")
    parser.add_argument(
        "--apply", action="store_true",
        help="perform remuxing and replace originals after output validation (default is dry-run)",
    )
    args = parser.parse_args()
    dry_run = not args.apply

    if shutil.which("ffprobe") is None or shutil.which("ffmpeg") is None:
        print("ERROR: both ffprobe and ffmpeg must be installed.", file=sys.stderr)
        return 1
    try:
        rows = read_audit(CSV_PATH)
    except (OSError, RuntimeError, csv.Error) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    files = defaultdict(list)
    for row in rows:
        filename = row["Filename"]
        location = row["Location"]
        if not filename or os.path.basename(filename) != filename:
            print(f"ERROR: unsafe filename in audit: {filename!r}", file=sys.stderr)
            return 1
        path = os.path.join(location, filename)
        files[path].append(row)

    os.makedirs(SSD_BUFFER, exist_ok=True)
    if not os.path.isdir(SSD_BUFFER):
        print(f"ERROR: buffer path is not a directory: {SSD_BUFFER}", file=sys.stderr)
        return 1

    total = len(files)
    succeeded = failed = 0
    failures = []
    start = time.monotonic()

    if dry_run:
        print("DRY RUN: FFmpeg will test and validate outputs, but originals will not be changed.")
    else:
        try:
            update_audit_state(CSV_PATH, "IN_PROGRESS")
        except OSError as exc:
            print(f"ERROR: could not mark audit IN_PROGRESS: {exc}", file=sys.stderr)
            return 1

    for index, (path, stream_rows) in enumerate(files.items(), 1):
        name = os.path.basename(path)
        elapsed = time.monotonic() - start
        eta = elapsed / index * (total - index) if index else 0
        percent = index / total * 100 if total else 100
        pc, reset = colour(progress_color(percent)), colour(RESET)
        italic, fg, cyan = colour(ITALIC), colour(FG), colour(CYAN)
        print(
            f"{pc}[{percent:5.1f}%]{reset} {italic}{fg}{name[:40]:<40}{reset} | "
            f"{cyan}ETA:{reset} {int(eta // 3600)}h {int((eta % 3600) // 60)}m"
        )

        work_dir = None
        try:
            work_dir = tempfile.mkdtemp(prefix=f"remux-{index:06d}-", dir=SSD_BUFFER)
            remux_one(path, stream_rows, work_dir, apply_changes=not dry_run)
            succeeded += 1
            if dry_run:
                print("  Remux output validated; original left untouched.")
            else:
                print("  Remuxed and validated; original replaced atomically.")
        except Exception as exc:
            failed += 1
            failures.append(f"{path}: {exc}")
            print(f"  FAILED: {exc}")
        finally:
            if work_dir:
                shutil.rmtree(work_dir, ignore_errors=True)

    duration = int(time.monotonic() - start)
    final_state = "UNPROCESSED (unchanged)" if dry_run else ("PROCESSED" if failed == 0 else "PARTIAL")
    if not dry_run:
        try:
            update_audit_state(CSV_PATH, final_state)
        except OSError as exc:
            failures.append(f"Could not update audit state: {exc}")
            failed += 1
            final_state = "IN_PROGRESS"

    report = [
        "=" * 75,
        " REMUX REPORT ",
        "=" * 75,
        f"Run mode: {'DRY RUN' if dry_run else 'APPLY'}",
        f"Files in audit: {total}",
        f"Validated/replaced successfully: {succeeded}",
        f"Failed: {failed}",
        f"Duration: {duration // 3600}h {(duration % 3600) // 60}m",
        f"Audit state: {final_state}",
    ]
    if failures:
        report.extend(["", "FAILURES:", *failures])
    report.append("=" * 75)
    write_report(report)
    print("\n".join(report))
    if failed:
        print("Review remux_report.txt. Generate a fresh audit before another apply run.")
        return 1
    if dry_run:
        print("Dry run complete. Use --apply only after reviewing the validated run.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
