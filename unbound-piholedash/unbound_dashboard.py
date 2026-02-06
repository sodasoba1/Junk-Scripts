from flask import Flask, request, abort, render_template
import subprocess
import psutil
import datetime
import socket
import os

# add your LAN range but leave the last EG 192.168.1. or 192.168.188.
LAN_PREFIX = "192.168.XXX."
REFRESH_INTERVAL = 5
HISTORY_LEN = 20

app = Flask(__name__)
cache_ratio_history = []
psutil.cpu_percent(interval=None)

def update_cache_history(ratio):
    cache_ratio_history.append(ratio)
    if len(cache_ratio_history) > HISTORY_LEN:
        cache_ratio_history.pop(0)

@app.before_request
def limit_remote_addr():
    client_ip = request.remote_addr
    # Allow localhost and LAN devices
    if client_ip != "127.0.0.1" and not client_ip.startswith(LAN_PREFIX):
        abort(403)

def get_pihole_status():
    """Checks if Pi-hole FTL service is active using systemctl"""
    try:
        # Check if the service is 'active'
        cmd = ["systemctl", "is-active", "pihole-FTL"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=1)

        if result.stdout.strip() == "active":
            # Optional: Check if blocking is actually enabled
            # Pi-hole stores status in its own DB/config, but 'active'
            # usually means it's working.
            return "Active (Enabled)"
        else:
            return "⚠️ Stopped"
    except:
        return "Unknown"

def get_unbound_stats():
    data = {
        "hits": "0", "misses": "0", "ratio": "0%", "total": "0",
        "memory": "0 MB", "uptime": "0h 0m", "ratio_value": 0, "Error": None
    }
    try: 
        #make this work add in visudo: pi ALL=(ALL) NOPASSWD: /usr/sbin/unbound-control
        cmd = ["sudo", "/usr/sbin/unbound-control", "-c", "/etc/unbound/unbound.conf.d/pi-hole.conf", "stats_noreset"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
        if result.returncode != 0:
            data["Error"] = "Sudo permission denied"
            return data

        stats = {}
        for line in result.stdout.strip().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                stats[k.strip()] = v.strip()

        hits = int(stats.get("total.num.cachehits", 0))
        misses = int(stats.get("total.num.cachemiss", 0))
        total = hits + misses
        ratio = round((hits / total) * 100, 1) if total > 0 else 0
        uptime_sec = int(float(stats.get("time.up", 0)))
        mem_mb = (int(stats.get("mem.cache.rrset", 0)) + int(stats.get("mem.cache.message", 0))) // 1024 // 1024

        data.update({
            "hits": f"{hits:,}", "misses": f"{misses:,}", "ratio": f"{ratio}%",
            "total": f"{total:,}", "memory": f"{mem_mb} MB",
            "uptime": f"{uptime_sec//3600}h {(uptime_sec%3600)//60}m", "ratio_value": ratio
        })
    except Exception as e:
        data["Error"] = f"Internal Error: {str(e)}"
    return data

def get_system_stats():
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    cpu = psutil.cpu_percent(interval=None)
    # 2. Temperature
    try:
        temp = subprocess.check_output(["vcgencmd", "measure_temp"]).decode().split("=")[1].replace("'C\n", "")
    except: temp = "N/A"
    # 3. Uptime
    uptime = datetime.datetime.now() - datetime.datetime.fromtimestamp(psutil.boot_time())
    # 4. Load Averages (Tuple: 1 min, 5 min, 15 min)
    try:
        load1, load5, load15 = os.getloadavg()
    except:
        load1, load5, load15 = (0, 0, 0)
    # 5. Power/Throttling Health
    # 0x50005 means under-voltage occurring. 0x0 means fine.
    throttle_status = "OK"
    try:
        out = subprocess.check_output(["vcgencmd", "get_throttled"]).decode().strip()
        code = int(out.split("=")[1], 16)
        if code != 0:
            # Decode common bits
            reasons = []
            if code & 0x1: reasons.append("Under-voltage")
            if code & 0x2: reasons.append("Freq Capped")
            if code & 0x4: reasons.append("Throttled")
            if code & 0x10000: reasons.append("Was Under-voltage")
            throttle_status = "⚠️ " + ", ".join(reasons)
    except:
        throttle_status = "Unknown"

    return {
        "Pi-hole Status": get_pihole_status(),
        "CPU Load (1m/5m)": f"{load1:.2f} / {load5:.2f}",
        "CPU Usage": f"{cpu}%",
        "Power Health": throttle_status,
        "Memory Usage": f"{mem.percent}% ({mem.used//1024//1024}MB)",
        "Disk Space": f"{disk.percent}%",
        "Temp": f"{temp}°C",
        "System Uptime": f"{uptime.days}d {uptime.seconds//3600}h {(uptime.seconds%3600)//60}m"
    }

@app.route("/")
def dashboard():
    unbound = get_unbound_stats()
    update_cache_history(unbound.get("ratio_value", 0))
    system = get_system_stats()

    return render_template("dashboard.html",
                           unbound=unbound,
                           system=system,
                           history=cache_ratio_history,
                           refresh=REFRESH_INTERVAL,
                           hostname=socket.gethostname(),
                           timestamp=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
