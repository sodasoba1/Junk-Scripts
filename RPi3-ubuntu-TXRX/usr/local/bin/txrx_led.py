#!/usr/bin/env python3
import time
import os

# Configuration
IFACE = "ADD YOUR INTERFACE NAME HERE"
LED_GREEN = "/sys/class/leds/ACT/"
LED_RED = "/sys/class/leds/PWR/"

# Network statistics paths
RX_BYTES = f"/sys/class/net/{IFACE}/statistics/rx_bytes"
TX_BYTES = f"/sys/class/net/{IFACE}/statistics/tx_bytes"
RX_DROPPED = f"/sys/class/net/{IFACE}/statistics/rx_dropped"
TX_DROPPED = f"/sys/class/net/{IFACE}/statistics/tx_dropped"
OPERSTATE = f"/sys/class/net/{IFACE}/operstate"

# Debounce for red LED
ERROR_BLINK_INTERVAL = 1.0  # seconds between blinks

# Initialize LEDs (ACT=GREEN | PWR=RED)
for led in [LED_GREEN, LED_RED]:
    try:
        with open(led + "trigger", "w") as f:
            f.write("none")
        with open(led + "brightness", "w") as f:
            f.write("0")
    except Exception:
        pass

# Initialize counters
last_rx = 0
last_tx = 0
last_rx_drop = 0
last_tx_drop = 0
last_error_blink_time = 0

# Wait a few seconds for the interface to appear at boot
time.sleep(5)

# Main loop
while True:
    try:
        # Skip if interface is missing
        if not os.path.exists(OPERSTATE):
            time.sleep(1)
            continue

        # Link status
        with open(OPERSTATE) as f:
            state = f.read().strip()

        # Green LED logic
        if state != "up":
            # Link down → green LED off
            with open(LED_GREEN + "brightness", "w") as f:
                f.write("0")
            time.sleep(0.5)
            continue
        else:
            # Link up → normally on
            with open(LED_GREEN + "brightness", "w") as f:
                f.write("1")

        # Traffic activity → quick flicker for RX/TX
        with open(RX_BYTES) as f:
            rx = int(f.read())
        with open(TX_BYTES) as f:
            tx = int(f.read())

        if rx != last_rx or tx != last_tx:
            # Quick green blink
            with open(LED_GREEN + "brightness", "w") as f:
                f.write("0")
            time.sleep(0.03)
            with open(LED_GREEN + "brightness", "w") as f:
                f.write("1")

        last_rx = rx
        last_tx = tx

        # Red LED logic for dropped packets (debounced)
        with open(RX_DROPPED) as f:
            rx_drop = int(f.read())
        with open(TX_DROPPED) as f:
            tx_drop = int(f.read())

        current_time = time.time()
        if (rx_drop != last_rx_drop or tx_drop != last_tx_drop) and (current_time - last_error_blink_time >= ERROR_BLINK_INTERVAL):
            # Blink red LED briefly
            with open(LED_RED + "brightness", "w") as f:
                f.write("1")
            time.sleep(0.2)
            with open(LED_RED + "brightness", "w") as f:
                f.write("0")
            last_error_blink_time = current_time

        last_rx_drop = rx_drop
        last_tx_drop = tx_drop

        time.sleep(0.05)

    except Exception:
        # Safe fallback: turn off LEDs if something fails
        try:
            with open(LED_GREEN + "brightness", "w") as f:
                f.write("0")
            with open(LED_RED + "brightness", "w") as f:
                f.write("0")
        except Exception:
            pass
        time.sleep(1)
