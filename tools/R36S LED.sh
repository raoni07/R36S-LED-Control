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
NAME_WIDTH=16
PROFILE_TOTAL_CELLS=20

PROBE_PINS=(0 1 17 77)
GPIO_ROOT="${GPIO_ROOT:-/sys/class/gpio}"
BATT_DIR="${BATT_DIR:-/sys/class/power_supply/battery}"
OBS_FILE=""
WIZ_PINS=""

sudo setfont /usr/share/consolefonts/Lat15-TerminusBold20x10.psf.gz 2>/dev/null

pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
printf "\033c" > /dev/tty1
printf "Starting R36S LED Control..." > /dev/tty1

SCRIPT_DIR="${SCRIPT_DIR:-/roms/tools/R36S_LED}"
TARGET_SCRIPT="${TARGET_SCRIPT:-/usr/local/bin/batt_life_warning.py}"
CORE_NAME="batt_led_core.py"
CORE_SRC="$SCRIPT_DIR/$CORE_NAME"
CORE_DST="$(dirname "$TARGET_SCRIPT")/$CORE_NAME"
SERVICE="batt_led.service"

mkdir -p "$SCRIPT_DIR" 2>/dev/null || sudo mkdir -p "$SCRIPT_DIR" 2>/dev/null
CORE_VERSION=1

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

service_exists() {
  systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE}"
}

color_code() {
  case "$1" in
    red)                 echo 1 ;;
    green)               echo 2 ;;
    yellow|orange)       echo 3 ;;
    blue)                echo 4 ;;
    pink|purple|magenta) echo 5 ;;
    cyan)                echo 6 ;;
    white)               echo 7 ;;
    black|off)           echo 0 ;;
    *)                   echo 7 ;;
  esac
}

color_display() {
  case "$1" in
    green)       echo "Green" ;;
    blue)        echo "Blue" ;;
    red)         echo "Red" ;;
    yellow)      echo "Yellow" ;;
    orange)      echo "Orange" ;;
    white)       echo "White" ;;
    pink)        echo "Pink" ;;
    purple)      echo "Purple" ;;
    off)         echo "Off" ;;
    *)           echo "$1" ;;
  esac
}

swatch_paint() {
  local color="$1" block="$2"
  case "$color" in
    off)   printf '%s' "\Z0${block}\Zn" ;;
    white) printf '%s' "\Zb\Z7${block}\Zn" ;;
    *)     printf '%s' "\Z$(color_code "$color")${block}\Zn" ;;
  esac
}

draw_bar() {
  local color="$1"
  local cells="$2"
  local color2="${3:-}"
  local s="" i

  [ "$cells" -lt 1 ] && cells=1

  if [ -n "$color2" ] && [ "$color2" != "$color" ]; then
    [ "$cells" -lt 2 ] && cells=2
    local step=1
    [ "$cells" -ge 8 ] && step=2
    local pos=0 idx=0 end block j
    while [ "$pos" -lt "$cells" ]; do
      end=$((pos + step))
      [ "$end" -gt "$cells" ] && end=$cells
      block=""
      for ((j=pos; j<end; j++)); do block+="█"; done
      if [ $((idx % 2)) -eq 0 ]; then
        s+="$(swatch_paint "$color" "$block")"
      else
        s+="$(swatch_paint "$color2" "$block")"
      fi
      pos=$end
      idx=$((idx + 1))
    done
    printf '%s' "$s"
    return
  fi

  for ((i=0; i<cells; i++)); do s+="█"; done
  printf '%s' "$(swatch_paint "$color" "$s")"
}

truncate_name() {
  local n="$1"
  local max="${2:-$NAME_WIDTH}"
  if [ ${#n} -gt "$max" ]; then
    printf '%s..' "${n:0:$((max-2))}"
  else
    printf '%s' "$n"
  fi
}

pretty_name() {
  case "$1" in
    Clone_Blue_30_Purple_10_Red.py)   echo "Red <=10%  |  Purple 11-29%  |  Blue >=30%" ;;
    Clone_Off_10_Red.py)              echo "Red <=10%  |  Off >=11%" ;;
    Clone_Off_30_Purple_10_Red.py)    echo "Red <=10%  |  Purple 11-29%  |  Off >=30%" ;;
    Clone_PMIC_Controlled.py)         echo "Device default (no software control)" ;;
    R36S_Green_10_Red.py)             echo "Warning <=10%  |  Off >=11%" ;;
    R36S_Green_20_Red.py)             echo "Warning <=20%  |  Off >=21%" ;;
    R36S_Green_30_Red.py)             echo "Warning <=30%  |  Off >=31%" ;;
    R36S_PMIC_Controlled.py)          echo "Device default (no software control)" ;;
    SoySauce_Blue_30_Pink_10_Red.py)  echo "Red <=10%  |  Pink 11-29%  |  Blue >=30%" ;;
    SoySauce_Off_10_Red.py)           echo "Red <=10%  |  Off >=11%" ;;
    SoySauce_Off_30_Pink_10_Red.py)   echo "Red <=10%  |  Pink 11-29%  |  Off >=30%" ;;
    SoySauce_PMIC_Controlled.py)      echo "Device default (no software control)" ;;
    Custom_*.py)
      local b="${1%.py}"; b="${b#Custom_}"
      local parts
      IFS='_' read -ra parts <<< "$b"
      if [ ${#parts[@]} -ge 5 ]; then
        echo "${parts[2]} > ${parts[3]} > ${parts[4]}  (${parts[0]}/${parts[1]}%)"
      else
        echo "$b"
      fi
      ;;
    *)                                echo "$1" ;;
  esac
}

short_name() {
  case "$1" in
    Clone_Blue_30_Purple_10_Red)  echo "Red/Purple/Blue" ;;
    Clone_Off_10_Red)             echo "Red/Off" ;;
    Clone_Off_30_Purple_10_Red)   echo "Red/Purple/Off" ;;
    Clone_PMIC_Controlled)        echo "Device default" ;;
    R36S_Green_10_Red)            echo "Warning/Off @10%" ;;
    R36S_Green_20_Red)            echo "Warning/Off @20%" ;;
    R36S_Green_30_Red)            echo "Warning/Off @30%" ;;
    R36S_PMIC_Controlled)         echo "Device default" ;;
    SoySauce_Blue_30_Pink_10_Red) echo "Red/Pink/Blue" ;;
    SoySauce_Off_10_Red)          echo "Red/Off" ;;
    SoySauce_Off_30_Pink_10_Red)  echo "Red/Pink/Off" ;;
    SoySauce_PMIC_Controlled)     echo "Device default" ;;
    Custom_*)
      local out="${1#Custom_}"
      case "$out" in *+*) out="$out [blink]" ;; esac
      echo "$out"
      ;;
    *)                            echo "$1" ;;
  esac
}

current_file() {
  [ ! -f "$TARGET_SCRIPT" ] && return
  for f in "$SCRIPT_DIR"/*.py; do
    [ -f "$f" ] || continue
    if cmp -s "$f" "$TARGET_SCRIPT"; then
      basename "$f"
      return
    fi
  done
}

profile_zones() {
  local f="$1"
  case "$f" in
    Clone_Blue_30_Purple_10_Red.py)   echo "blue:30 purple:10 red:0" ;;
    Clone_Off_10_Red.py)              echo "off:10 red:0" ;;
    Clone_Off_30_Purple_10_Red.py)    echo "off:30 purple:10 red:0" ;;
    R36S_Green_10_Red.py)             echo "off:10 red:0" ;;
    R36S_Green_20_Red.py)             echo "off:20 red:0" ;;
    R36S_Green_30_Red.py)             echo "off:30 red:0" ;;
    SoySauce_Blue_30_Pink_10_Red.py)  echo "blue:30 purple:10 red:0" ;;
    SoySauce_Off_10_Red.py)           echo "off:10 red:0" ;;
    SoySauce_Off_30_Pink_10_Red.py)   echo "off:30 purple:10 red:0" ;;
    Clone_PMIC_Controlled.py)         ;;
    R36S_PMIC_Controlled.py)          ;;
    SoySauce_PMIC_Controlled.py)      ;;
    Custom_*.py)
      local b="${f%.py}"; b="${b#Custom_}"
      local parts
      IFS='_' read -ra parts <<< "$b"
      if [ ${#parts[@]} -ge 5 ]; then
        echo "${parts[2]}:${parts[0]} ${parts[3]}:${parts[1]} ${parts[4]}:0"
      fi
      ;;
  esac
}

profile_bar_core() {
  local zones="$1"
  local -a zc=() zt=()
  local z
  for z in $zones; do
    zc+=("${z%%:*}")
    zt+=("${z##*:}")
  done

  local n=${#zc[@]}

  if [ "$n" -eq 2 ]; then
    local t0="${zt[0]}"
    local vthr=30
    [ "$t0" -ge 30 ] && vthr=$((t0 + 20))
    [ "$vthr" -gt 90 ] && vthr=90
    zc=("${zc[0]}" "${zc[0]}" "${zc[1]}")
    zt=("$vthr" "$t0" "${zt[1]}")
    n=3
  fi

  local -a rc=() rt=()
  local i
  for ((i=n-1; i>=0; i--)); do
    rc+=("${zc[$i]}")
    rt+=("${zt[$i]}")
  done

  for ((i=0; i<n; i++)); do
    local c="${rc[$i]}"
    local c1="${c%%+*}"
    local c2=""
    [[ "$c" == *+* ]] && c2="${c##*+}"
    local from="${rt[$i]}"
    local to
    if [ $((i+1)) -lt "$n" ]; then
      to="${rt[$((i+1))]}"
    else
      to=100
    fi
    local range=$((to - from))
    [ "$range" -lt 0 ] && range=0
    local cells=$((range * PROFILE_TOTAL_CELLS / 100))
    local min_cells=1
    [ -n "$c2" ] && [ "$c2" != "$c1" ] && min_cells=2
    [ "$cells" -lt "$min_cells" ] && cells=$min_cells
    if [ -n "$c2" ]; then
      printf '%s' "$(draw_bar "$c1" "$cells" "$c2")"
    else
      printf '%s' "$(draw_bar "$c1" "$cells")"
    fi
    if [ $((i+1)) -lt "$n" ]; then
      printf ' %2d%% ' "${rt[$((i+1))]}"
    fi
  done
}

profile_line() {
  local f="$1"
  local name
  name=$(truncate_name "$2")
  local zones
  zones=$(profile_zones "$f")
  if [ -z "$zones" ]; then
    printf '%s' "$name"
    return
  fi
  printf '%-*s ' "$NAME_WIDTH" "$name"
  profile_bar_core "$zones"
}

profile_swatches() {
  local f="$1"
  local zones
  zones=$(profile_zones "$f")
  if [ -z "$zones" ]; then
    printf '%s' "\Zn[ Device default ]\Zn"
    return
  fi
  profile_bar_core "$zones"
}

ExitMenu() {
  printf "\033c" > /dev/tty1
  pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
  sudo setfont /usr/share/consolefonts/Lat15-TerminusBold20x10.psf.gz 2>/dev/null
  exit 0
}

ConfirmApply() {
  local f="$1"
  dialog --colors --title " Confirm " --yesno \
"\nApply this profile?

\Zb$(pretty_name "$f")\Zn" \
    11 $WIDTH > /dev/tty1
}

ApplyLED() {
  local file="$1"

  if [ ! -f "$SCRIPT_DIR/$file" ] || [ ! -f "$CORE_SRC" ]; then
    dialog --colors --title " Error " --msgbox \
"\n\ZbMissing files.\Zn\n\nNeed $file\nand $CORE_NAME in\n$SCRIPT_DIR" 11 $WIDTH > /dev/tty1
    return 1
  fi

  dialog --colors --infobox \
"\n\nApplying profile:\n\n\Zb$(pretty_name "$file")\Zn\n\nPlease wait..." \
    10 $WIDTH > /dev/tty1

  StopService                      
  sudo rm -f "$TARGET_SCRIPT"
  sudo cp "$SCRIPT_DIR/$file" "$TARGET_SCRIPT"
  sudo chmod +x "$TARGET_SCRIPT"
  InstallCore

  if service_exists; then
    sudo systemctl start "$SERVICE"
    sleep 2
    if systemctl is-active --quiet "$SERVICE"; then
      dialog --colors --title " Result " --msgbox \
"\n\Zb✓ Applied successfully\Zn\n\n$(pretty_name "$file")" \
        9 $WIDTH > /dev/tty1
    else
      dialog --colors --title " Warning " --msgbox \
"\n\Zb$SERVICE failed to start.\Zn\n\nScript copied but may fail on boot." \
        9 $WIDTH > /dev/tty1
    fi
  else
    dialog --colors --title " Done " --msgbox \
"\n\ZbScript copied.\Zn\n\n\ZbService $SERVICE not present.\Zn\nStarting script manually." \
      11 $WIDTH > /dev/tty1
    sudo nohup python3 "$TARGET_SCRIPT" >/dev/null 2>&1 &
    sleep 1
  fi
  sudo sync
}

RemoveLED() {
  if dialog --colors --title " Confirm " --yesno \
    "\nRemove custom LED?\n\nDevice default will take over." 8 $WIDTH > /dev/tty1; then

    StopService                     

    local nop
    nop=$(ls -1 "$SCRIPT_DIR"/*_PMIC_Controlled.py 2>/dev/null | head -n 1)
    if service_exists && [ -n "$nop" ]; then
      
      sudo cp "$nop" "$TARGET_SCRIPT"
      sudo chmod +x "$TARGET_SCRIPT"
      InstallCore
      sudo systemctl start "$SERVICE" 2>/dev/null
    else
      sudo rm -f "$TARGET_SCRIPT"
    fi
    sudo sync
    dialog --colors --title " Done " --msgbox \
      "\nCustom LED removed.\nDevice now controls the LED." 7 $WIDTH > /dev/tty1
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
      options+=("$i" "$(profile_line "$f" "$(short_name "${f%.py}")")")
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

GPIOExport() {
  local pin="$1" i
  [ -d "$GPIO_ROOT/gpio$pin" ] && return 0
  echo "$pin" | sudo tee "$GPIO_ROOT/export" >/dev/null 2>&1
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -d "$GPIO_ROOT/gpio$pin" ] && return 0
    sleep 0.1
  done
  return 1
}

GPIOSet() {
  local pin="$1" mode="$2" value="$3" lvl
  GPIOExport "$pin" || return 1
  if [ "$mode" = "in" ]; then
    echo in | sudo tee "$GPIO_ROOT/gpio$pin/direction" >/dev/null 2>&1
  else
    lvl=low
    [ "$value" = "1" ] && lvl=high
    if ! echo "$lvl" | sudo tee "$GPIO_ROOT/gpio$pin/direction" >/dev/null 2>&1; then
      echo out | sudo tee "$GPIO_ROOT/gpio$pin/direction" >/dev/null 2>&1
      echo "$value" | sudo tee "$GPIO_ROOT/gpio$pin/value" >/dev/null 2>&1
    fi
  fi
}

ReleasePins() {
  local pin
  for pin in "${PROBE_PINS[@]}"; do
    if [ -d "$GPIO_ROOT/gpio$pin" ]; then
      echo in | sudo tee "$GPIO_ROOT/gpio$pin/direction" >/dev/null 2>&1
    fi
  done
}

InstallCore() {
  [ -f "$CORE_SRC" ] || return 1
  sudo cp "$CORE_SRC" "$CORE_DST" && sudo chmod 644 "$CORE_DST"
}

HasColor() {
  local want="$1" x
  shift
  for x in "$@"; do
    [ "$x" = "$want" ] && return 0
  done
  return 1
}

StopService() {
  if service_exists; then
    sudo systemctl stop "$SERVICE" 2>/dev/null
  fi
  sudo pkill -f batt_life_warning.py 2>/dev/null
  sleep 1
  ReleasePins
}

StartService() {
  if service_exists; then
    sudo systemctl start "$SERVICE" 2>/dev/null
  fi
}

AskColor() {
  local title="$1" text="${2:-What color do you see on the LED?}"
  local -a names=(blue red purple green orange white off)
  local -a labels=("Blue" "Red" "Purple / Pink" "Green" "Orange / Yellow" "White" "Off")
  local options=() i
  for i in "${!names[@]}"; do
    options+=("$((i + 1))" "$(draw_bar "${names[$i]}" 14)  ${labels[$i]}")
  done

  local pick
  pick=$(dialog --colors --no-collapse --title " $title " --cancel-label "Abort" --menu \
    "\n$text" 18 $WIDTH 7 "${options[@]}" \
    2>&1 >/dev/tty1) || return 1
  [ -z "$pick" ] && return 1
  echo "${names[$((pick - 1))]}"
}

WizardAbort() {
  ReleasePins
  [ -n "$OBS_FILE" ] && rm -f "$OBS_FILE" 2>/dev/null
  OBS_FILE=""
  StartService
}

GenerateUniversalProfile() {
  local HIGH_THR="$1" LOW_THR="$2"
  local Z_HIGH="$3" Z_MID="$4" Z_LOW="$5"
  local BLINK_PERIOD="${6:-1.0}"

  local FNAME="Custom_${HIGH_THR}_${LOW_THR}_${Z_HIGH}_${Z_MID}_${Z_LOW}.py"
  local FOUT="$SCRIPT_DIR/$FNAME"

  local need
  need=$(printf '%s\n' "${Z_HIGH//+/$'\n'}" "${Z_MID//+/$'\n'}" "${Z_LOW//+/$'\n'}" | sort -u | paste -sd, -)

  local CMAP
  CMAP=$(python3 "$CORE_SRC" --solve "$OBS_FILE" --pins "$WIZ_PINS" --need "$need") || return 1
  [ -n "$CMAP" ] || return 1

  [ -f "$FOUT" ] && sudo mv "$FOUT" "${FOUT}.bak"

  local PINS_PY="[${WIZ_PINS//,/, }]"
  local MID_MIN=$((LOW_THR + 1))

  sudo tee "$FOUT" > /dev/null <<EOF
#!/usr/bin/env python3
# Custom LED profile generated by R36S LED Control (needs batt_led_core.py next to it).
import os, sys
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import batt_led_core as core

core.run(
    pins=$PINS_PY,
    colors={
$CMAP
    },
    zones=[($HIGH_THR, "$Z_HIGH"), ($MID_MIN, "$Z_MID"), (0, "$Z_LOW")],
    hysteresis=2,
    blink_period=$BLINK_PERIOD,
)
EOF

  sudo chmod +x "$FOUT"
  sudo sync
  echo "$FNAME"
}

PickColor() {
  local title="$1" current="$2"
  shift 2
  local available=("$@")

  local options=() i=1 c
  for c in "${available[@]}"; do
    local mark=" "
    [ "$c" = "$current" ] && mark="*"
    options+=("$i" "${mark} $(draw_bar "$c" 12)  $(color_display "$c")")
    i=$((i+1))
  done

  local pick
  pick=$(dialog --colors --title " $title " --menu \
    "\nSelect a color:" 17 $WIDTH 8 "${options[@]}" \
    2>&1 >/dev/tty1) || return 1
  [ -z "$pick" ] && return 1
  echo "${available[$((pick - 1))]}"
}

PickZone() {
  local title="$1" current="$2"
  shift 2
  local available=("$@")

  local cur_c1="$current" cur_c2=""
  if [[ "$current" == *+* ]]; then
    cur_c1="${current%%+*}"
    cur_c2="${current##*+}"
  fi

  local options=() i=1 c
  for c in "${available[@]}"; do
    local mark=" "
    [ "$c" = "$cur_c1" ] && [ -z "$cur_c2" ] && mark="*"
    options+=("$i" "${mark} $(draw_bar "$c" 12)  $(color_display "$c")")
    i=$((i+1))
  done
  local bmark=" "
  [ -n "$cur_c2" ] && bmark="*"
  options+=("B" "${bmark} Blink between two colors...")

  local pick
  pick=$(dialog --colors --title " $title " --menu \
    "\nChoose a mode for this zone:" 18 $WIDTH 9 "${options[@]}" \
    2>&1 >/dev/tty1) || return 1
  [ -z "$pick" ] && return 1

  if [ "$pick" = "B" ]; then
    local c1 c2
    c1=$(PickColor "Blink - color 1" "$cur_c1" "${available[@]}") || return 1
    [ -z "$c1" ] && return 1
    c2=$(PickColor "Blink - color 2" "$cur_c2" "${available[@]}") || return 1
    [ -z "$c2" ] && return 1
    if [ "$c1" = "$c2" ]; then
      dialog --colors --title " Invalid " --msgbox \
        "\nPick two different colors to blink." 7 $WIDTH >/dev/tty1
      return 1
    fi
    echo "${c1}+${c2}"
  else
    echo "${available[$((pick - 1))]}"
  fi
}

zone_preview_line() {
  local z="$1"
  if [[ "$z" == *+* ]]; then
    local c1="${z%%+*}"
    local c2="${z##*+}"
    printf '%s  %s ↻ %s' "$(draw_bar "$c1" 8 "$c2")" "$(color_display "$c1")" "$(color_display "$c2")"
  else
    printf '%s  %s' "$(draw_bar "$z" 8)" "$(color_display "$z")"
  fi
}

WizardColorPicker() {
  local available_colors=("$@")

  if [ ${#available_colors[@]} -eq 0 ]; then
    dialog --colors --title " Error " --msgbox "\nNo colors available." 7 $WIDTH >/dev/tty1
    WizardAbort
    return
  fi

  local colors=()
  local c
  for c in "${available_colors[@]}"; do
    [ "$c" != "off" ] && colors+=("$c")
  done
  local has_off="no"
  for c in "${available_colors[@]}"; do
    [ "$c" = "off" ] && has_off="yes"
  done
  [ "$has_off" = "yes" ] && colors+=("off")

  if [ ${#colors[@]} -eq 0 ]; then
    colors=("off")
  fi

  local HIGH_THR=30 LOW_THR=10
  local Z_HIGH="${colors[0]}" Z_MID="${colors[0]}" Z_LOW="${colors[0]}"
  local pref

  for pref in blue green off; do
    if HasColor "$pref" "${colors[@]}"; then Z_HIGH="$pref"; break; fi
  done
  for pref in red orange; do
    if HasColor "$pref" "${colors[@]}"; then Z_LOW="$pref"; break; fi
  done
  Z_MID="$Z_HIGH"
  for pref in purple orange white green blue red; do
    if [ "$pref" != "$Z_HIGH" ] && [ "$pref" != "$Z_LOW" ] && HasColor "$pref" "${colors[@]}"; then
      Z_MID="$pref"; break
    fi
  done

  local BLINK_PERIOD="1.0"

  while true; do
    local any_blink=0
    [[ "$Z_HIGH" == *+* ]] && any_blink=1
    [[ "$Z_MID"  == *+* ]] && any_blink=1
    [[ "$Z_LOW"  == *+* ]] && any_blink=1

    local line1_lbl="High (>=$HIGH_THR%):"
    local line2_lbl="Mid ($((LOW_THR + 1))-$((HIGH_THR - 1))%):"
    local line3_lbl="Low (<=$LOW_THR%):"

    while [ ${#line1_lbl} -lt 21 ]; do line1_lbl="$line1_lbl "; done
    while [ ${#line2_lbl} -lt 21 ]; do line2_lbl="$line2_lbl "; done
    while [ ${#line3_lbl} -lt 21 ]; do line3_lbl="$line3_lbl "; done

    local menu_items=(
      "1" "${line1_lbl} $(zone_preview_line "$Z_HIGH")"
      "2" "${line2_lbl} $(zone_preview_line "$Z_MID")"
      "3" "${line3_lbl} $(zone_preview_line "$Z_LOW")"
      "4" "High threshold:   ${HIGH_THR}%"
      "5" "Low threshold:    ${LOW_THR}%"
    )
    [ "$any_blink" = "1" ] && menu_items+=("6" "Blink period:     ${BLINK_PERIOD}s")
    menu_items+=("7" "\Zb✔  Save & Apply\Zn")

    local pick
    pick=$(dialog --colors --title " LED Behavior " --no-collapse --clear \
      --ok-label "Select" --cancel-label "Cancel" \
      --menu "" 20 $WIDTH 8 "${menu_items[@]}" \
      2>&1 >/dev/tty1) || { WizardAbort; return; }

    case "$pick" in
      1)
        c=$(PickZone "High zone (>= ${HIGH_THR}%)" "$Z_HIGH" "${colors[@]}") \
          && [ -n "$c" ] && Z_HIGH="$c"
        ;;
      2)
        c=$(PickZone "Mid zone ($((LOW_THR + 1))-$((HIGH_THR - 1))%)" "$Z_MID" "${colors[@]}") \
          && [ -n "$c" ] && Z_MID="$c"
        ;;
      3)
        c=$(PickZone "Low zone (<= ${LOW_THR}%)" "$Z_LOW" "${colors[@]}") \
          && [ -n "$c" ] && Z_LOW="$c"
        ;;
      4)
        local t
        t=$(dialog --colors --title " High threshold " --menu \
          "\nBattery level at or above which the high color is shown:" 14 $WIDTH 5 \
          "30" "30%" "50" "50%" "70" "70%" "20" "20%" "10" "10%" 2>&1 >/dev/tty1)
        if [ -n "$t" ]; then
          HIGH_THR="$t"
          if [ "$LOW_THR" -ge "$HIGH_THR" ]; then
            LOW_THR=$((HIGH_THR - 10))
            [ "$LOW_THR" -lt 1 ] && LOW_THR=5
          fi
        fi
        ;;
      5)
        local t
        t=$(dialog --colors --title " Low threshold " --menu \
          "\nBattery level at or below which the low color is shown:" 14 $WIDTH 5 \
          "10" "10%" "20" "20%" "30" "30%" "5"  "5%" "1" "1%" 2>&1 >/dev/tty1)
        if [ -n "$t" ]; then
          if [ "$t" -ge "$HIGH_THR" ]; then
            dialog --colors --title " Invalid " --msgbox \
              "\nLow threshold must be below the high threshold." 7 $WIDTH >/dev/tty1
          else
            LOW_THR="$t"
          fi
        fi
        ;;
      6)
        local np
        np=$(dialog --colors --title " Blink period " --menu \
          "\nTime between color changes:" 15 $WIDTH 5 \
          "0.25" "0.25s (fast)" \
          "0.5"  "0.5s" \
          "1.0"  "1.0s (default)" \
          "2.0"  "2.0s (slow)" \
          2>&1 >/dev/tty1)
        [ -n "$np" ] && BLINK_PERIOD="$np"
        ;;
      7|"")
        local FNAME
        FNAME=$(GenerateUniversalProfile "$HIGH_THR" "$LOW_THR" "$Z_HIGH" "$Z_MID" "$Z_LOW" "$BLINK_PERIOD")
        if [ -n "$FNAME" ] && [ -f "$SCRIPT_DIR/$FNAME" ]; then
          if dialog --colors --title " Profile " --yesno \
            "\nGenerated:\n$FNAME\n\nApply now?" 11 $WIDTH >/dev/tty1; then
            ApplyLED "$FNAME"
            return
          fi
        else
          dialog --colors --title " Error " --msgbox \
            "\nFailed to generate profile." 6 $WIDTH >/dev/tty1
        fi
        ;;
    esac
  done
}

WizardLED() {
  dialog --colors --title " Diagnostic " --yesno \
    "\nThe wizard will test each available pin\nand ask what color you see on the LED.\n\n\ZbUnplug the charger first.\Zn\nYou can cancel at any time.\n\nStart?" 14 $WIDTH > /dev/tty1 || return

  local bstatus
  bstatus=$(cat "$BATT_DIR/status" 2>/dev/null)
  case "$bstatus" in
    Charging|Full|"Not charging")
      dialog --colors --title " Charger detected " --yesno \
        "\nThe charger seems connected.\nThe PMIC will light the LED and\nspoil the test.\n\nContinue anyway?" 11 $WIDTH > /dev/tty1 || return
      ;;
  esac

  if [ ! -f "$CORE_SRC" ]; then
    dialog --colors --title " Error " --msgbox \
      "\n$CORE_NAME not found in\n$SCRIPT_DIR" 8 $WIDTH > /dev/tty1
    return
  fi

  StopService
  OBS_FILE=$(mktemp /tmp/r36s_led_obs.XXXXXX)
  WIZ_PINS=""

  local -A res=()
  local pin st col base cancelled=0
  local -a probed=()

  dialog --colors --infobox "\n\nAll pins released.\n\nWatch the LED..." 9 $WIDTH > /dev/tty1
  sleep 2
  base=$(AskColor "Baseline" "All pins released.\nWhat color is the LED now?")
  if [ $? -ne 0 ] || [ -z "$base" ]; then
    WizardAbort
    return
  fi
  echo "- $base" >> "$OBS_FILE"

  for pin in "${PROBE_PINS[@]}"; do
    GPIOExport "$pin" || continue          
    for st in 0 1; do
      dialog --colors --infobox \
"\n\nTesting pin $pin\n\nDrive = $st\n\nWatch the LED..." 10 $WIDTH > /dev/tty1
      GPIOSet "$pin" out "$st"
      sleep 2
      col=$(AskColor "Pin $pin = $st")
      if [ $? -ne 0 ] || [ -z "$col" ]; then
        cancelled=1
        break
      fi
      res["$pin:$st"]="$col"
      echo "$pin=$st $col" >> "$OBS_FILE"
    done
    GPIOSet "$pin" in
    [ "$cancelled" = "1" ] && break
    probed+=("$pin")
  done
  if [ "$cancelled" = "1" ]; then
    WizardAbort
    return
  fi

  local lines="" n
  for pin in "${probed[@]}"; do
    n=0
    [ "${res[$pin:0]}" != "$base" ] && n=$((n + 1))
    [ "${res[$pin:1]}" != "$base" ] && n=$((n + 1))
    [ "$n" -gt 0 ] && lines+="$n $pin"$'\n'
  done
  local -a active=()
  mapfile -t active < <(printf '%s' "$lines" | sort -s -k1,1nr | head -n 2 | awk '{print $2}')

  if [ ${#active[@]} -eq 0 ]; then
    dialog --colors --title " Unavailable " --msgbox \
      "\nNo controllable LED behavior detected.\n\nAborting." 8 $WIDTH > /dev/tty1
    WizardAbort
    return
  fi

  if [ ${#active[@]} -eq 2 ]; then
    local a="${active[0]}" b="${active[1]}" sa sb
    for sa in 0 1; do
      for sb in 0 1; do
        dialog --colors --infobox \
"\n\nTesting pins $a + $b\n\n$a = $sa    $b = $sb\n\nWatch the LED..." 10 $WIDTH > /dev/tty1
        GPIOSet "$a" out "$sa"
        GPIOSet "$b" out "$sb"
        sleep 2
        col=$(AskColor "Pins $a=$sa  $b=$sb")
        if [ $? -ne 0 ] || [ -z "$col" ]; then
          cancelled=1
          break 2
        fi
        echo "$a=$sa,$b=$sb $col" >> "$OBS_FILE"
      done
    done
    GPIOSet "$a" in
    GPIOSet "$b" in
    if [ "$cancelled" = "1" ]; then
      WizardAbort
      return
    fi
  fi

  WIZ_PINS=$(IFS=,; echo "${active[*]}")

  local -a found_colors=()
  mapfile -t found_colors < <(python3 "$CORE_SRC" --solve "$OBS_FILE" --pins "$WIZ_PINS" 2>/dev/null)

  local usable=0 c
  for c in "${found_colors[@]}"; do
    [ "$c" != "off" ] && usable=1
  done
  if [ "$usable" = "0" ]; then
    dialog --colors --title " Unavailable " --msgbox \
      "\nNo controllable LED behavior detected.\n\nAborting." 8 $WIDTH > /dev/tty1
    WizardAbort
    return
  fi

  WizardColorPicker "${found_colors[@]}"
  [ -n "$OBS_FILE" ] && rm -f "$OBS_FILE" 2>/dev/null
  OBS_FILE=""
}

VariantMenu() {
  local prefix="$1" title="$2"
  while true; do
    mapfile -t files < <(ls -1 "$SCRIPT_DIR"/${prefix}*.py 2>/dev/null | xargs -n1 basename)
    if [ ${#files[@]} -eq 0 ]; then
      dialog --colors --title " $title " --msgbox \
        "\nNo scripts found for $title." 6 $WIDTH > /dev/tty1
      return
    fi
    local options=() i=1
    for f in "${files[@]}"; do
      options+=("$i" "$(profile_line "$f" "$(short_name "${f%.py}")")")
      i=$((i+1))
    done
    choice=$(dialog --colors \
      --backtitle " R36S LED Control " \
      --title " $title " \
      --no-collapse --clear \
      --ok-label "Apply" --cancel-label "Back" \
      --menu "" $HEIGHT $WIDTH 12 "${options[@]}" 2>&1 >/dev/tty1)
    [[ $? -ne 0 ]] && return

    local target="${files[$((choice - 1))]}"
    if ConfirmApply "$target"; then
      ApplyLED "$target"
    fi
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
      options+=("$i" "$(profile_line "$f" "$(short_name "${f%.py}")")")
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
      local target="${files[$((choice - 1))]}"
      if ConfirmApply "$target"; then
        ApplyLED "$target"
      fi
    fi
  done
}

WriteCore() {
  cat <<'PYEOF'
#!/usr/bin/env python3
import glob
import json
import os
import signal
import sys
import time

VERSION = 1

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
PYEOF
}

EnsureDefaults() {
  local created=0 name f

  if [ ! -f "$CORE_SRC" ] || ! grep -qx "VERSION = $CORE_VERSION" "$CORE_SRC" 2>/dev/null; then
    [ -f "$CORE_SRC" ] && sudo cp "$CORE_SRC" "${CORE_SRC}.bak"
    WriteCore | sudo tee "$CORE_SRC" >/dev/null
    created=$((created + 1))
  fi

  local -A profiles=(
    [Clone_Blue_30_Purple_10_Red]='core.run("clone", zones=[(30, "blue"), (11, "purple"), (0, "red")])'
    [Clone_Off_10_Red]='core.run("clone", zones=[(11, "off"), (0, "red")])'
    [Clone_Off_30_Purple_10_Red]='core.run("clone", zones=[(30, "off"), (11, "purple"), (0, "red")])'
    [Clone_PMIC_Controlled]='core.park()'
    [R36S_Green_10_Red]='core.run("r36s", zones=[(11, "off"), (0, "red")])'
    [R36S_Green_20_Red]='core.run("r36s", zones=[(21, "off"), (0, "red")])'
    [R36S_Green_30_Red]='core.run("r36s", zones=[(31, "off"), (0, "red")])'
    [R36S_PMIC_Controlled]='core.park()'
    [SoySauce_Blue_30_Pink_10_Red]='core.run("soysauce", zones=[(30, "blue"), (11, "pink"), (0, "red")])'
    [SoySauce_Off_10_Red]='core.run("soysauce", zones=[(11, "off"), (0, "red")])'
    [SoySauce_Off_30_Pink_10_Red]='core.run("soysauce", zones=[(30, "off"), (11, "pink"), (0, "red")])'
    [SoySauce_PMIC_Controlled]='core.park()'
  )

  for name in "${!profiles[@]}"; do
    f="$SCRIPT_DIR/$name.py"
    if [ ! -f "$f" ] || ! grep -q "batt_led_core" "$f" 2>/dev/null; then
      [ -f "$f" ] && sudo cp "$f" "${f}.bak"
      printf '%s\n' \
        '#!/usr/bin/env python3' \
        'import os, sys' \
        'sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))' \
        'import batt_led_core as core' \
        '' \
        "${profiles[$name]}" | sudo tee "$f" >/dev/null
      created=$((created + 1))
    fi
  done

  if [ "$created" -gt 0 ]; then
    sudo sync
    dialog --colors --infobox \
      "\n\nCreated/updated $created default file(s) in\n$SCRIPT_DIR" 8 $WIDTH > /dev/tty1
    sleep 1.5
  fi
}

MainMenu() {
  while true; do
    local model cur_file cur_swatches
    model=$(detect_model)
    cur_file=$(current_file)
    if [ -n "$cur_file" ]; then
      cur_swatches=$(profile_swatches "$cur_file")
    else
      cur_swatches="\Zn[ Device default ]\Zn"
    fi

    choice=$(dialog --colors \
      --backtitle " R36S LED Control " \
      --title " Main Menu " \
      --no-collapse --clear \
      --ok-label "Select" --cancel-label "Exit" \
      --menu "Model:  $model\nActive: $cur_swatches\n\nSelect a device family:" \
      $HEIGHT $WIDTH 11 \
      "1" "Clone" \
      "2" "R36S" \
      "3" "SoySauce" \
      "4" "Custom (generated profiles)" \
      "5" "Diagnose & Create Profile" \
      "6" "Remove LED (device control)" \
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
EnsureDefaults
trap ExitMenu EXIT
MainMenu