# System Monitoring

A set of terminal scripts for Linux host health, resource usage, storage capacity, SMART drive information and ZRAM statistics.

## Scripts

| File | Name | Purpose and functionality |
|---|---|---|
| `sys-info.sh` | Basic System Information | Displays distribution/codename, kernel and host details, last-login information, uptime, load averages, process counts split between root and non-root, CPU model/core count and memory totals. |
| `sys-info2.sh` | Extended System Information | Expanded system summary with configurable colour thresholds and icon modes. Reports OS, kernel, login/source IP, uptime, CPU, memory/swap, process counts and (in rich mode) Linux PSI pressure, per-core activity and sensor temperatures when supported. |
| `sys-info-3.sh` | System Status / Health Summary | Further extended status view. Includes virtualization detection, active user sessions, reboot-required marker, failed systemd services, top CPU/memory processes, PSI pressure, per-core activity and sensor temperatures. |
| `diskspace.sh` | Disk Space and Temperature Report | Shows usage bars for mounted filesystems, excluding several virtual filesystems and selected mounts. Attempts non-intrusive SMART temperature reads for the parent physical device and prints an aggregate capacity/usage summary. |
| `hddmonitor.sh` | HDD / Server Vitals Monitor | Displays CPU core temperatures when `sensors` is available, IO wait, filesystem usage bars and SMART drive temperature. Uses SMART standby checks to avoid waking sleeping drives. |
| `hddpower.sh` | Drive Model, Capacity and Power-On Report | Discovers physical block devices and reports model, user capacity and SMART power-on hours, converted to days and years. It reports drive usage age; it does not change drive power settings. |
| `monit-storage.sh` | Storage Activity / Standby Status | Lists physical `/dev/sd*` and `/dev/nvme*` mounted filesystems with usage. Samples disk I/O statistics briefly, then checks SMART standby state to show an activity/awake or sleeping indicator. |
| `zram-info.sh` | ZRAM Usage and Compression Report | Uses `zramctl` to show each ZRAM device's allocated size, data/compressed size, utilisation percentage, compression algorithm and estimated memory savings. Exits quietly if ZRAM tools/devices are unavailable. |

## Usage

Run the required script directly:

```bash
./sys-info.sh
./sys-info2.sh
./sys-info-3.sh
./diskspace.sh
./hddmonitor.sh
sudo ./hddpower.sh | column -t -s $'\t'
./monit-storage.sh
./zram-info.sh
```

Some scripts need elevated permissions for SMART or system information. Use sudo only where required by your system's permissions.

## Requirements

- Bash and standard Linux tools such as `awk`, `df`, `free`, `ps`, `lsblk`, `numfmt`, `uname` and `systemctl`.
- `smartmontools` (`smartctl`) for drive details and temperature/standby queries.
- `bc` for `hddpower.sh`.
- `lm-sensors` (`sensors`) for CPU temperature readings.
- `zramctl` (util-linux) for ZRAM reporting.
- A Nerd Font is recommended for the icon-rich output; the scripts also contain Unicode/colour formatting.

## Notes

- These scripts report current host state; they do not provide continuous monitoring or alert delivery unless separately scheduled or integrated.
- SMART attribute availability and names vary by drive model and controller.
- `diskspace.sh` and `hddmonitor.sh` can require sudo for SMART access. The SMART standby option is used to avoid deliberately waking sleeping disks.
- The system information scripts overlap in purpose but show different levels of detail. Choose the output that suits the terminal/MOTD environment.
