#!/bin/bash
exec 9>/tmp/cava-waybar.lock
flock -n 9 || exit 0

conf=/tmp/cava-waybar.conf
cat > "$conf" << CFG
[input]
method = pipewire
source = auto

[general]
bars = 12
framerate = 30

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
bar_delimiter = 59
CFG

bar="▁▂▃▄▅▆▇█"
dict="s/;//g;"
for ((i=0; i<${#bar}; i++)); do dict+="s/$i/${bar:$i:1}/g;"; done

trap 'pkill -P $$' EXIT
while true; do
  cava -p "$conf" | sed -u "$dict"
  echo "▁▁▁▁▁▁▁▁▁▁▁▁"
  sleep 2
done
