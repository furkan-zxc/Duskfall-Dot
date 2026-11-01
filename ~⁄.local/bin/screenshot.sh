#!/bin/bash
dir=~/Pictures/Screenshots
mkdir -p "$dir"
file="$dir/$(date +%F_%H-%M-%S).png"

if [ "$1" = "area" ]; then
  region=$(slurp) || exit 0
  grim -g "$region" "$file" || exit 1
else
  grim "$file" || exit 1
fi

wl-copy < "$file"
notify-send -i "$file" "Screenshot taken"
