#!/usr/bin/env python3
"""
Genuine R36S battery warning LED service – dArkOS RE
GPIO 77 (GPIO2 PB5): 1 = LED on (red/orange warning), 0 = off
Attempts pin reset on start/failure to avoid PMIC locks.
"""

import os
import time

CAPACITY_PATH = "/sys/class/power_supply/battery/capacity"
STATUS_PATH   = "/sys/class/power_supply/battery/status"

LED_GPIO = 77
LED_DIR  = f"/sys/class/gpio/gpio{LED_GPIO}/direction"
LED_VAL  = f"/sys/class/gpio/gpio{LED_GPIO}/value"

def reset_pin():
    try:
        os.system(f"echo {LED_GPIO} > /sys/class/gpio/unexport 2>/dev/null")
        time.sleep(0.5)
        os.system(f"echo {LED_GPIO} > /sys/class/gpio/export")
        time.sleep(0.5)
        with open(LED_DIR, "w") as f:
            f.write("out")
        print("Pin reset successful")
    except Exception as e:
        print(f"Pin reset failed: {e}")

def set_led(on: bool):
    try:
        value = "1" if on else "0"
        with open(LED_VAL, "w") as f:
            f.write(value)
        print(f"Set LED to {'ON' if on else 'OFF'} (value {value})")
    except Exception as e:
        print(f"Set failed: {e}")
        reset_pin()  # Retry reset on error
        time.sleep(1)
        try:
            with open(LED_VAL, "w") as f:
                f.write(value)
            print("Retry succeeded")
        except:
            print("Retry also failed - likely DTB/PMIC lock")

def release_led():
    try:
        with open(LED_DIR, "w") as f:
            f.write("in")
        print("Released to PMIC")
    except:
        pass

# Initial reset
reset_pin()
release_led()  # Start safe

prev_cap = -1
prev_status = ""
prev_mode = ""

while True:
    try:
        cap = int(open(CAPACITY_PATH).read().strip())
        status = open(STATUS_PATH).read().strip()
    except:
        release_led()
        time.sleep(10)
        continue

    if cap == prev_cap and status == prev_status:
        time.sleep(5)
        continue

    prev_cap = cap
    prev_status = status

    if status in ["Charging", "Full"]:
        new_mode = "charging"
        release_led()
    else:
        new_mode = "warning" if cap <= 10 else "off"
        set_led(on=(new_mode == "warning"))

    prev_mode = new_mode
    time.sleep(5)