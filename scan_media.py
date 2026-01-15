#!/usr/bin/env python3
import os
import subprocess
import json
import csv
import shutil
from datetime import datetime

# ---------------- CONFIG ----------------
ROOT_DIRECTORY = "/media"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(SCRIPT_DIR, "media_audit.csv")

VIDEO_EXTENSIONS = (".mkv", ".mp4", ".avi", ".mov", ".m4v")
# ----------------------------------------

def ffprobe_streams(path):
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_streams",
        path
    ]
    try:
        out = subprocess.check_output(cmd)
        return json.loads(out).get("streams", [])
    except Exception:
        return []

def scan():
    if shutil.which("ffprobe") is None:
        print("ERROR: ffprobe not found (install ffmpeg)")
        return

    now = datetime.utcnow().isoformat() + "Z"

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
