#!/bin/bash
# R36S LED Control v0.3
# Based on R36 Control.sh by southoz (dArkOSRE-R36)
# https://github.com/southoz/dArkOSRE-R36

sudo chmod 666 /dev/tty1
reset

printf "\e[?25l" > /dev/tty1
dialog --clear

WIDTH=58
HEIGHT=18
GPIO_PIN=77

sudo setfont /usr/share/consolefonts/Lat15-TerminusBold20x10.psf.gz 2>/dev/null

pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
printf "\033c" > /dev/tty1
printf "Starting R36S LED Control..." > /dev/tty1

SCRIPT_DIR="/roms/tools/R36S_LED"
TARGET_SCRIPT="/usr/local/bin/batt_life_warning.py"
SERVICE="batt_led.service"

detect_model() {
  local m=""
  for f in /proc/device-tree/model /sys/firmware/devicetree/base/model; do
    if [ -f "$f" ]; then
      m=$(tr -d '\0' < "$f" 2>/dev/null)
      break
    fi
  done
  if [ -z "$m" ]; then
    for f in /proc/device-tree/compatible /sys/firmware/devicetree/base/compatible; do
      if [ -f "$f" ]; then
        m=$(tr '\0' ' ' < "$f" 2>/dev/null | awk '{print $1}')
        break
      fi
    done
  fi
  [ -z "$m" ] && m="Unknown"
  echo "$m"
}

pretty_name() {
  case "$1" in
    Clone_Blue_30_Purple_10_Red.py)   echo "Blue >=30%  |  Purple 11-29%  |  Red <=10%" ;;
    Clone_Off_10_Red.py)              echo "Off >=11%  |  Red <=10%" ;;
    Clone_Off_30_Purple_10_Red.py)    echo "Off >=30%  |  Purple 11-29%  |  Red <=10%" ;;
    Clone_PMIC_Controlled.py)         echo "PMIC controls LED (no software)" ;;
    R36S_Green_10_Red.py)             echo "Off >=11%  |  Warning LED <=10%" ;;
    R36S_Green_20_Red.py)             echo "Off >=21%  |  Warning LED <=20%" ;;
    R36S_Green_30_Red.py)             echo "Off >=31%  |  Warning LED <=30%" ;;
    R36S_PMIC_Controlled.py)          echo "PMIC controls LED (no software)" ;;
    SoySauce_Blue_30_Pink_10_Red.py)  echo "Blue >=30%  |  Pink 11-29%  |  Red <=10%" ;;
    SoySauce_Off_10_Red.py)           echo "Off >=11%  |  Red <=10%" ;;
    SoySauce_Off_30_Pink_10_Red.py)   echo "Off >=30%  |  Pink 11-29%  |  Red <=10%" ;;
    SoySauce_PMIC_Controlled.py)      echo "PMIC controls LED (no software)" ;;
    Custom_*.py)
      local b="${1%.py}"; b="${b#Custom_}"
      local thr ok low
      thr=$(echo "$b" | cut -d_ -f1)
      ok=$(echo "$b"  | cut -d_ -f2)
      low=$(echo "$b" | cut -d_ -f4)
      echo "Th ${thr}%  |  ${ok}  ->  ${low}"
      ;;
    *)                                echo "$1" ;;
  esac
}

short_name() {
  case "$1" in
    Clone_Blue_30_Purple_10_Red)  echo "Clone - Blue/Purple/Red" ;;
    Clone_Off_10_Red)             echo "Clone - Off/Red" ;;
    Clone_Off_30_Purple_10_Red)   echo "Clone - Off/Purple/Red" ;;
    Clone_PMIC_Controlled)        echo "Clone - PMIC" ;;
    R36S_Green_10_Red)            echo "R36S - Warn 10%" ;;
    R36S_Green_20_Red)            echo "R36S - Warn 20%" ;;
    R36S_Green_30_Red)            echo "R36S - Warn 30%" ;;
    R36S_PMIC_Controlled)         echo "R36S - PMIC" ;;
    SoySauce_Blue_30_Pink_10_Red) echo "SoySauce - Blue/Pink/Red" ;;
    SoySauce_Off_10_Red)          echo "SoySauce - Off/Red" ;;
    SoySauce_Off_30_Pink_10_Red)  echo "SoySauce - Off/Pink/Red" ;;
    SoySauce_PMIC_Controlled)     echo "SoySauce - PMIC" ;;
    Custom_*)                     echo "$1" ;;
    *)                            echo "$1" ;;
  esac
}

current_led() {
  [ ! -f "$TARGET_SCRIPT" ] && { echo "None (PMIC)"; return; }
  for f in "$SCRIPT_DIR"/*.py; do
    [ -f "$f" ] || continue
    if cmp -s "$f" "$TARGET_SCRIPT"; then
      short_name "$(basename "$f" .py)"
      return
    fi
  done
  echo "Custom (unknown)"
}

ExitMenu() {
  printf "\033c" > /dev/tty1
  pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
  sudo setfont /usr/share/consolefonts/Lat15-TerminusBold20x10.psf.gz 2>/dev/null
  exit 0
}

ApplyLED() {
  local file="$1"
  dialog --colors --infobox "\nApplying:\n$(pretty_name "$file")" 6 $WIDTH > /dev/tty1

  sudo systemctl stop "$SERVICE" 2>/dev/null
  sleep 1
  sudo rm -f "$TARGET_SCRIPT"
  sudo cp "$SCRIPT_DIR/$file" "$TARGET_SCRIPT"
  sudo chmod +x "$TARGET_SCRIPT"
  sudo systemctl start "$SERVICE"
  sleep 1

  if systemctl is-active --quiet "$SERVICE"; then
    dialog --colors --title " Result " --msgbox \
      "\n\ZbApplied successfully:\Zn\n\n$(pretty_name "$file")" 9 $WIDTH > /dev/tty1
  else
    dialog --colors --title " Warning " --msgbox \
      "\n\Zb$SERVICE failed to start.\Zn\n\nScript copied but may fail on boot." 9 $WIDTH > /dev/tty1
  fi
  sudo sync
}

RemoveLED() {
  if dialog --colors --title " Confirm " --yesno \
    "\nRemove custom LED?\n\nPMIC will control the LED again." 8 $WIDTH > /dev/tty1; then

    sudo systemctl stop "$SERVICE" 2>/dev/null
    sleep 1
    sudo rm -f "$TARGET_SCRIPT"
    sudo sync
    dialog --colors --title " Done " --msgbox \
      "\nCustom LED removed.\nPMIC now controls the LED." 7 $WIDTH > /dev/tty1
  fi
}

ManageCustom() {
  while true; do
    mapfile -t files < <(ls -1 "$SCRIPT_DIR"/Custom_*.py 2>/dev/null | xargs -n1 basename)

    if [ ${#files[@]} -eq 0 ]; then
      dialog --colors --title " Custom " --msgbox "\nNo custom profiles found." 6 $WIDTH > /dev/tty1
      return
    fi

    local options=() i=1
    options+=("D" "Delete ALL custom profiles...")
    for f in "${files[@]}"; do
      options+=("$i" "$(pretty_name "$f")")
      i=$((i+1))
    done

    choice=$(dialog --colors \
      --backtitle " R36S LED Control " \
      --title " Custom Profiles " \
      --no-collapse --clear \
      --ok-label "Select" --cancel-label "Back" \
      --menu "Select a profile to delete:" 16 $WIDTH 10 "${options[@]}" 2>&1 >/dev/tty1)

    [[ $? -ne 0 ]] && return

    if [ "$choice" = "D" ]; then
      if dialog --colors --title " Confirm " --yesno \
        "\nDelete ALL custom profiles?\n\nThis cannot be undone." 9 $WIDTH > /dev/tty1; then
        for f in "${files[@]}"; do
          sudo rm -f "$SCRIPT_DIR/$f"
          sudo rm -f "$SCRIPT_DIR/${f}.bak"
        done
        sudo sync
        dialog --colors --title " Done " --msgbox \
          "\nAll custom profiles deleted." 6 $WIDTH > /dev/tty1
      fi
    else
      local target="${files[$((choice - 1))]}"
      if dialog --colors --title " Confirm " --yesno \
        "\nDelete this profile?\n\n$target" 9 $WIDTH > /dev/tty1; then
        sudo rm -f "$SCRIPT_DIR/$target"
        sudo rm -f "$SCRIPT_DIR/${target}.bak"
        sudo sync
        dialog --colors --title " Done " --msgbox "\nDeleted." 5 $WIDTH > /dev/tty1
      fi
    fi
  done
}

WizardGPIO() {
  local v="$1"
  if [ ! -d "/sys/class/gpio/gpio$GPIO_PIN" ]; then
    echo "$GPIO_PIN" | sudo tee /sys/class/gpio/export >/dev/null 2>&1
    sleep 0.3
  fi
  if [ "$v" = "in" ]; then
    echo in | sudo tee "/sys/class/gpio/gpio$GPIO_PIN/direction" >/dev/null 2>&1
  else
    echo out | sudo tee "/sys/class/gpio/gpio$GPIO_PIN/direction" >/dev/null 2>&1
    echo "$v" | sudo tee "/sys/class/gpio/gpio$GPIO_PIN/value" >/dev/null 2>&1
  fi
}

WizardAbort() {
  WizardGPIO in
  sudo systemctl start "$SERVICE" 2>/dev/null
}

AskColor() {
  local title="$1" text="$2"
  dialog --colors --title " $title " --menu "$text" 13 $WIDTH 4 \
    "green" "Green" \
    "blue"  "Blue" \
    "red"   "Red" \
    "off"   "Off" \
    2>&1 >/dev/tty1
}

GenerateProfile() {
  local THRESHOLD="$1" OK_COLOR="$2" LOW_COLOR="$3"
  local GREEN_VAL="$4" BLUE_VAL="$5" RED_VAL="$6" OFF_MODE="$7" OFF_VAL="$8"
  local MODEL_RAW MODEL

  MODEL_RAW=$(detect_model | tr -d '\n\r' | cut -c1-64)
  MODEL=$(echo "$MODEL_RAW" | tr -c 'A-Za-z0-9' '_' | sed 's/__*/_/g; s/^_//; s/_$//')
  [ -z "$MODEL" ] && MODEL="Unknown"

  local FNAME="Custom_${THRESHOLD}_${OK_COLOR}_to_${LOW_COLOR}.py"
  local FOUT="$SCRIPT_DIR/$FNAME"

  [ -f "$FOUT" ] && sudo mv "$FOUT" "${FOUT}.bak"

  sudo tee "$FOUT" > /dev/null <<EOF
#!/usr/bin/env python3
# Auto-generated by R36S LED Control diagnostic wizard
# Model: $MODEL_RAW
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
import os, time

CAP = "/sys/class/power_supply/battery/capacity"
STATUS = "/sys/class/power_supply/battery/status"
GPIO = $GPIO_PIN
GPIO_DIR = f"/sys/class/gpio/gpio{GPIO}"
DIR = f"{GPIO_DIR}/direction"
VAL = f"{GPIO_DIR}/value"

GREEN_VAL = $GREEN_VAL
BLUE_VAL  = $BLUE_VAL
RED_VAL   = $RED_VAL

OFF_MODE = "$OFF_MODE"
OFF_VAL  = $OFF_VAL

THRESHOLD = $THRESHOLD
OK_COLOR  = "$OK_COLOR"
LOW_COLOR = "$LOW_COLOR"

def write(path, v):
    try:
        with open(path, "w") as f:
            f.write(str(v))
    except:
        pass

def ensure_exported():
    if not os.path.exists(GPIO_DIR):
        write("/sys/class/gpio/export", GPIO)
        time.sleep(0.15)

def gpio_off():
    if OFF_MODE == "input":
        write(DIR, "in")
    elif OFF_MODE == "unexport":
        if os.path.exists(GPIO_DIR):
            write("/sys/class/gpio/unexport", GPIO)
    elif OFF_MODE == "value":
        ensure_exported()
        write(DIR, "out")
        write(VAL, OFF_VAL)

def gpio_set(value):
    if value is None:
        gpio_off()
        return
    ensure_exported()
    write(DIR, "out")
    write(VAL, value)

COLOR_VALS = {
    "green": GREEN_VAL,
    "blue":  BLUE_VAL,
    "red":   RED_VAL,
    "off":   None,
}

def apply_color(c):
    gpio_set(COLOR_VALS.get(c))

gpio_off()
prev = (-1, "")

while True:
    try:
        cap = int(open(CAP).read().strip())
        status = open(STATUS).read().strip()
    except:
        gpio_off()
        time.sleep(10)
        continue

    if (cap, status) == prev:
        time.sleep(5)
        continue

    prev = (cap, status)

    if status in ["Charging", "Full"]:
        gpio_off()
    elif cap <= THRESHOLD:
        apply_color(LOW_COLOR)
    else:
        apply_color(OK_COLOR)

    time.sleep(5)
EOF

  sudo chmod +x "$FOUT"
  sudo sync
  echo "$FNAME"
}

WizardLED() {
  if [ ! -d "/sys/class/gpio/gpio$GPIO_PIN" ] && [ ! -w /sys/class/gpio/export ]; then
    dialog --colors --title " Unavailable " --msgbox \
      "\nGPIO $GPIO_PIN is not available on this device." 8 $WIDTH > /dev/tty1
    return
  fi

  dialog --colors --title " Diagnostic " --yesno \
    "\nThe wizard will test GPIO $GPIO_PIN\nand ask what you see on the LED.\n\nStart?" 11 $WIDTH > /dev/tty1 || return

  sudo systemctl stop "$SERVICE" 2>/dev/null
  sleep 1

  WizardGPIO 0
  dialog --colors --infobox "\n\nGPIO is at value=0.\n\nObserve the LED..." 8 $WIDTH > /dev/tty1
  sleep 5
  local A
  A=$(AskColor " Test 1/4 " "\nWith value=0, what color?")
  [ -z "$A" ] && { WizardAbort; return; }

  WizardGPIO 1
  dialog --colors --infobox "\n\nGPIO is at value=1.\n\nObserve the LED..." 8 $WIDTH > /dev/tty1
  sleep 5
  local B
  B=$(AskColor " Test 2/4 " "\nWith value=1, what color?")
  [ -z "$B" ] && { WizardAbort; return; }

  WizardGPIO in
  dialog --colors --infobox "\n\nGPIO is in input (high-Z).\n\nObserve the LED..." 8 $WIDTH > /dev/tty1
  sleep 5
  local C
  C=$(AskColor " Test 3/4 " "\nWith input (high-Z), what color?")
  [ -z "$C" ] && { WizardAbort; return; }

  local D="off"
  if [ "$C" != "off" ]; then
    if [ -d "/sys/class/gpio/gpio$GPIO_PIN" ]; then
      echo "$GPIO_PIN" | sudo tee /sys/class/gpio/unexport >/dev/null 2>&1
    fi
    dialog --colors --infobox "\n\nGPIO is unexported (released).\n\nObserve the LED..." 8 $WIDTH > /dev/tty1
    sleep 5
    D=$(AskColor " Test 4/4 " "\nWith GPIO released, what color?")
    [ -z "$D" ] && { WizardAbort; return; }
    echo "$GPIO_PIN" | sudo tee /sys/class/gpio/export >/dev/null 2>&1
    sleep 0.3
  fi

  local GREEN_VAL="" BLUE_VAL="" RED_VAL=""
  case "$A" in
    green) GREEN_VAL=0 ;;
    blue)  BLUE_VAL=0 ;;
    red)   RED_VAL=0 ;;
  esac
  case "$B" in
    green) GREEN_VAL=1 ;;
    blue)  BLUE_VAL=1 ;;
    red)   RED_VAL=1 ;;
  esac

  local OFF_MODE="none" OFF_VAL=0
  if   [ "$C" = "off" ]; then OFF_MODE="input"
  elif [ "$D" = "off" ]; then OFF_MODE="unexport"
  elif [ "$A" = "off" ]; then OFF_MODE="value"; OFF_VAL=0
  elif [ "$B" = "off" ]; then OFF_MODE="value"; OFF_VAL=1
  fi

  local HAS_GREEN=0 HAS_BLUE=0 HAS_RED=0 HAS_OFF=0
  [ -n "$GREEN_VAL" ] && HAS_GREEN=1
  [ -n "$BLUE_VAL" ]  && HAS_BLUE=1
  [ -n "$RED_VAL" ]   && HAS_RED=1
  [ "$OFF_MODE" != "none" ] && HAS_OFF=1

  local opts=() n=0
  local NORMAL_OPTS=()

  [ "$HAS_OFF"   = "1" ] && NORMAL_OPTS+=("off")
  [ "$HAS_GREEN" = "1" ] && NORMAL_OPTS+=("green")
  [ "$HAS_BLUE"  = "1" ] && NORMAL_OPTS+=("blue")
  [ "$HAS_RED"   = "1" ] && NORMAL_OPTS+=("red")

  if [ "$HAS_RED" = "1" ]; then
    local thr ok label_ok
    for thr in 10 20 30; do
      for ok in "${NORMAL_OPTS[@]}"; do
        [ "$ok" = "red" ] && continue
        case "$ok" in
          off)   label_ok="Off" ;;
          green) label_ok="Green" ;;
          blue)  label_ok="Blue" ;;
          red)   label_ok="Red" ;;
        esac
        n=$((n+1))
        opts+=("$n" "$label_ok >= $((thr+1))%   |   Red <= $thr%")
      done
    done
  else
    local ok label_ok
    for ok in "${NORMAL_OPTS[@]}"; do
      [ "$ok" = "red" ] && continue
      case "$ok" in
        off)   label_ok="Always off" ;;
        green) label_ok="Always green" ;;
        blue)  label_ok="Always blue" ;;
        red)   label_ok="Always red" ;;
      esac
      n=$((n+1))
      opts+=("$n" "$label_ok")
    done
  fi

  opts+=("C" "Custom...")
  local MENU_H=$((${#opts[@]} / 2))
  [ "$MENU_H" -lt 4 ] && MENU_H=4

  if [ "$HAS_OFF" = "0" ]; then
    dialog --colors --title " Note " --msgbox \
      "\nThis LED cannot be turned off.\n\nOnly color changes will be available." 8 $WIDTH > /dev/tty1
  fi

  local PICK
  PICK=$(dialog --colors --title " LED Behavior " --menu \
    "\nChoose how the LED should behave:" 16 $WIDTH $MENU_H "${opts[@]}" \
    2>&1 >/dev/tty1)
  [ -z "$PICK" ] && { WizardAbort; return; }

  local THRESHOLD="" OK_COLOR="" LOW_COLOR=""

  if [ "$PICK" = "C" ]; then
    THRESHOLD=$(dialog --colors --title " Threshold " --menu \
      "\nLow battery threshold:" 12 $WIDTH 3 \
      "10" "10%" "20" "20%" "30" "30%" 2>&1 >/dev/tty1)
    [ -z "$THRESHOLD" ] && { WizardAbort; return; }

    local ok_menu=()
    [ "$HAS_OFF"   = "1" ] && ok_menu+=("off"   "Off")
    [ "$HAS_GREEN" = "1" ] && ok_menu+=("green" "Green")
    [ "$HAS_BLUE"  = "1" ] && ok_menu+=("blue"  "Blue")
    [ "$HAS_RED"   = "1" ] && ok_menu+=("red"   "Red")

    OK_COLOR=$(dialog --colors --title " Normal " --menu \
      "\nAbove $THRESHOLD%, the LED is:" 14 $WIDTH 5 "${ok_menu[@]}" 2>&1 >/dev/tty1)
    [ -z "$OK_COLOR" ] && { WizardAbort; return; }

    local low_menu=()
    [ "$HAS_RED"   = "1" ] && low_menu+=("red"   "Red")
    [ "$HAS_GREEN" = "1" ] && low_menu+=("green" "Green")
    [ "$HAS_BLUE"  = "1" ] && low_menu+=("blue"  "Blue")
    [ "$HAS_OFF"   = "1" ] && low_menu+=("off"   "Off")

    LOW_COLOR=$(dialog --colors --title " Low battery " --menu \
      "\nAt or below $THRESHOLD%, the LED is:" 14 $WIDTH 5 "${low_menu[@]}" 2>&1 >/dev/tty1)
    [ -z "$LOW_COLOR" ] && { WizardAbort; return; }
  else
    if [ "$HAS_RED" = "1" ]; then
      local idx=0 matched=0 thr ok
      for thr in 10 20 30; do
        for ok in "${NORMAL_OPTS[@]}"; do
          [ "$ok" = "red" ] && continue
          idx=$((idx+1))
          if [ "$idx" = "$PICK" ]; then
            THRESHOLD=$thr
            OK_COLOR=$ok
            LOW_COLOR="red"
            matched=1
            break 2
          fi
        done
      done
      if [ "$matched" = "0" ]; then
        WizardAbort
        return
      fi
    else
      local idx=0 ok
      for ok in "${NORMAL_OPTS[@]}"; do
        [ "$ok" = "red" ] && continue
        idx=$((idx+1))
        if [ "$idx" = "$PICK" ]; then
          THRESHOLD=0
          OK_COLOR=$ok
          LOW_COLOR=$ok
          break
        fi
      done
    fi
  fi

  local FNAME
  FNAME=$(GenerateProfile "$THRESHOLD" "$OK_COLOR" "$LOW_COLOR" \
    "$GREEN_VAL" "$BLUE_VAL" "$RED_VAL" "$OFF_MODE" "$OFF_VAL")

  if [ -z "$FNAME" ] || [ ! -f "$SCRIPT_DIR/$FNAME" ]; then
    dialog --colors --title " Error " --msgbox "\nFailed to generate profile." 6 $WIDTH > /dev/tty1
    WizardAbort
    return
  fi

  if dialog --colors --title " Profile " --yesno \
    "\nGenerated:\n$FNAME\n\nApply now?" 10 $WIDTH > /dev/tty1; then
    ApplyLED "$FNAME"
  else
    WizardAbort
  fi
}

VariantMenu() {
  local prefix="$1" title="$2"
  while true; do
    mapfile -t files < <(ls -1 "$SCRIPT_DIR"/${prefix}*.py 2>/dev/null | xargs -n1 basename)
    if [ ${#files[@]} -eq 0 ]; then
      dialog --colors --title " $title " --msgbox "\nNo scripts found for $title." 6 $WIDTH > /dev/tty1
      return
    fi
    local options=() i=1
    for f in "${files[@]}"; do
      options+=("$i" "$(pretty_name "$f")")
      i=$((i+1))
    done
    choice=$(dialog --colors \
      --backtitle " R36S LED Control " \
      --title " $title " \
      --no-collapse --clear \
      --ok-label "Apply" --cancel-label "Back" \
      --menu "" $HEIGHT $WIDTH 12 "${options[@]}" 2>&1 >/dev/tty1)
    [[ $? -ne 0 ]] && return
    ApplyLED "${files[$((choice - 1))]}"
  done
}

CustomMenu() {
  while true; do
    mapfile -t files < <(ls -1 "$SCRIPT_DIR"/Custom_*.py 2>/dev/null | xargs -n1 basename)

    if [ ${#files[@]} -eq 0 ]; then
      dialog --colors --title " Custom " --msgbox "\nNo custom profiles found." 6 $WIDTH > /dev/tty1
      return
    fi

    local options=() i=1
    for f in "${files[@]}"; do
      options+=("$i" "$(pretty_name "$f")")
      i=$((i+1))
    done
    options+=("M" "Manage / Delete...")

    choice=$(dialog --colors \
      --backtitle " R36S LED Control " \
      --title " Custom " \
      --no-collapse --clear \
      --ok-label "Apply" --cancel-label "Back" \
      --menu "" $HEIGHT $WIDTH 12 "${options[@]}" 2>&1 >/dev/tty1)

    [[ $? -ne 0 ]] && return

    if [ "$choice" = "M" ]; then
      ManageCustom
    else
      ApplyLED "${files[$((choice - 1))]}"
    fi
  done
}

MainMenu() {
  while true; do
    local cur model
    cur=$(current_led)
    model=$(detect_model)

    choice=$(dialog --colors \
      --backtitle " R36S LED Control " \
      --title " Main Menu " \
      --no-collapse --clear \
      --ok-label "Select" --cancel-label "Exit" \
      --menu "Model:  $model\nActive: $cur\n\nSelect a device family:" \
      $HEIGHT $WIDTH 11 \
      "1" "Clone" \
      "2" "R36S" \
      "3" "SoySauce" \
      "4" "Custom (generated profiles)" \
      "5" "Diagnose & Create Profile" \
      "6" "Remove LED (PMIC control)" \
      "7" "Exit" \
      2>&1 >/dev/tty1)

    case "$choice" in
      1) VariantMenu "Clone_"    "Clone" ;;
      2) VariantMenu "R36S_"     "R36S" ;;
      3) VariantMenu "SoySauce_" "SoySauce" ;;
      4) CustomMenu ;;
      5) WizardLED ;;
      6) RemoveLED ;;
      7|"") ExitMenu ;;
    esac
  done
}

sudo chmod 666 /dev/uinput 2>/dev/null
export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
/opt/inttools/gptokeyb -1 "R36S LED.sh" -c "/opt/inttools/keys.gptk" >/dev/null 2>&1 &

printf "\033c" > /dev/tty1
dialog --clear
trap ExitMenu EXIT
MainMenu
