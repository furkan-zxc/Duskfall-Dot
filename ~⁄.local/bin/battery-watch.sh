#!/bin/bash
exec 9>/tmp/$(basename "$0").lock
flock -n 9 || exit 0
bat=$(ls -d /sys/class/power_supply/BAT* | head -n1)
ac=$(grep -l Mains /sys/class/power_supply/*/type | head -n1 | xargs dirname)

last_ac=$(cat "$ac/online")
warned20=0; warned10=0

check() {
  cap=$(cat "$bat/capacity")
  online=$(cat "$ac/online")

  if [ "$online" != "$last_ac" ]; then
    if [ "$online" = "1" ]; then
      notify-send "charger plugged in (%$cap)"
    else
      notify-send "charge" "charger removed (%$cap)"
    fi
    last_ac="$online"
  fi

  if [ "$online" = "0" ]; then
    if [ "$cap" -le 10 ] && [ $warned10 -eq 0 ]; then
      notify-send -u critical "battery is very low" "%$cap left, plug it in to charge!"; warned10=1
    elif [ "$cap" -le 20 ] && [ $warned20 -eq 0 ]; then
      notify-send -u normal "discharging" "%$cap left"; warned20=1
    fi
  else
    warned20=0; warned10=0
  fi
}

check
udevadm monitor --udev --subsystem-match=power_supply 2>/dev/null | while read -r -t 60 _ || true; do
  check
done
