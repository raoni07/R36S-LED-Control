#!/usr/bin/env python3
"""
LED warning service - final requested behavior:
≥ 30% battery only : off
11–29% battery only : solid purple
< 10% battery only  : solid red
Charger plugged in  : disable software control (all "in", let PMIC handle red)
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

def disable_control():
    blue_off()
    red_off()

# Start disabled
disable_control()

while True:
    try:
        cap = int(open(CAPACITY_PATH).read().strip())
        status = open(STATUS_PATH).read().strip()
    except:
        disable_control()
        time.sleep(10)
        continue

    if status in ["Charging", "Full"]:
        disable_control()  # charger plugged in → software off, PMIC red can show
    else:
        if cap >= 30:
            disable_control()  # off above 30%
        elif cap >= 11:
            blue_on()
            red_on()           # purple solid
        else:
            blue_off()
            red_on()           # solid red below 10%

    time.sleep(5)