#!/usr/bin/env python3
"""
LED warning service - your requested behavior:
≥ 10% battery only : off (all pins "in")
< 10% battery only : solid red (gpio0 "in", gpio17 "out" + "1")
Charger plugged in : disable software control (all "in")
"""

import os
import time

CAPACITY_PATH = "/sys/class/power_supply/battery/capacity"
STATUS_PATH   = "/sys/class/power_supply/battery/status"

BLUE_PIN = "0"      # gpio0 = blue (set "in" to kill blue bleed)
RED_PIN  = "17"     # gpio17 = red/purple (set "out" + "1" for red)

BLUE_DIR = f"/sys/class/gpio/gpio{BLUE_PIN}/direction"
RED_DIR  = f"/sys/class/gpio/gpio{RED_PIN}/direction"
RED_VAL  = f"/sys/class/gpio/gpio{RED_PIN}/value"

def setup():
    for pin, dir_path in [(BLUE_PIN, BLUE_DIR), (RED_PIN, RED_DIR)]:
        path = f"/sys/class/gpio/gpio{pin}"
        if not os.path.exists(path):
            try:
                with open("/sys/class/gpio/export", "w") as f:
                    f.write(str(pin))
                time.sleep(0.3)
            except:
                pass
        if os.path.exists(dir_path):
            try:
                with open(dir_path, "w") as f:
                    f.write("out")
            except:
                pass

setup()

def all_off():
    """All pins 'in' = off from software side"""
    try:
        with open(BLUE_DIR, "w") as f:
            f.write("in")
        with open(RED_DIR, "w") as f:
            f.write("in")
    except:
        pass

def solid_red():
    """Pure red: kill blue with gpio0 'in', enable red with gpio17 'out' + '1'"""
    try:
        with open(BLUE_DIR, "w") as f:
            f.write("in")  # blue off
        with open(RED_DIR, "w") as f:
            f.write("out")
        with open(RED_VAL, "w") as f:
            f.write("1")   # red on
    except:
        pass

# Start off
all_off()

while True:
    try:
        cap = int(open(CAPACITY_PATH).read().strip())
        status = open(STATUS_PATH).read().strip()
    except:
        all_off()
        time.sleep(10)
        continue

    if status in ["Charging", "Full"]:
        all_off()  # charger plugged → disable software control
    else:
        if cap >= 10:
            all_off()      # off above 10%
        else:
            solid_red()    # solid red below 10%

    time.sleep(5)