#!/usr/bin/env python3
"""Run the media scan and apply all positively identified safe remuxes."""
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPORT = HERE / "media_run_report.txt"

def main():
    if os.environ.get("MEDIA_ROOT"):
        print("NOTE: scan_media.py uses ROOT_DIRECTORY in its configuration; MEDIA_ROOT only affects media.sh.")
    scan = subprocess.run([sys.executable, str(HERE / "scan_media.py")], cwd=HERE)
    if scan.returncode:
        print("Scan could not complete. No remuxes were attempted.", file=sys.stderr)
        return scan.returncode

    apply = subprocess.run([sys.executable, str(HERE / "audio_cleaner.py"), "--apply"], cwd=HERE)
    cleaner_report = HERE / "remux_report.txt"
    details = cleaner_report.read_text(encoding="utf-8") if cleaner_report.exists() else "Cleaner report was not produced."
    content = [
        "MEDIA MANAGEMENT RUN",
        "=" * 72,
        f"Completed: {datetime.now(timezone.utc).isoformat()}",
        "Mode: AUTOMATIC APPLY",
        "Backups: not created (validated temporary staging only)",
        "",
        details.rstrip(),
        "",
        "Review media_audit.csv and the MANUAL REVIEW REQUIRED / FAILURES sections above.",
        "Only successfully validated and atomically replaced files count toward reclaimed space.",
        "=" * 72,
    ]
    temporary = REPORT.with_suffix(".tmp")
    temporary.write_text("\n".join(content) + "\n", encoding="utf-8")
    os.replace(temporary, REPORT)
    print(f"\nRun summary: {REPORT}")
    return apply.returncode

if __name__ == "__main__":
    raise SystemExit(main())
