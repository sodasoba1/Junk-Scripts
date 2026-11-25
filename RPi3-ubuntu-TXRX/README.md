# Raspberry Pi 3 Ubuntu TX/RX LED Indicator

This folder contains a Python service that uses Linux LED class devices to indicate network link state, traffic and interface packet drops.

## Files

| File | Name | Purpose and functionality |
|---|---|---|
| `usr/local/bin/txrx_led.py` | Network TX/RX and Drop LED Monitor | Reads link state and RX/TX byte/drop counters from `/sys/class/net/<interface>`. The green LED is solid while the interface is up and is briefly interrupted when traffic counters increase. The red LED pulses when RX or TX dropped-packet counters increase, with a one-second minimum interval between pulses. |
| `etc/systemd/system/txrx-led.service` | TX/RX LED systemd Service | Runs the monitor as root at boot, restarts it after an unexpected failure and leaves output in the systemd journal for diagnosis. |

## Hardware and configuration checks

The script's defaults are examples, not guaranteed Raspberry Pi sysfs names. Before installing, identify the actual interface and LED class-device names on the target system:

```bash
ip -br link
ls -l /sys/class/leds/
```

Edit `usr/local/bin/txrx_led.py`:

- Set `IFACE` to the required interface name (for example, `eth0` only if that is what `ip -br link` reports).
- Set `LED_GREEN` and `LED_RED` to the actual LED directories shown under `/sys/class/leds/`.
- The selected LED devices must expose a writable `brightness` file. If a `trigger` file exists, the script disables the trigger while running and restores its previous active trigger on shutdown.

The script requires no third-party Python packages. It runs as root because the LED sysfs controls are normally writable only by root.

## Installation

From the repository's `RPi3-ubuntu-TXRX` directory, install the files:

```bash
sudo install -D -m 0755 usr/local/bin/txrx_led.py /usr/local/bin/txrx_led.py
sudo install -D -m 0644 etc/systemd/system/txrx-led.service /etc/systemd/system/txrx-led.service
```

Edit the installed script's interface and LED paths, then enable the service:

```bash
sudo nano /usr/local/bin/txrx_led.py
sudo systemctl daemon-reload
sudo systemctl enable --now txrx-led.service
sudo systemctl status txrx-led.service
```

View runtime messages and errors with:

```bash
sudo journalctl -u txrx-led.service -f
```

After changing the script or service file, restart the service:

```bash
sudo systemctl restart txrx-led.service
```

## Behaviour and limitations

- **Green LED:** solid on while `operstate` is `up`; a traffic-counter increase briefly turns it off for approximately 30 ms. It is not an off-when-idle activity LED.
- **Red LED:** pulses for approximately 200 ms when either `rx_dropped` or `tx_dropped` increases. Pulses are rate-limited to at most one per second.
- The first counter sample establishes a baseline, avoiding a false activity/drop event at startup. Counter decreases (for example, after an interface reset) establish a new baseline and are not reported as drops.
- Counters are sampled while the interface exists, including while its link is down. This avoids treating accumulated changes during link-down as a new event on reconnection.
- Missing interfaces are retried. Read/write failures are logged; the service remains diagnosable through the systemd journal.
- On SIGTERM/SIGINT, the script turns the LEDs off and restores their previously active kernel triggers when available.
- `rx_dropped` and `tx_dropped` are specific Linux interface statistics. They do not represent every possible network error; this script does not monitor `rx_errors` or `tx_errors`.
- Actual LED names, availability and behaviour depend on the Raspberry Pi model, Ubuntu kernel and device-tree configuration. Static code review cannot confirm hardware compatibility; verify the sysfs paths on the target Pi.
- Polling is nominally every 50 ms while the link is up. A traffic or drop indication temporarily adds its blink duration to that cycle.
