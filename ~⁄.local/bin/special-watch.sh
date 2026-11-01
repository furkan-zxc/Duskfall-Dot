#!/bin/bash
sig="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t "$XDG_RUNTIME_DIR/hypr/" | head -n1)}"
sock="$XDG_RUNTIME_DIR/hypr/$sig/.socket2.sock"

print() {
  name=$(HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl monitors -j | jq -r '.[0].specialWorkspace.name')
  if [ -n "$name" ] && [ "$name" != "null" ]; then
    echo '{"text":"★","class":"special","tooltip":"Special workspace is open"}'
  else
    echo '{"text":"","class":"empty"}'
  fi
}

print
socat -u "UNIX-CONNECT:$sock" - | while read -r line; do
  case "$line" in
    activespecial*|workspace*|focusedmon*) print ;;
  esac
done
