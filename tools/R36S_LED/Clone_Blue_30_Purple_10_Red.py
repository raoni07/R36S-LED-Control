#!/usr/bin/env python3
"""
Custom LED service for R36S clone (G80CA / Soy Sauce style):
- ≥ 30% battery only: solid blue
- 11–29% battery only: solid purple
- < 10% battery only: solid red
- Charger plugged in: disable software control (all pins "in", PMIC red may show)
"""

import os
import time

CAPACITY_PATH = "/sys/class/power_supply/battery/capacity"
STATUS_PATH   = "/sys/class/power_supply/battery/status"

BLUE_PIN = "0"      # gpio0 = blue
RED_PIN  = "17"     # gpio17 = red/purple component

BLUE_DIR = f"/sys/class/gpio/gpio{BLUE_PIN}/direction"
RED_DIR  = f"/sys/class/gpio/gpio{RED_PIN}/direction"
BLUE_VAL = f"/sys/class/gpio/gpio{BLUE_PIN}/value"
RED_VAL  = f"/sys/class/gpio/gpio{RED_PIN}/value"

def setup():
    for pin, dir_path, val_path in [(BLUE_PIN, BLUE_DIR, BLUE_VAL), (RED_PIN, RED_DIR, RED_VAL)]:
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

def blue_on():
    try:
        with open(BLUE_DIR, "w") as f:
            f.write("out")
        with open(BLUE_VAL, "w") as f:
            f.write("1")
    except:
        pass

def blue_off():
    try:
        with open(BLUE_DIR, "w") as f:
            f.write("in")
    except:
        pass

def red_on():
    try:
        with open(RED_DIR, "w") as f:
            f.write("out")
        with open(RED_VAL, "w") as f:
            f.write("1")
    except:
        pass

def red_off():
    try:
        with open(RED_DIR, "w") as f:
            f.write("in")
    except:
        pass

# Start off
blue_off()
red_off()

while True:
    try:
        cap = int(open(CAPACITY_PATH).read().strip())
        status = open(STATUS_PATH).read().strip()
    except:
        blue_off()
        red_off()
        time.sleep(10)
        continue

    if status in ["Charging", "Full"]:
        # Disable software control when charger plugged in
        blue_off()
        red_off()
    else:
        if cap >= 30:
            blue_on()
            red_off()           # solid blue
        elif cap >= 11:
            blue_on()
            red_on()            # solid purple
        else:
            blue_off()
            red_on()            # solid red

    time.sleep(5)