# Raspberry Pi 3 Ubuntu TX/RX LED Indicator

This folder contains a small Python service that repurposes the Raspberry Pi status LEDs to indicate Ethernet/network activity and packet drops.

## Files

| File | Name | Purpose and functionality |
|---|---|---|
| `usr/local/bin/txrx_led.py` | Network TX/RX and Drop LED Monitor | Reads interface counters and link state from `/sys/class/net`. The green ACT LED is normally on while the configured interface is up and briefly flickers when RX/TX byte counters change. The red PWR LED briefly flashes when RX or TX dropped-packet counters increase, with a one-second debounce. Missing interfaces and runtime errors are handled by waiting/retrying and attempting to turn both LEDs off. |
| `etc/systemd/system/txrx-led.service` | TX/RX LED systemd Service | Defines a system service to run the Python LED monitor at boot. The unit refers to the installed script path and must be adjusted for the actual service user/group and installation. |

## Configuration

Edit `usr/local/bin/txrx_led.py` before installing:

- Set `IFACE` to the actual network interface name. It is a placeholder in the current source.
- Confirm that `LED_GREEN` and `LED_RED` match the LED class-device paths on the target Raspberry Pi.
- The script disables the kernel LED triggers and controls brightness directly through sysfs.

## Installation outline

Copy the Python script to `/usr/local/bin/txrx_led.py`, edit the service's `User`, `Group` and `WorkingDirectory` values as appropriate, install the unit under `/etc/systemd/system/`, then reload systemd and enable/start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now txrx-led.service
sudo systemctl status txrx-led.service
```

The service must have permission to write to the LED sysfs brightness/trigger files. Running it as an unprivileged user may require a deliberate permissions/udev setup.

## Requirements and limitations

- Raspberry Pi hardware exposing the expected ACT/PWR LED sysfs interfaces.
- Python 3 and access to network interface statistics under `/sys/class/net`.
- A valid configured interface name.
- The script polls every 50 ms while the interface is up; it is intended as a lightweight local indicator, not a network diagnostic tool.
