import os
import subprocess
import json
import shutil
import time
import csv

# --- CONFIGURATION ---
# IMPORTANT: Use the actual mount path, e.g., '/media/'
root_directory = '/media' 
output_file = '/home/your_username/media_audit.csv' # Save to your home folder for easy access
extensions = ('.mp4', '.mkv', '.avi', '.mov', '.m4v')
# ---------------------

def get_audio_info(file_path):
    cmd = ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_streams', '-select_streams', 'a', file_path]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode('utf-8')
        return json.loads(result).get('streams', [])
    except: return []

def scan():
    if shutil.which('ffprobe') is None:
        print("Error: ffprobe not found. Run: sudo apt install ffmpeg")
        return

    found_count = 0
    total_scanned = 0
    start_time = time.time()
    
    with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
        fieldnames = ['Filename', 'Size_GB', 'Location', 'Track', 'Language', 'Codec', 'Title']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

        for root, dirs, files in os.walk(root_directory):
            for file in files:
                if file.lower().endswith(extensions):
                    total_scanned += 1
                    full_path = os.path.join(root, file)
                    
                    # Terminal feedback
                    if total_scanned % 10 == 0:
                        print(f"  Scanned: {total_scanned} | Found: {found_count}", end='\r')

                    streams = get_audio_info(full_path)
                    
                    if len(streams) > 1:
                        langs = [s.get('tags', {}).get('language', 'und').lower() for s in streams]
                        
                        # Only log if NOT purely English
                        if not all(l == 'eng' for l in langs):
                            found_count += 1
                            f_size = os.path.getsize(full_path) / (1024**3)
                            
                            for i, s in enumerate(streams):
                                writer.writerow({
                                    'Filename': file,
                                    'Size_GB': round(f_size, 2),
                                    'Location': root,
                                    'Track': i + 1,
                                    'Language': s.get('tags', {}).get('language', 'und').upper(),
                                    'Codec': s.get('codec_name', 'unknown'),
                                    'Title': s.get('tags', {}).get('title', '')
                                })

    print(f"\nScan Complete. Total Flagged: {found_count}")
    print(f"Results saved to: {output_file}")

if __name__ == "__main__":
    scan()
