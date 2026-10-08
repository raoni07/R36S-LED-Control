# R36S LED Control

A tiny TUI tool for the **R36S** (and clones) running **dArkOS** / **dArkOS-RE** / **dArkOSen** /
**ArkOS**-derived firmwares. Lets you pick how the status LED behaves at low battery —
by device family (Clone, R36S, SoySauce) — or hand control back to the PMIC.

No config files, no logs, no system files touched. Everything lives under
`/roms/tools/`.

---

## Features

- **Variant-aware menu** — Clone, R36S, SoySauce, each with its own set of scripts
- **Human-readable labels** — e.g. `Blue ≥30% | Purple 11-29% | Red ≤10%`
- **One-tap Apply** — copies the chosen script to `/usr/local/bin/batt_life_warning.py`
  and restarts `batt_led.service`
- **Remove LED** — stops the service and deletes the custom script, letting
  the PMIC control the LED again
- **Self-contained** — no `/etc/r36_config.ini`, no `ogage`, no audio, no gamma
- **Gamepad-driven** — uses `gptokeyb` with the firmware's existing keymap

---

## Supported LED behaviors

### Clone
| Option | Behavior |
|---|---|
| Blue / Purple / Red | Blue ≥30% · Purple 11–29% · Red ≤10% |
| Off / Red | Off ≥11% · Red ≤10% |
| Off / Purple / Red | Off ≥30% · Purple 11–29% · Red ≤10% |
| PMIC | No software control |

### R36S
| Option | Behavior |
|---|---|
| Warn 10% | Off ≥11% · Warning LED ≤10% |
| Warn 20% | Off ≥21% · Warning LED ≤20% |
| Warn 30% | Off ≥31% · Warning LED ≤30% |
| PMIC | No software control |

### SoySauce
| Option | Behavior |
|---|---|
| Blue / Pink / Red | Blue ≥30% · Pink 11–29% · Red ≤10% |
| Off / Red | Off ≥11% · Red ≤10% |
| Off / Pink / Red | Off ≥30% · Pink 11–29% · Red ≤10% |
| PMIC | No software control |

---

## Install

Copy the `tools/` folder to your device's ROMs partition:

From https://github.com/southoz/dArkOSRE-R36 
https://github.com/southoz/dArkOSRE-R36/tree/main/files/ROOTFS/usr/local/bin/r36_config/batt_life_warning
https://github.com/southoz/dArkOSRE-R36/blob/main/files/ROOTFS/opt/system/R36%20Control.sh
