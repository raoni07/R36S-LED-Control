# R36S LED Control

A tiny TUI tool for the **R36S** (and clones) running **dArkOS** / **dArkOS-RE** / **dArkOSen** /
**ArkOS**-derived firmwares. Lets you pick how the status LED behaves at low battery,
by device family (Clone, R36S, SoySauce) or hand control back to the PMIC.

No config files, no logs, no system files touched. Everything lives under
`/roms/tools/`.

---

## Features

- **Variant-aware menu:** Clone, R36S, SoySauce, each with its own set of profiles.
- **Labels:** e.g., `Blue >=30% | Purple 11-29% | Red <=10%`.
- **One-tap Apply:** Copies the chosen script to `/usr/local/bin/batt_life_warning.py` and restarts `batt_led.service`.
- **Diagnostic wizard:** Tests the GPIO, asks what you see, and generates a custom profile for your specific device.
- **Custom profiles:** Generated profiles are saved and can be managed or deleted from inside the tool.
- **Remove LED:** Stops the service and deletes the installed script, letting the PMIC control the LED again.
- **Self-contained:** No `/etc/r36_config.ini`, no `ogage`, no audio, no gamma.
- **Gamepad-driven:** Uses `gptokeyb` with the firmware's existing keymap.

---

## Supported LED behaviors

### Clone
| Options |
|---|
| Red <=10% \| Purple 11-29% \| Blue >=30% |
| Red <=10% \| Off >=11% |
| Red <=10% \| Purple 11-29% \| Off >=30% |
| No software control |

### R36S
| Options |
|---|
| Warning LED <=10% \| Off >=11% |
| Warning LED <=20% \| Off >=21% |
| Warning LED <=30% \| Off >=31% |
| No software control |

### SoySauce
| Options |
|---|
| Red <=10% \| Pink 11-29% \| Blue >=30% |
| Red <=10% \| Off >=11% |
| Red <=10% \| Pink 11-29% \| Off >=30% |
| No software control |

### Custom
| Options |
|---|
| Generated profiles created and saved by the diagnostic wizard |

---

> [!NOTE]
> **Some devices cannot turn the LED off.**
>
> On a few R36S revisions (notably the V21 and some SoySauce units),
> the bicolor LED is wired directly to the PMIC and only exposes two
> software-controllable states, one color or the other. There is no
> high-impedance or "off" state available through the GPIO.
>
> When this happens, `input` (high-Z) floats the pin and an internal
> pull-up drives it to the same level as `value=1`, so the LED simply
> switches to the other color instead of turning off.
>
> The diagnostic wizard detects this case automatically and tells you:
> *"This LED cannot be turned off. Only color changes will be available."*
> In that situation, the wizard only offers color-to-color presets
> (e.g., `Green` above the threshold, `Red` below).
>
> Turning the LED off completely on these units requires a hardware
> modification (removing the LED, cutting its trace, or adding a
> resistor). It is not something any firmware or script can do.

---

## Install

Copy the .sh or script to your handheld's `/roms/tools/` directory.

---

## Screenshots

| Main Menu | Clone Submenu |
| :---: | :---: |
| <a href="https://github.com/user-attachments/assets/ed0d6d0d-edb8-4731-b4c4-fcc82f6becdf"><img src="https://github.com/user-attachments/assets/ed0d6d0d-edb8-4731-b4c4-fcc82f6becdf" width="300" alt="Main Menu"></a> | <a href="https://github.com/user-attachments/assets/bf9b2975-7927-49f5-aa5b-9ce370a3f654"><img src="https://github.com/user-attachments/assets/bf9b2975-7927-49f5-aa5b-9ce370a3f654" width="300" alt="Clone Menu"></a> |
| **Diagnostic Wizard** | **Custom Profile Configuration** |
| <a href="https://github.com/user-attachments/assets/258591ec-b521-4843-bac4-c353e8a9e2ef"><img src="https://github.com/user-attachments/assets/258591ec-b521-4843-bac4-c353e8a9e2ef" width="300" alt="Diagnostic Wizard"></a> | <a href="https://github.com/user-attachments/assets/c13638dc-7e1a-4ec8-981d-d8019c44126c"><img src="https://github.com/user-attachments/assets/c13638dc-7e1a-4ec8-981d-d8019c44126c" width="300" alt="Custom Profile"></a> |

---

## Credits & Acknowledgments

Base LED scripts adapted from **southoz**:
- [southoz/dArkOSRE-R36](https://github.com/southoz/dArkOSRE-R36)
- [batt_life_warning scripts](https://github.com/southoz/dArkOSRE-R36/tree/main/files/ROOTFS/usr/local/bin/r36_config/batt_life_warning)
- [R36 Control.sh](https://github.com/southoz/dArkOSRE-R36/blob/main/files/ROOTFS/opt/system/R36%20Control.sh)