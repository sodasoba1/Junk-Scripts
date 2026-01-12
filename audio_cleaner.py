import os
import subprocess
import csv
import shutil
import time
import sys
from collections import defaultdict

# media_audit.csv is made via the scan_media.py script

# --- CONFIGURATION ---
input_csv = 'media_audit.csv'
report_file = 'remux_report.txt'
dry_run = TRUE  # SET TO False TO BEGIN RECLAIMING SPACE
os_temp_dir = os.path.expanduser('~/remux_buffer')
# ---------------------

def format_bytes(size):
    power = 2**10
    n = 0
    labels = {0 : '', 1: 'K', 2: 'M', 3: 'G', 4: 'T'}
    while abs(size) > power and n < 4:
        size /= power
        n += 1
    return f"{size:.2f} {labels[n]}B"

def format_time(seconds):
    if seconds < 60: return f"{int(seconds)}s"
    elif seconds < 3600: return f"{int(seconds//60)}m {int(seconds%60)}s"
    else: return f"{int(seconds//3600)}h {int((seconds%3600)//60)}m"

def get_mount_point(path):
    path = os.path.abspath(path)
    while not os.path.ismount(path):
        parent = os.path.dirname(path)
        if parent == path: break
        path = parent
    return path

def analyze_csv_data(csv_path):
    file_groups = defaultdict(list)
    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                full_path = os.path.join(row['Location'], row['Filename'])
                file_groups[full_path].append(row)
    except Exception as e:
        print(f"Error reading CSV: {e}")
        sys.exit(1)

    clean_queue = []
    skipped_count = 0
    for full_path, tracks in file_groups.items():
        foreign_tracks = [t for t in tracks if t['Language'].lower() not in ['eng', 'und']]
        if len(foreign_tracks) > 0:
            has_eng = any(t['Language'].lower() == 'eng' for t in tracks)
            clean_queue.append((full_path, tracks, has_eng))
        else:
            skipped_count += 1
    return clean_queue, skipped_count

def process_files():
    if not os.path.exists(os_temp_dir):
        os.makedirs(os_temp_dir)

    print(f"Analyzing {input_csv}...")
    work_queue, skipped_count = analyze_csv_data(input_csv)
    total_to_clean = len(work_queue)

    print(f"Analysis Results:")
    print(f" - Files already clean: {skipped_count}")
    print(f" - Files to be cleaned: {total_to_clean}")
    print("-" * 75)

    if total_to_clean == 0: return

    cleaned_count = 0
    total_saved = 0
    drive_stats = defaultdict(int)
    start_time = time.time()

    for i, (full_path, tracks, has_eng) in enumerate(work_queue):
        filename = os.path.basename(full_path)
        location = os.path.dirname(full_path)

        # Build FFmpeg Mapping
        mapping = ['-map', '0:v']
        if has_eng:
            for t in tracks:
                if t['Language'].lower() in ['eng', 'und']:
                    mapping.extend(['-map', f'0:{t["Track Number"]}'])
        else:
            for t in tracks:
                mapping.extend(['-map', f'0:{t["Track Number"]}'])

        # Progress Logic
        percent = (i + 1) / total_to_clean * 100
        elapsed = time.time() - start_time
        avg_time = elapsed / (i + 1)
        eta = avg_time * (total_to_clean - (i + 1))

        # Real-time line print
        sys.stdout.write(f"[{percent:5.1f}%] {filename[:40]:<40} | Saved: {format_bytes(total_saved):>9} | ETA: {format_time(eta):>8}\n")
        sys.stdout.flush()

        if not dry_run:
            temp_input = os.path.join(os_temp_dir, f"TEMP_IN_{filename}")
            temp_output = os.path.join(os_temp_dir, f"TEMP_OUT_{filename}")
            try:
                old_size = os.path.getsize(full_path)

                # Copy to SSD
                shutil.copy2(full_path, temp_input)

                # Remux on SSD
                cmd = ['ffmpeg', '-y', '-i', temp_input] + mapping + ['-c', 'copy', '-map_metadata', '0', temp_output]
                res = subprocess.run(cmd, capture_output=True)

                if res.returncode == 0:
                    new_size = os.path.getsize(temp_output)
                    os.remove(full_path)
                    shutil.move(temp_output, full_path)

                    saved = old_size - new_size
                    total_saved += saved
                    drive_stats[get_mount_point(location)] += saved
                    cleaned_count += 1

                    # DYNAMIC COOLDOWN: 5s for movies (>2GB), 1s for TV/Anime
                    nap_time = 5 if old_size > 2 * 1024**3 else 1
                    time.sleep(nap_time)

                if os.path.exists(temp_input): os.remove(temp_input)
            except Exception as e:
                print(f"!! Error on {filename}: {e}")

    # --- FINAL REPORT ---
    duration = time.time() - start_time
    report = [
        "="*75, " FINAL REMUX REPORT ", "="*75,
        f"Files Skipped (Already Clean): {skipped_count}",
        f"Files Processed:              {cleaned_count}",
        f"Total Job Duration:           {format_time(duration)}",
        "-"*75, "SPACE RECLAIMED PER MOUNT POINT:"
    ]
    for drive, saved in sorted(drive_stats.items()):
        report.append(f" {drive:<35}: {format_bytes(saved)}")
    report.append("-" * 75)
    report.append(f" GRAND TOTAL SPACE RECLAIMED: {format_bytes(total_saved)}")
    report.append("=" * 75)

    final_text = "\n".join(report)
    print(f"\n{final_text}")
    if not dry_run:
        with open(report_file, 'w') as f: f.write(final_text)

if __name__ == "__main__":
    process_files()
