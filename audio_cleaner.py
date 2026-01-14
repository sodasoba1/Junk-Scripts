#!/usr/bin/env python3
import os
import csv
import sys
import shutil
import subprocess
import time
from collections import defaultdict
from datetime import datetime

# ---------------- CONFIG ----------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(SCRIPT_DIR, "media_audit.csv")
REPORT_PATH = os.path.join(SCRIPT_DIR, "remux_report.txt")

SSD_BUFFER = os.path.expanduser("~/remux_buffer")
DRY_RUN = False
# ----------------------------------------

# ---- Dracula-friendly ANSI ----
RESET  = "\033[0m"
BOLD   = "\033[1m"
ITALIC = "\033[3m"
DIM    = "\033[2m"

PURPLE = "\033[38;5;141m"
ORANGE = "\033[38;5;208m"
CYAN   = "\033[38;5;81m"
GREEN  = "\033[38;5;82m"
FG     = "\033[38;5;252m"

def progress_color(p):
    if p < 25: return PURPLE
    if p < 50: return ORANGE
    if p < 75: return CYAN
    return GREEN

def check_csv_state(path):
    state = None
    header = []

    with open(path, encoding="utf-8") as f:
        for line in f:
            if not line.startswith("#"):
                break
            header.append(line.strip())
            if line.startswith("# MEDIA_AUDIT_STATE="):
                state = line.split("=", 1)[1].strip()

    if state is None:
        print("✖ ERROR: CSV missing MEDIA_AUDIT_STATE")
        sys.exit(1)

    if state == "UNPROCESSED":
        print("✔ CSV state: UNPROCESSED — proceeding")
        return header

    if state == "IN_PROGRESS":
        print("⚠ CSV state: IN_PROGRESS — previous run incomplete")
        sys.exit(1)

    if state == "PROCESSED":
        print("ℹ CSV already PROCESSED — regenerate CSV")
        sys.exit(0)

    print(f"✖ ERROR: Unknown CSV state {state}")
    sys.exit(1)

def mark_csv_state(path, new_state):
    lines = []
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()

    with open(path, "w", encoding="utf-8") as f:
        for line in lines:
            if line.startswith("# MEDIA_AUDIT_STATE="):
                f.write(f"# MEDIA_AUDIT_STATE={new_state}\n")
            else:
                f.write(line)

def remux():
    if not os.path.exists(SSD_BUFFER):
        os.makedirs(SSD_BUFFER)

    header = check_csv_state(CSV_PATH)
    mark_csv_state(CSV_PATH, "IN_PROGRESS")

    rows = []
    with open(CSV_PATH, encoding="utf-8") as f:
        reader = csv.DictReader(l for l in f if not l.startswith("#"))
        rows = list(reader)

    files = defaultdict(list)
    for r in rows:
        path = os.path.join(r["Location"], r["Filename"])
        files[path].append(r)

    total = len(files)
    start = time.time()

    for i, (path, streams) in enumerate(files.items(), 1):
        name = os.path.basename(path)
        temp_in  = os.path.join(SSD_BUFFER, f"IN_{name}")
        temp_out = os.path.join(SSD_BUFFER, f"OUT_{name}")

        audio = [s for s in streams if s["Stream_Type"] == "audio"]
        subs  = [s for s in streams if s["Stream_Type"] == "subtitle"]

        eng_audio = [s for s in audio if s["Language"].lower() == "eng"]
        keep_audio = eng_audio if eng_audio else audio

        eng_subs = [s for s in subs if s["Language"].lower() == "eng"]
        keep_subs = eng_subs if eng_subs else subs

        mapping = ["-map", "0:v"]
        for s in keep_audio + keep_subs:
            mapping += ["-map", f"0:{s['Stream_Index']}"]

        percent = i / total * 100
        elapsed = time.time() - start
        eta = elapsed / i * (total - i)

        pc = progress_color(percent)
        print(
            f"{pc}[{percent:5.1f}%]{RESET} "
            f"{ITALIC}{FG}{name[:40]:<40}{RESET} | "
            f"{CYAN}ETA:{RESET} {int(eta//3600)}h {int((eta%3600)//60)}m"
        )

        if DRY_RUN:
            continue

        shutil.copy2(path, temp_in)

        cmd = [
            "ffmpeg", "-y", "-i", temp_in,
            *mapping,
            "-c", "copy",
            "-disposition:a:0", "default",
            "-disposition:s:0", "default",
            temp_out
        ]

        res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        if res.returncode == 0:
            os.remove(path)
            shutil.move(temp_out, path)

        if os.path.exists(temp_in):
            os.remove(temp_in)

    mark_csv_state(CSV_PATH, "PROCESSED")

    duration = int(time.time() - start)
    report = [
        "=" * 75,
        " FINAL REMUX REPORT ",
        "=" * 75,
        f"Files processed: {total}",
        f"Total duration: {duration//3600}h {(duration%3600)//60}m",
        "=" * 75,
    ]

    with open(REPORT_PATH, "w") as f:
        f.write("\n".join(report))

    print("\n".join(report))

if __name__ == "__main__":
    remux()
    with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
        # ---- CSV HEADER STATE ----
        f.write("# MEDIA_AUDIT_STATE=UNPROCESSED\n")
        f.write(f"# GENERATED_AT={now}\n")
        f.write("# GENERATED_BY=scan_media.py\n")

        fieldnames = [
            "Filename",
            "Location",
            "Stream_Index",
            "Stream_Type",
            "Language",
            "Codec",
            "Title",
            "Disposition_Default"
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        scanned = 0
        flagged = 0

        for root, _, files in os.walk(ROOT_DIRECTORY):
            for name in files:
                if not name.lower().endswith(VIDEO_EXTENSIONS):
                    continue

                scanned += 1
                full_path = os.path.join(root, name)
                streams = ffprobe_streams(full_path)

                audio = [s for s in streams if s.get("codec_type") == "audio"]
                subs  = [s for s in streams if s.get("codec_type") == "subtitle"]

                if not audio:
                    continue

                langs = [s.get("tags", {}).get("language", "und").lower() for s in audio]

                # ---- SKIP CLEAN FILES ----
                if len(audio) == 1 and langs[0] == "eng":
                    continue

                flagged += 1

                for s in audio + subs:
                    writer.writerow({
                        "Filename": name,
                        "Location": root,
                        "Stream_Index": s.get("index"),
                        "Stream_Type": s.get("codec_type"),
                        "Language": s.get("tags", {}).get("language", "und").upper(),
                        "Codec": s.get("codec_name", "unknown"),
                        "Title": s.get("tags", {}).get("title", ""),
                        "Disposition_Default": s.get("disposition", {}).get("default", 0)
                    })

                if scanned % 50 == 0:
                    print(f" Scanned: {scanned} | Flagged: {flagged}", end="\r")

    print(f"\nScan complete.")
    print(f"Files flagged: {flagged}")
    print(f"CSV written to: {CSV_PATH}")

if __name__ == "__main__":
    scan()
