#!/usr/bin/env python3
"""Run the media scan and apply all positively identified safe remuxes."""
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPORT = HERE / "media_run_report.txt"

def preflight_media_root():
    root = Path(os.path.expandvars(os.path.expanduser(os.environ.get("MEDIA_ROOT", "/media")))).resolve()
    if not root.is_dir():
        raise RuntimeError(f"media root does not exist or is not a directory: {root}")

    # WSL must never mistake an empty local mountpoint for the network library.
    is_wsl = bool(os.environ.get("WSL_DISTRO_NAME")) or Path("/proc/sys/fs/binfmt_misc/WSLInterop").exists()
    if is_wsl:
        matching_mounts = []
        try:
            with open("/proc/mounts", encoding="utf-8") as mounts:
                for line in mounts:
                    fields = line.split()
                    if len(fields) < 3 or fields[2] != "cifs":
                        continue
                    mountpoint = fields[1].replace("\\040", " ").replace("\\011", "\t")
                    mountpoint = os.path.realpath(mountpoint)
                    if str(root) == mountpoint or str(root).startswith(mountpoint.rstrip("/") + "/"):
                        matching_mounts.append(mountpoint)
        except OSError as exc:
            raise RuntimeError(f"cannot verify the WSL SMB mount: {exc}") from exc
        if not matching_mounts:
            raise RuntimeError(
                f"{root} is not inside a mounted SMB/CIFS share. Mount the intended share first; "
                "refusing to scan or modify a local mountpoint."
            )

    # Check write/delete access at the library root before processing files.
    fd, probe_path = tempfile.mkstemp(prefix=".media-manager-write-test-", dir=str(root))
    os.close(fd)
    os.unlink(probe_path)


def acquire_run_lock():
    lock_path = HERE / ".media_manager.lock"
    handle = open(lock_path, "a+")
    try:
        if os.name == "nt":
            import msvcrt
            handle.seek(0)
            if handle.read(1) == "":
                handle.seek(0)
                handle.write("0")
                handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        raise RuntimeError("another media-management run is already active")
    return handle


def main():
    try:
        lock = acquire_run_lock()
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    try:
        try:
            preflight_media_root()
        except (OSError, RuntimeError) as exc:
            print(f"ERROR: preflight failed: {exc}", file=sys.stderr)
            return 2

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
    finally:
        lock.close()

if __name__ == "__main__":
    raise SystemExit(main())
