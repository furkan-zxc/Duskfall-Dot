#!/bin/bash
exec 9>/tmp/$(basename "$0").lock
flock -n 9 || exit 0
journalctl -f -n0 -o cat SYSLOG_IDENTIFIER=systemd-coredump 2>/dev/null | \
while read -r line; do
  case "$line" in
    *"Process "*"dumped core"*)
      app=$(echo "$line" | sed -E 's/.*\(([^)]+)\).*/\1/')
      notify-send -u critical "the application crashed!" "$app closed unexpectedly"
      ;;
  esac
done
