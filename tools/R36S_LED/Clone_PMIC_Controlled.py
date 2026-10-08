#!/usr/bin/env python3
"""
Genuine R36S – pure NOP service
Does absolutely nothing after starting.
Exists only to occupy the batt_led.service slot and do zero GPIO/LED interference.
PMIC has full control from the beginning.
"""

import time

# No imports, no GPIO, no nothing

# Optional: one-time message so you know the service started
print("NOP service started – doing literally nothing. PMIC owns the LED.")

# Forever empty loop – ultra low CPU
while True:
    time.sleep(300)  # 5 minutes – basically zero activity