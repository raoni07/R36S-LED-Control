#!/usr/bin/env python3
import glob
import json
import os
import signal
import sys
import time

GPIO_ROOT = os.environ.get("BATT_LED_GPIO_ROOT", "/sys/class/gpio")
PS_ROOT = os.environ.get("BATT_LED_PS_ROOT", "/sys/class/power_supply")
POLL = float(os.environ.get("BATT_LED_POLL", "3"))
PLUGGED = {"Charging", "Full", "Not charging"}
KNOWN_PINS = (0, 1, 17, 77)


HARDWARE = {
    "clone": {
        "pins": [0, 17],
        "colors": {
            "off":    {0: "in", 17: "in"},
            "blue":   {0: 1,    17: "in"},
            "red":    {0: "in", 17: 1},
            "purple": {0: 1,    17: 1},
        },
    },
    "soysauce": {
        "pins": [0, 1],
        "colors": {
            "off":  {0: "in", 1: 0},
            "blue": {0: 0,    1: "in"},
            "red":  {0: "in", 1: 1},
            "pink": {0: 0,    1: 1},
        },
    },
    "r36s": {
        "pins": [77],
        "colors": {"off": {77: 0}, "red": {77: 1}},
    },
}
ALIASES = {"purple": "pink", "pink": "purple"}


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def _write(path, value):
    try:
        with open(path, "w") as f:
            f.write(str(value))
        return True
    except OSError:
        return False


class Led:
    def __init__(self, pins, colors):
        self.pins = list(pins)
        self.colors = colors
        self.current = None
        self._warned = set()

    def _dir(self, pin):
        return "%s/gpio%s" % (GPIO_ROOT, pin)

    def _export(self, pin):
        d = self._dir(pin)
        if os.path.isdir(d):
            return True
        _write(GPIO_ROOT + "/export", pin)
        for _ in range(20):
            if os.path.isdir(d):
                return True
            time.sleep(0.05)
        if pin not in self._warned:
            log("gpio%s: export falhou (pino reservado pelo DTB?)" % pin)
            self._warned.add(pin)
        return False

    def _apply_pin(self, pin, state):
        if not self._export(pin):
            return
        d = self._dir(pin)
        if state == "in":
            _write(d + "/direction", "in")
        elif not _write(d + "/direction", "high" if state else "low"):
            if _write(d + "/direction", "out"):
                _write(d + "/value", int(state))

    def resolve(self, name):
        if name in self.colors:
            return name
        if ALIASES.get(name) in self.colors:
            return ALIASES[name]
        if name not in self._warned:
            log("cor '%s' inexistente neste perfil; usando fallback" % name)
            self._warned.add(name)
        return "red" if "red" in self.colors else next(iter(self.colors))

    def set_color(self, name):
        name = self.resolve(name)
        if name == self.current:
            return
        state = self.colors[name]
        for pin in self.pins:
            self._apply_pin(pin, state.get(pin, "in"))
        self.current = name

    def release(self):
        if self.current == "<released>":
            return
        for pin in self.pins:
            if os.path.isdir(self._dir(pin)):
                _write(self._dir(pin) + "/direction", "in")
        self.current = "<released>"


def find_battery():
    for d in sorted(glob.glob(PS_ROOT + "/*")):
        if os.path.isfile(d + "/capacity"):
            try:
                with open(d + "/type") as f:
                    if f.read().strip() != "Battery":
                        continue
            except OSError:
                pass
            return d
    return PS_ROOT + "/battery"


def read_battery(d):
    try:
        with open(d + "/capacity") as f:
            cap = int(f.read().strip())
        with open(d + "/status") as f:
            status = f.read().strip()
        return cap, status
    except (OSError, ValueError):
        return None, None


def pick_zone(cap, zones, cur, hyst):
    target = next((i for i, z in enumerate(zones) if cap >= z[0]), len(zones) - 1)
    if cur is None or target >= cur:
        return target
    for i in range(target, cur):
        if cap >= zones[i][0] + hyst:
            return i
    return cur


def _install_term_handlers():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))


def run(hardware=None, zones=None, pins=None, colors=None, hysteresis=2, blink_period=1.0):
    hw = HARDWARE.get(hardware, {}) if hardware else {}
    pins = list(pins if pins is not None else hw.get("pins", []))
    colors = colors if colors is not None else hw.get("colors", {})
    if not pins or not colors or not zones:
        sys.exit("perfil sem pins/colors/zones")
    zones = sorted(((int(m), c) for m, c in zones), key=lambda z: -z[0])

    led = Led(pins, colors)
    _install_term_handlers()
    batt = find_battery()
    zone_idx, active = None, None
    phase, last_toggle, last_poll = 0, 0.0, -1e9
    try:
        while True:
            now = time.monotonic()
            if now - last_poll >= POLL:
                last_poll = now
                cap, status = read_battery(batt)
                if cap is None or status in PLUGGED:
                    zone_idx, active = None, None
                else:
                    zone_idx = pick_zone(cap, zones, zone_idx, hysteresis)
                    c = zones[zone_idx][1]
                    active = c.split("+") if "+" in c else c

            if active is None:
                led.release()
            elif isinstance(active, list):
                if now - last_toggle >= blink_period:
                    phase ^= 1
                    last_toggle = now
                    led.set_color(active[phase])
            else:
                led.set_color(active)
            time.sleep(0.2 if isinstance(active, list) else 1.0)
    finally:
        led.release()


def release_known():
    for pin in KNOWN_PINS:
        d = "%s/gpio%s" % (GPIO_ROOT, pin)
        if os.path.isdir(d):
            _write(d + "/direction", "in")


def park():
    _install_term_handlers()
    release_known()
    while True:
        time.sleep(300)


COLOR_ORDER = ["blue", "red", "purple", "green", "orange", "white", "off"]


def _parse_obs(path, pins):
    table = {}
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) != 2:
                continue
            key, color = parts
            if key == "-":
                vec = ("in",) * len(pins)
            else:
                d = {}
                for item in key.split(","):
                    p, s = item.split("=")
                    d[int(p)] = int(s)
                if any(p not in pins for p in d):
                    continue
                vec = tuple(d.get(p, "in") for p in pins)
            table[vec] = color
    return table


def solve(path, pins_arg, need_arg=None):
    pins = [int(p) for p in pins_arg.split(",") if p != ""]
    table = _parse_obs(path, pins)
    best = {}
    for vec, color in sorted(table.items(), key=lambda kv: (-sum(s != "in" for s in kv[0]), str(kv[0]))):
        best.setdefault(color, vec)
    if need_arg is None:
        for c in COLOR_ORDER:
            if c in best:
                print(c)
        return
    for c in need_arg.split(","):
        if c not in best:
            sys.exit("cor não observada: " + c)
        st = ", ".join("%d: %s" % (p, json.dumps(s)) for p, s in zip(pins, best[c]))
        print('        "%s": {%s},' % (c, st))


if __name__ == "__main__":
    a = sys.argv[1:]
    if "--release" in a:
        release_known()
    elif "--solve" in a:
        opt = lambda n: a[a.index(n) + 1] if n in a else None
        solve(opt("--solve"), opt("--pins") or "", opt("--need"))
    else:
        sys.exit(1)
