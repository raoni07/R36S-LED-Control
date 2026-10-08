#!/usr/bin/env python3
"""
Soy Sauce variant LED service – RK3326 DarkOS RE
Based strictly on provided truth table:

Not charging:
  ≥ 11%     → Off (clean, step 7 style: Red out + 0, Blue in)
  ≤ 10%     → solid Red (step 8 style: Blue in, Red out + 1)

Charging / Full → both high-Z (PMIC control)
"""

import os
import time

CAPACITY_PATH = "/sys/class/power_supply/battery/capacity"
STATUS_PATH   = "/sys/class/power_supply/battery/status"

# GPIO numbers – confirm these are correct for your Soy Sauce board
BLUE_GPIO = "0"     # sysfs number for blue channel
RED_GPIO  = "1"     # sysfs number for red channel

BLUE_DIR  = f"/sys/class/gpio/gpio{BLUE_GPIO}/direction"
BLUE_VAL  = f"/sys/class/gpio/gpio{BLUE_GPIO}/value"
RED_DIR   = f"/sys/class/gpio/gpio{RED_GPIO}/direction"
RED_VAL   = f"/sys/class/gpio/gpio{RED_GPIO}/value"

# State tracking to prevent flicker
prev_capacity = -1
prev_status   = ""
prev_mode     = ""          # "charging", "off", "red", "error"

def export_gpio(pin):
    path = f"/sys/class/gpio/gpio{pin}"
    if not os.path.exists(path):
        try:
            with open("/sys/class/gpio/export", "w") as f:
                f.write(pin)
            time.sleep(0.4)
        except:
            pass

def set_input(pin_dir):
    try:
        with open(pin_dir, "w") as f:
            f.write("in")
    except:
        pass

def set_output_value(pin_dir, pin_val, value):
    try:
        if os.path.exists(pin_dir):
            curr = open(pin_dir).read().strip()
            if curr != "out":
                with open(pin_dir, "w") as f:
                    f.write("out")
        if os.path.exists(pin_val):
            curr_val = int(open(pin_val).read().strip())
            if curr_val != value:
                with open(pin_val, "w") as f:
                    f.write(str(value))
    except:
        pass

def soy_off():
    # Step 7: clean off (Red driven low, Blue floating)
    set_input(BLUE_DIR)
    set_output_value(RED_DIR, RED_VAL, 0)

def soy_red():
    # Step 8: pure red (Red driven high, Blue floating)
    set_input(BLUE_DIR)
    set_output_value(RED_DIR, RED_VAL, 1)

def soy_disable():
    # Both high-Z → PMIC control
    set_input(BLUE_DIR)
    set_input(RED_DIR)

# Initial setup
export_gpio(BLUE_GPIO)
export_gpio(RED_GPIO)
soy_off()           # safe default

while True:
    try:
        cap = int(open(CAPACITY_PATH).read().strip())
        status = open(STATUS_PATH).read().strip()
    except:
        if prev_mode != "error":
            soy_off()
            prev_mode = "error"
        time.sleep(8)
        continue

    # Skip if no change in values
    if cap == prev_capacity and status == prev_status:
        time.sleep(5)
        continue

    prev_capacity = cap
    prev_status = status

    if status in ["Charging", "Full"]:
        new_mode = "charging"
    else:
        if cap >= 11:
            new_mode = "off"
        else:
            new_mode = "red"

    # Only update when mode changes
    if new_mode != prev_mode:
        if new_mode == "charging":
            soy_disable()
        elif new_mode == "off":
            soy_off()
        elif new_mode == "red":
            soy_red()

        prev_mode = new_mode

    time.sleep(5)