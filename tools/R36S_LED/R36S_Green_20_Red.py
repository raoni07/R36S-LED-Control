#!/usr/bin/env python3
import os, sys
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import batt_led_core as core

core.run("r36s", zones=[(21, "off"), (0, "red")])
