#!/usr/bin/env python3
"""Use Raspberry Pi status LEDs as a network activity/drop indicator.

Green: solid while the configured interface is up; briefly interrupted by
network traffic. Red: brief pulse when RX/TX dropped counters increase.
"""
import logging
import os
import signal
import threading
import time
from pathlib import Path

# Configuration: replace this with the interface shown by `ip -br link`.
IFACE = "ADD YOUR INTERFACE NAME HERE"
LED_GREEN = Path("/sys/class/leds/ACT")
LED_RED = Path("/sys/class/leds/PWR")

POLL_INTERVAL = 0.05
LINK_DOWN_INTERVAL = 0.5
MISSING_INTERFACE_INTERVAL = 1.0
TRAFFIC_BLINK_SECONDS = 0.03
DROP_BLINK_SECONDS = 0.2
DROP_BLINK_INTERVAL = 1.0

LOG = logging.getLogger("txrx-led")
STOP = threading.Event()


def stop_service(signum, _frame):
    """Allow systemd to stop cleanly and restore the LEDs."""
    LOG.info("Received signal %s; stopping", signum)
    STOP.set()


class Led:
    """Small wrapper around a Linux LED class device."""

    def __init__(self, path: Path, label: str):
        self.path = path
        self.label = label
        self.original_trigger = None
        self.available = path.is_dir()

        if not self.available:
            LOG.warning("%s LED path is unavailable: %s", label, path)
            return

        trigger_file = path / "trigger"
        try:
            if trigger_file.exists():
                active = trigger_file.read_text().strip()
                # The kernel marks the active trigger with square brackets.
                self.original_trigger = next(
                    (item[1:-1] for item in active.split() if item.startswith("[") and item.endswith("]")),
                    None,
                )
                trigger_file.write_text("none")
            self.set(0)
        except OSError:
            LOG.exception("Could not initialise %s LED at %s", label, path)
            self.available = False

    def set(self, value: int):
        if not self.available:
            return
        try:
            (self.path / "brightness").write_text(str(value))
        except OSError:
            LOG.exception("Could not set %s LED brightness", self.label)
            self.available = False

    def restore(self):
        if not self.path.is_dir():
            return
        try:
            # Leave the LED dark before returning control to its old trigger.
            brightness = self.path / "brightness"
            if brightness.exists():
                brightness.write_text("0")
            if self.original_trigger is not None:
                (self.path / "trigger").write_text(self.original_trigger)
        except OSError:
            LOG.exception("Could not restore %s LED", self.label)


def read_counter(path: Path) -> int:
    return int(path.read_text().strip())


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    if not IFACE or IFACE == "ADD YOUR INTERFACE NAME HERE":
        LOG.error("Set IFACE in %s to the real network interface name (see: ip -br link)", __file__)
        return 2

    green = Led(LED_GREEN, "green")
    red = Led(LED_RED, "red")

    base = Path("/sys/class/net") / IFACE
    operstate = base / "operstate"
    stats = base / "statistics"
    rx_bytes_path = stats / "rx_bytes"
    tx_bytes_path = stats / "tx_bytes"
    rx_dropped_path = stats / "rx_dropped"
    tx_dropped_path = stats / "tx_dropped"

    previous = None
    last_drop_blink = float("-inf")
    LOG.info("Monitoring interface %s; green=%s red=%s", IFACE, LED_GREEN, LED_RED)

    try:
        while not STOP.is_set():
            try:
                if not operstate.exists():
                    green.set(0)
                    if previous is not None:
                        LOG.warning("Interface %s is not present; waiting", IFACE)
                    previous = None
                    STOP.wait(MISSING_INTERFACE_INTERVAL)
                    continue

                state = operstate.read_text().strip()
                current = (
                    read_counter(rx_bytes_path),
                    read_counter(tx_bytes_path),
                    read_counter(rx_dropped_path),
                    read_counter(tx_dropped_path),
                )

                # First sample establishes a baseline; it is not an event.
                if previous is None:
                    previous = current
                else:
                    traffic_increased = current[0] > previous[0] or current[1] > previous[1]
                    drops_increased = current[2] > previous[2] or current[3] > previous[3]

                    if drops_increased and time.monotonic() - last_drop_blink >= DROP_BLINK_INTERVAL:
                        red.set(1)
                        STOP.wait(DROP_BLINK_SECONDS)
                        red.set(0)
                        last_drop_blink = time.monotonic()

                    if state == "up" and traffic_increased and not STOP.is_set():
                        green.set(0)
                        STOP.wait(TRAFFIC_BLINK_SECONDS)
                        if not STOP.is_set():
                            green.set(1)

                    # Counter resets are treated as a new baseline, not as drops.
                    previous = current

                if state == "up":
                    # Restore the normal connected indication after a traffic blink.
                    green.set(1)
                    STOP.wait(POLL_INTERVAL)
                else:
                    green.set(0)
                    STOP.wait(LINK_DOWN_INTERVAL)

            except (OSError, ValueError) as exc:
                LOG.exception("Unable to read interface/LED state: %s", exc)
                green.set(0)
                red.set(0)
                previous = None
                STOP.wait(MISSING_INTERFACE_INTERVAL)

    finally:
        green.restore()
        red.restore()
        LOG.info("LED monitor stopped")

    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop_service)
    signal.signal(signal.SIGINT, stop_service)
    raise SystemExit(main())
