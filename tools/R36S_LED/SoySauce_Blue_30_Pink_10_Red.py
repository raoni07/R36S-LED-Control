#!/usr/bin/env python3
"""
Soy Sauce variant LED service – RK3326 dArkOS RE
Based strictly on provided truth table:
  ≥ 30% (not charging) → solid Blue
  11–29%               → solid Pink
  ≤ 10%                → solid Red
  Charging / Full      → both high-Z (PMIC control)
"""

import os
import time

CAPACITY_PATH = "/sys/class/power_supply/battery/capacity"
STATUS_PATH   = "/sys/class/power_supply/battery/status"

# GPIO numbers – CHANGE THESE if different on your Soy Sauce board
BLUE_GPIO = "0"     # sysfs number for the blue channel
RED_GPIO  = "1"     # sysfs number for the red channel

BLUE_DIR  = f"/sys/class/gpio/gpio{BLUE_GPIO}/direction"
BLUE_VAL  = f"/sys/class/gpio/gpio{BLUE_GPIO}/value"
RED_DIR   = f"/sys/class/gpio/gpio{RED_GPIO}/direction"
RED_VAL   = f"/sys/class/gpio/gpio{RED_GPIO}/value"

# State tracking to prevent flicker
prev_capacity = -1
prev_status   = ""
prev_mode     = ""          # "charging", "blue", "pink", "red", "error"

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
        # Set direction only if not already out
        if os.path.exists(pin_dir):
            curr = open(pin_dir).read().strip()
            if curr != "out":
                with open(pin_dir, "w") as f:
                    f.write("out")
        # Write value only if different
        if os.path.exists(pin_val):
            curr_val = int(open(pin_val).read().strip())
            if curr_val != value:
                with open(pin_val, "w") as f:
                    f.write(str(value))
    except:
        pass

def soy_off():
    # Step 7 – clean off, one pin driven
    set_input(BLUE_DIR)
    set_output_value(RED_DIR, RED_VAL, 0)

def soy_blue():
    # Step 5 – most reliable blue
    set_output_value(BLUE_DIR, BLUE_VAL, 0)
    set_input(RED_DIR)

def soy_pink():
    # Step 2 – clearest pink
    set_output_value(BLUE_DIR, BLUE_VAL, 0)
    set_output_value(RED_DIR, RED_VAL, 1)

def soy_red():
    # Step 8 – only reliable pure red
    set_input(BLUE_DIR)
    set_output_value(RED_DIR, RED_VAL, 1)

def soy_disable():
    # Both high-Z – let PMIC handle (usually red when charging)
    set_input(BLUE_DIR)
    set_input(RED_DIR)

# One-time setup
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

    # Skip logic if values unchanged
    if cap == prev_capacity and status == prev_status:
        time.sleep(5)
        continue

    prev_capacity = cap
    prev_status = status

    if status in ["Charging", "Full"]:
        new_mode = "charging"
    else:
        if cap >= 30:
            new_mode = "blue"
        elif cap >= 11:
            new_mode = "pink"
        else:
            new_mode = "red"

    # Only act when mode actually changes
    if new_mode != prev_mode:
        if new_mode == "charging":
            soy_disable()
        elif new_mode == "blue":
            soy_blue()
        elif new_mode == "pink":
            soy_pink()
        elif new_mode == "red":
            soy_red()

        prev_mode = new_mode

    time.sleep(5)