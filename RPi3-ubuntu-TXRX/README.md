# Raspberry Pi 3 Ubuntu TX/RX LED Indicator

This directory contains a first-run setup script, a Python network/LED monitor and its systemd unit. The monitor uses the Pi's ACT and PWR LED class devices to indicate link state, traffic and interface packet drops.

## Files

| Repository path | Installed path | Purpose |
|---|---|---|
| `usr/local/sbin/setup-txrx-led.sh` | `/usr/local/sbin/setup-txrx-led.sh` | First-run configuration. Checks the LED controls, detects the default-route interface and writes the selection to `/etc/default/txrx-led`. |
| `usr/local/bin/txrx_led.py` | `/usr/local/bin/txrx_led.py` | Python monitor. Reads link state and RX/TX byte/drop counters from `/sys/class/net/<interface>`. |
| `etc/systemd/system/txrx-led.service` | `/etc/systemd/system/txrx-led.service` | Starts the monitor at boot and supplies its interface configuration. |

## Hardware assumptions

The setup script checks these LED paths, which have been confirmed on the target Raspberry Pi 3 Ubuntu installation:

- Green/activity: `/sys/class/leds/ACT`
- Red/power: `/sys/class/leds/PWR`

For each device it verifies that the directory and `brightness` control exist and that the control is writable when run as root. It does not change LED brightness or triggers during setup.

The Python monitor also checks `max_brightness` when available so that an LED's full-on value is not assumed to be `1`. If a `trigger` control exists, it records the active trigger, selects `none` while the monitor is running, and attempts to restore the previous trigger on shutdown.

## First-run setup and installation

Run these commands from the repository's `RPi3-ubuntu-TXRX` directory:

```bash
sudo install -D -m 0755 usr/local/bin/txrx_led.py /usr/local/bin/txrx_led.py
sudo install -D -m 0644 etc/systemd/system/txrx-led.service /etc/systemd/system/txrx-led.service
sudo install -D -m 0755 usr/local/sbin/setup-txrx-led.sh /usr/local/sbin/setup-txrx-led.sh
```

Run the setup script:

```bash
sudo /usr/local/sbin/setup-txrx-led.sh
```

The script:

1. Requires root and checks that the `ip` command is installed.
2. Checks both expected LED paths and their writable `brightness` controls.
3. Looks for an IPv4 default route first, then an IPv6 default route.
4. Offers the detected interface for confirmation when an interactive terminal is available. If no default route is found, it presents a numbered list of non-loopback interfaces for manual selection.
5. Validates that the selected interface still exists and writes `IFACE=<name>` to `/etc/default/txrx-led`.

If a default route is detected but the script has no interactive terminal, it uses that detected interface automatically. If no default route exists and there is no interactive terminal for manual selection, setup stops with an explanatory error.

The setup script does not start or enable the service. Once setup has completed, run:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now txrx-led.service
sudo systemctl status txrx-led.service
```

The systemd unit loads `/etc/default/txrx-led` as an environment file. Run setup successfully before starting the service; if the file is missing, systemd cannot start the unit.

## Changing the interface

Rerun the setup script and select a different interface, or edit the configuration directly:

```bash
sudo nano /etc/default/txrx-led
```

The file contains one setting, for example:

```ini
IFACE=eth0
```

Use the actual interface name detected on the Pi. After changing it, restart the service:

```bash
sudo systemctl restart txrx-led.service
```

## Monitoring and troubleshooting

Check service state:

```bash
sudo systemctl status txrx-led.service
```

Follow its logs:

```bash
sudo journalctl -u txrx-led.service -f
```

If setup reports a missing LED path or brightness control, it stops without writing the interface configuration. Check the reported path and confirm that the expected LED class device is exposed by the running kernel. If the service reports that no interface is configured, run the setup script and then restart the service.

## LED behaviour

- **Green LED:** full brightness while the selected interface's `operstate` is `up`. When RX or TX byte counters increase, the LED is briefly switched off for approximately 30 ms, then returned to its normal link-up state. It is not an off-when-idle activity indicator.
- **Red LED:** pulses for approximately 200 ms when either `rx_dropped` or `tx_dropped` increases. Pulses are rate-limited to at most one per second.
- The first counter sample establishes a baseline, so startup does not create a false traffic or drop event.
- Counter decreases, such as after an interface reset, are treated as a new baseline rather than as packet drops.
- Counters are read while the interface exists even when its link is down. A missing interface is retried.
- Read/write errors are written to the systemd journal.
- On SIGTERM/SIGINT, the monitor attempts to turn the LEDs off and restore their previously active kernel triggers.

## Timing and limitations

- Link-up polling interval: nominally 50 ms.
- Link-down polling interval: 500 ms.
- Missing-interface/error retry interval: 1 second.
- Traffic indication: approximately 30 ms.
- Drop indication: approximately 200 ms, with a one-second minimum interval between pulses.
- The monitor uses Linux `rx_dropped` and `tx_dropped` interface statistics. These counters do not represent every possible network error; `rx_errors` and `tx_errors` are not monitored.
- The first default route returned by `ip` is selected. On systems with multiple default routes, confirm that the proposed interface is the one whose traffic you want to monitor.
- The scripts use Bash, Python 3 and standard Linux utilities; no third-party Python packages are required. Setup and the service run as root because the LED sysfs controls are normally writable only by root.

Hardware behaviour still needs to be confirmed by running the service on the Pi. Passing setup checks confirms the expected sysfs controls are present and writable; it does not prove that the LEDs illuminate as intended.
