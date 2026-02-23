# System Monitoring Scripts Documentation

This document provides comprehensive documentation for various system monitoring scripts available in the `system-monitoring` directory.

## Scripts Overview

### sys-info.sh
- **Description:** This script gathers system information, including CPU, RAM, and OS details.
- **Dependencies:** 
  - `bash`
  - `uname`
- **Usage:** 
  ```bash
  ./sys-info.sh
  ```
- **Example Output:** 
  - Displays the operating system, kernel version, CPU info, etc.

### sys-info2.sh
- **Description:** An enhanced version of `sys-info.sh` with more detailed information.
- **Dependencies:** 
  - `bash`
  - `lscpu`
- **Usage:** 
  ```bash
  ./sys-info2.sh
  ```
- **Example Output:** 
  - Includes additional statistics like load average.

### sys-info-3.sh
- **Description:** This script provides network statistics.
- **Dependencies:** 
  - `bash`
  - `ifconfig`
- **Usage:** 
  ```bash
  ./sys-info-3.sh
  ```
- **Example Output:** 
  - Shows active network interfaces and their IP addresses.

### diskspace.sh
- **Description:** Checks disk usage and available space on mounted filesystems.
- **Dependencies:** 
  - `bash`
  - `df`
- **Usage:** 
  ```bash
  ./diskspace.sh
  ```
- **Example Output:** 
  - Outputs the disk usage of each mounted filesystem.

### zram-info.sh
- **Description:** Reports statistics related to ZRAM devices.
- **Dependencies:** 
  - `bash`
  - `lszram`
- **Usage:** 
  ```bash
  ./zram-info.sh
  ```
- **Example Output:** 
  - Displays compression ratio and memory statistics.

### hddmonitor.sh
- **Description:** Monitors HDD health and temperature.
- **Dependencies:** 
  - `bash`
  - `smartctl`
- **Usage:** 
  ```bash
  ./hddmonitor.sh
  ```
- **Example Output:** 
  - Shows the smart status and temperature of HDDs.

### hddpower.sh
- **Description:** Controls power management settings for HDDs.
- **Dependencies:** 
  - `bash`
  - `hdparm`
- **Usage:** 
  ```bash
  ./hddpower.sh
  ```
- **Example Output:** 
  - Outputs current power settings and allows modification.

### monit-storage.sh
- **Description:** Monitors storage space and sends alerts when thresholds are breached.
- **Dependencies:** 
  - `bash`
  - `mail`
- **Usage:** 
  ```bash
  ./monit-storage.sh
  ```
- **Example Output:** 
  - Alerts via email if any storage threshold is exceeded.

## Conclusion

This documentation should help you understand how to use the system monitoring scripts effectively. Make sure to review each script for specific environment requirements and configurations.