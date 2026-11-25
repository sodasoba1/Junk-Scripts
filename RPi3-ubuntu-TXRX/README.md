# Raspberry Pi 3 Ubuntu TX/RX LED Indicator

This folder contains a Python service that uses the Raspberry Pi status LEDs to indicate network link state, traffic and interface packet drops.

## Files

| File | Purpose |
|---|---|
| `usr/local/sbin/setup-txrx-led.sh` | First-run setup. Detects the default-route network interface, checks the LED sysfs controls and writes the selected interface to `/etc/default/txrx-led`. |
| `usr/local/bin/txrx_led.py` | Monitors link state and RX/TX byte/drop counters. Reads the interface from the systemd environment file. |
| `etc/systemd/system/txrx-led.service` | Starts the monitor at boot and logs output to the systemd journal. |

## First-run detection

The setup script is configured for the LED paths confirmed on this Raspberry Pi 3 Ubuntu installation:

- Green: `/sys/class/leds/ACT`
- Red: `/sys/class/leds/PWR`

It checks that each LED directory exists and exposes a writable `brightness` control. It does not change LED brightness or triggers during setup.

For the network interface, it checks the kernel's default route and offers that interface as the default selection. You can accept it or choose another detected non-loopback interface. The chosen name is saved in `/etc/default/txrx-led`.

If either LED path or its brightness control is missing, setup stops with an error rather than configuring an incomplete service.

## Installation

From the repository's `RPi3-ubuntu-TXRX` directory, install the three files:

```bash
sudo install -D -m 0755 usr/local/bin/txrx_led.py /usr/local/bin/txrx_led.py
sudo install -D -m 0644 etc/systemd/system/txrx-led.service /etc/systemd/system/txrx-led.service
sudo install -D -m 0755 usr/local/sbin/setup-txrx-led.sh /usr/local/sbin/setup-txrx-led.sh
```

Run first-run setup once:

```bash
sudo /usr/local/sbin/setup-txrx-led.sh
```

Then enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now txrx-led.service
sudo systemctl status txrx-led.service
```

If you later want to change the monitored interface, rerun the setup script or edit `/etc/default/txrx-led`, then restart the service:

```bash
sudo systemctl restart txrx-led.service
```

View runtime messages and errors with:

```bash
sudo journalctl -u txrx-led.service -f
```

The scripts use only standard Bash, Python and Linux utilities; no third-party Python packages are required. Run setup and the service as root because the LED sysfs controls are normally writable only by root.

## LED behaviour

- **Green LED:** solid on while the configured interface's `operstate` is `up`; a traffic-counter increase briefly turns it off for approximately 30 ms. It is not an off-when-idle activity LED.
- **Red LED:** pulses for approximately 200 ms when either `rx_dropped` or `tx_dropped` increases. Pulses are rate-limited to at most one per second.
- The first counter sample establishes a baseline, avoiding a false activity/drop event at startup. Counter decreases (for example, after an interface reset) establish a new baseline and are not reported as drops.
- Counters are sampled while the interface exists, including while its link is down.
- Missing interfaces are retried. Read/write failures are logged to the systemd journal.
- On SIGTERM/SIGINT, the monitor turns the LEDs off and restores their previously active kernel triggers when available.
- `rx_dropped` and `tx_dropped` are specific Linux interface statistics. They do not represent every possible network error; this monitor does not read `rx_errors` or `tx_errors`.
- Polling is nominally every 50 ms while the link is up. A traffic or drop indication temporarily adds its blink duration to that cycle.
