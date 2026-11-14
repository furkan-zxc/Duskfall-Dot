#!/bin/bash
exec 9>/tmp/record.lock
flock -n 9 || exit 0

dir=~/Videos/Recordings
mkdir -p "$dir"

if pgrep -x wf-recorder >/dev/null; then
  pkill -INT -x wf-recorder
  while pgrep -x wf-recorder >/dev/null; do sleep 0.2; done
  notify-send "screen recording stopped" "recording saved"
  exit 0
fi

file="$dir/$(date +%F_%H-%M-%S).mp4"
opts=(-c libopenh264 -x yuv420p -f "$file")

if [ "$1" = "area" ]; then
  region=$(slurp) || exit 0
  opts=(-g "$region" "${opts[@]}")
fi

notify-send "Screen recording has started" "Press the same shortcut to stop"
flock -u 9
exec wf-recorder "${opts[@]}" 2>/tmp/record.log
