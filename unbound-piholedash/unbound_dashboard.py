import time
import subprocess
import psutil
import socket
import os
import threading
import requests
import copy
import logging
from flask import Flask, render_template, jsonify
from collections import deque

# OLED Imports (UNCHANGED)
try:
    from luma.core.interface.serial import i2c
    from luma.oled.device import sh1106
    from luma.core.render import canvas
    from PIL import ImageFont
    import PIL
    OLED_AVAILABLE = True
except ImportError:
    OLED_AVAILABLE = False

psutil.cpu_percent(interval=None)

# Configuration
DATA_POLL_INTERVAL = 10
PIHOLE_API_URL = "http://PIHOLE API KEY:8080/api"
PIHOLE_API_TOKEN = "PiHOLE API KEY HERE"
BOOT_TIME = psutil.boot_time()

LOG_IS_ZRAM = any(
    part.mountpoint == '/var/log' and 'zram' in part.device
    for part in psutil.disk_partitions()
)

app = Flask(__name__)

# State
class SystemState:
    def __init__(self):
        self.lock = threading.Lock()
        self.last_query_count = 0
        self.last_query_time = time.time()
        self.first_run = True
        self.history_qpm = deque([0.0]*20, maxlen=20)
        self.history_cache = deque([0.0]*20, maxlen=20)
        self.archive_cache = deque(maxlen=1000)
        self.data = {
            "unbound": {
                "hits": "0",
                "misses": "0",
                "ratio": "0%",
                "total": 0,
                "ratio_value": 0.0
            },
            "pihole": {
                "blocked_today": "0",
                "percent_blocked": "0%",
                "unique_clients": "0",
                "queries_today": "0"
            },
            "system": {
                "Pi-hole Status": "Unknown",
                "Log Storage": "Disk",
                "CPU Usage": "0%",
                "Memory Usage": "0%",
                "Temp": "0°C",
                "System Uptime": "0d 0h",
                "Memory MB": "0MB",
                "Disk Space": "0%",
                "Load Avg": "N/A"
            },
            "qpm": 0,
            "blocked_rate": "0/min"
        }

state = SystemState()

# Pi-hole
def get_pihole_api_stats():
    data = state.data["pihole"]
    try:
        headers = {
            'Authorization': f'Bearer {PIHOLE_API_TOKEN}',
            'Accept': 'application/json'
        }
        r = requests.get(
            f"{PIHOLE_API_URL}/stats/summary",
            headers=headers,
            timeout=2
        )
        if r.status_code == 200:
            api = r.json()
            q = api.get('queries', {})
            data = {
                "blocked_today": f"{q.get('blocked', 0):,}",
                "percent_blocked": f"{q.get('percent_blocked', 0):.1f}%",
                "unique_clients": str(api.get('clients', {}).get('active', 0)),
                "queries_today": f"{q.get('total', 0):,}"
            }
    except Exception as e:
        logging.warning(f"Pi-hole API error: {e}")
    return data


# Unbound (fast parsing)         #make this work add in visudo: piusername ALL=(ALL) NOPASSWD: /usr/sbin/unbound-control
def get_unbound_stats():
    res = state.data["unbound"]
    try:
        result = subprocess.run(
            ["/usr/sbin/unbound-control", "stats_noreset"],
            capture_output=True,
            text=True,
            timeout=2
        )

        if result.returncode != 0:
            return res

        hits = 0
        misses = 0

        for line in result.stdout.splitlines():
            if line.startswith("total.num.cachehits="):
                hits = int(line.split("=")[1])
            elif line.startswith("total.num.cachemiss="):
                misses = int(line.split("=")[1])

        total = hits + misses
        ratio_val = (hits / total) * 100 if total > 0 else 0.0

        res = {
            "hits": f"{hits:,}",
            "misses": f"{misses:,}",
            "ratio": f"{ratio_val:.1f}%",
            "total": total,
            "ratio_value": ratio_val
        }

    except Exception as e:
        logging.warning(f"Unbound error: {e}")

    return res

# System
def get_system_stats():
    mem = psutil.virtual_memory()

    # Load average
    try:
        load_avg = os.getloadavg()[0]
        load_display = f"Load {load_avg:.2f}"
    except:
        load_display = "N/A"

    # ZRAM detection
    if LOG_IS_ZRAM:
        try:
            usage = os.statvfs('/var/log')
            percent = int((1 - usage.f_bavail / usage.f_blocks) * 100)
            log_status = f"ZRAM {percent}%"
        except:
            log_status = "ZRAM"
    else:
        log_status = "Disk"

    # Temperature
    try:
        with open("/sys/class/thermal/thermal_zone0/temp") as f:
            temp = str(int(f.read()) // 1000)
    except:
        temp = "N/A"

    uptime_seconds = int(time.time() - BOOT_TIME)
    uptime_days = uptime_seconds // 86400
    uptime_hours = (uptime_seconds % 86400) // 3600

    pihole_active = os.path.exists("/run/pihole-FTL.pid")

    disk = os.statvfs('/')
    disk_percent = int((1 - disk.f_bavail / disk.f_blocks) * 100)

    return {
        "Pi-hole Status": "Active" if pihole_active else "Stopped",
        "Log Storage": log_status,
        "CPU Usage": f"{psutil.cpu_percent(interval=0)}%",
        "Memory Usage": f"{mem.percent}%",
        "Memory MB": f"{mem.used // 1024 // 1024}MB",
        "Disk Space": f"{disk_percent}%",
        "Temp": f"{temp}°C",
        "System Uptime": f"{uptime_days}d {uptime_hours}h",
        "Load Avg": load_display
    }

# Background Updater
def data_updater():
    while True:
        start = time.time()
        try:
            unbound = get_unbound_stats()
            pihole = get_pihole_api_stats()
            sys_stat = get_system_stats()
            curr_time = time.time()

            with state.lock:
                if state.first_run:
                    qpm = 0.0
                    state.first_run = False
                else:
                    delta_time = max(curr_time - state.last_query_time, 0.001)
                    delta_queries = max(unbound["total"] - state.last_query_count, 0)
                    qpm = (delta_queries / delta_time) * 60

                state.last_query_count = unbound["total"]
                state.last_query_time = curr_time

                state.history_qpm.append(qpm)
                state.history_cache.append(unbound["ratio_value"])

                # Calculate blocked per minute
                try:
                    blocked = int(pihole["blocked_today"].replace(",", ""))
                    uptime_mins = (curr_time - BOOT_TIME) / 60
                    blocked_per_min = blocked / uptime_mins if uptime_mins > 0 else 0
                    blocked_rate = f"{blocked_per_min:.1f}/min"
                except:
                    blocked_rate = "0/min"

                state.data["unbound"] = unbound
                state.data["pihole"] = pihole
                state.data["system"] = sys_stat
                state.data["qpm"] = int(qpm)
                state.data["blocked_rate"] = blocked_rate

        except Exception as e:
            logging.warning(f"Updater error: {e}")

        time.sleep(max(DATA_POLL_INTERVAL - (time.time() - start), 0))

# OLED WORKER
def oled_worker():
    if not OLED_AVAILABLE:
        return

    serial = i2c(port=1, address=0x3C)
    device = sh1106(serial, rotate=2)

    try:
        font_path = os.path.join(os.path.dirname(PIL.__file__), "fonts", "cp437_8x8.pil")
        my_font = ImageFont.load(font_path)
    except:
        my_font = ImageFont.load_default()

    while True:
        with state.lock:
            d = copy.deepcopy(state.data)

        u = d["unbound"]
        s = d["system"]

        ph_label = "UP" if "Active" in s["Pi-hole Status"] else "X"
        zram_val = s["Log Storage"].split()[-1] if " " in s["Log Storage"] else ""

        with canvas(device) as draw:
            bbox = my_font.getbbox("A")
            lh = (bbox[3] - bbox[1]) + 4
            y = 0

            draw.text((0, y), f"Quer {u['total']}  Hits {u['hits']}", font=my_font, fill="white"); y += lh
            draw.text((0, y), f"Ratio {u['ratio']}  Miss {u['misses']}", font=my_font, fill="white"); y += lh
            draw.line((0, y, 128, y), fill="white"); y += 2
            draw.text((0, y), f"CPU {s['CPU Usage']}  TMP {s['Temp']}", font=my_font, fill="white"); y += lh
            draw.text((0, y), f"RAM {s['Memory Usage']}  ZRM {zram_val}", font=my_font, fill="white"); y += lh
            draw.line((0, y, 128, y), fill="white"); y += 2
            draw.text((0, y), f"PiHole {ph_label}  Uptime {s['System Uptime'].split(' ')[0]}", font=my_font, fill="white")

        time.sleep(15)

# Routes
@app.route('/')
def dashboard():
    return render_template(
        "dashboard.html",
        hostname=socket.gethostname(),
        timestamp=time.strftime("%Y-%m-%d %H:%M:%S")
    )

@app.route('/api/data')
def api_data():
    with state.lock:
        response_data = copy.deepcopy(state.data)

        # Add sparkline data
        response_data['sparklines'] = {
            'qpm': list(state.history_qpm),
            'cache': list(state.history_cache)
        }

        # Add trend calculation for cache ratio
        if len(state.history_cache) >= 2:
            recent_avg = sum(list(state.history_cache)[-5:]) / 5
            older_avg = sum(list(state.history_cache)[:5]) / 5 if len(state.history_cache) >= 10 else recent_avg
            trend_diff = recent_avg - older_avg

            if trend_diff > 1:
                response_data['cache_trend'] = f"↑{trend_diff:.1f}%"
                response_data['trend_color'] = "#4ade80"
            elif trend_diff < -1:
                response_data['cache_trend'] = f"↓{abs(trend_diff):.1f}%"
                response_data['trend_color'] = "#f87171"
            else:
                response_data['cache_trend'] = "~"
                response_data['trend_color'] = "white"
        else:
            response_data['cache_trend'] = "~"
            response_data['trend_color'] = "white"

        # Add hit trend indicator
        if len(state.history_qpm) >= 2:
            recent_qpm = sum(list(state.history_qpm)[-3:]) / 3
            if recent_qpm > 10:
                response_data['hit_trend'] = "↑ High"
            elif recent_qpm > 5:
                response_data['hit_trend'] = "~ Med"
            else:
                response_data['hit_trend'] = "↓ Low"
        else:
            response_data['hit_trend'] = "~"

        # Add timestamp
        response_data['timestamp'] = time.strftime("%Y-%m-%d %H:%M:%S")

        return jsonify(response_data)


# Main
if __name__ == "__main__":
    threading.Thread(target=data_updater, daemon=True).start()
    if OLED_AVAILABLE:
        threading.Thread(target=oled_worker, daemon=True).start()
    app.run(host="0.0.0.0", port=5000, threaded=True)
