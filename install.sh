#!/bin/bash
# Duskfall-Dot installer (openSUSE Tumbleweed + Hyprland Lua config)
# Usage: git clone <repo> && cd <repo> && ./install.sh
#
# What it does:
#   1) Installs packages (if one is missing it retries one by one, the install never aborts)
#   2) Copies the repo's config/ and local/ folders into your home directory (existing ones are backed up)
#   3) Rewrites /home/<someone-else>/ paths to the current user's $HOME
#   4) Creates helper files (scripts, hypridle, dunst...) ONLY if they are missing,
#      so nothing you already customized is ever overwritten.
#
# Requires zypper, so it only works on openSUSE.

set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.config-backup-$STAMP"
FAILED=()

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
short() { printf '%s' "${1/#$HOME/\~}"; }

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run this script as root. Run it as a normal user (it will ask for sudo when needed)."
  exit 1
fi

if ! command -v zypper >/dev/null 2>&1; then
  echo "zypper not found. This installer only supports openSUSE."
  exit 1
fi

# Writes stdin to a file only if the file does not exist yet
write_if_missing() {
  local path="$1"
  if [ -e "$path" ]; then
    log "skipped (already exists): $(short "$path")"
    cat > /dev/null
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  cat > "$path"
  log "created: $(short "$path")"
}

install_pkgs() {
  sudo zypper --non-interactive install "$@" && return 0
  warn "Bulk install failed, retrying packages one by one..."
  local p
  for p in "$@"; do
    sudo zypper --non-interactive install "$p" || FAILED+=("$p")
  done
}

# ---------------------------------------------------------------- 1) PACKAGES
log "Installing core packages"
install_pkgs \
  hyprland hyprland-guiutils hyprlock hypridle hyprpaper waybar wofi kitty dunst wlogout \
  grim slurp wl-clipboard cliphist wf-recorder cava mpv \
  brightnessctl libnotify-tools pavucontrol blueman wireplumber \
  NetworkManager-connection-editor jq socat \
  xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland xdg-user-dirs \
  qt5ct qt6ct nwg-look adwaita-qt5 adwaita-qt6 \
  fontawesome-fonts symbols-only-nerd-fonts \
  dconf gsettings-desktop-schemas systemd-coredump fastfetch

log "Installing optional packages (failures are fine)"
for p in dolphin kate breeze6 plasma6-integration; do
  sudo zypper --non-interactive install "$p" || warn "Optional package could not be installed: $p"
done

# ---------------------------------------------------------------- 2) WAYPAPER
log "Installing Waypaper (wallpaper picker)"
PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}")' 2>/dev/null || echo 313)"
install_pkgs python3-pipx "python${PYVER}-gobject" typelib-1_0-Gtk-3_0
pipx install --system-site-packages waypaper || warn "Waypaper could not be installed (pipx error)"
pipx ensurepath >/dev/null 2>&1 || true

# ---------------------------------------------------------------- 3) COPY FILES
# The repo folders may be named "config", ".config" or "~/.config" (same for local)
find_src_dir() {
  local plain="${1#.}"
  local c
  for c in "$SRC/$plain" "$SRC/$1" "$SRC/~/$1"; do
    if [ -d "$c" ]; then echo "$c"; return 0; fi
  done
}

log "Copying files"
CONFIG_SRC="$(find_src_dir .config)"
LOCAL_SRC="$(find_src_dir .local)"
mkdir -p "$HOME/.config" "$HOME/.local/bin"

if [ -n "${CONFIG_SRC:-}" ]; then
  for d in "$CONFIG_SRC"/*; do
    name="$(basename "$d")"
    if [ -e "$HOME/.config/$name" ]; then
      mkdir -p "$BACKUP"
      cp -a "$HOME/.config/$name" "$BACKUP/" && log "backed up: ~/.config/$name -> $(short "$BACKUP")/"
    fi
  done
  cp -a "$CONFIG_SRC/." "$HOME/.config/"
else
  warn "No config folder found in the repo, skipping copy"
fi

if [ -n "${LOCAL_SRC:-}" ]; then
  cp -a "$LOCAL_SRC/." "$HOME/.local/"
else
  warn "No local folder found in the repo, skipping copy"
fi

# Rewrite another user's home paths to the current user's home
log "Fixing file paths to $HOME"
grep -rIl -E "/home/[A-Za-z0-9_.-]+/" \
  "$HOME/.config/hypr" "$HOME/.config/waybar" "$HOME/.config/dunst" \
  "$HOME/.config/wlogout" "$HOME/.config/wofi" "$HOME/.config/waypaper" \
  "$HOME/.local/bin" 2>/dev/null \
  | xargs -r sed -i -E "s|/home/[A-Za-z0-9_.-]+/|$HOME/|g"

[ -f "$HOME/.config/hypr/hyprland.lua" ] || warn "~/.config/hypr/hyprland.lua is missing! The repo config may not have been copied."

# ---------------------------------------------------------------- 4) HELPER SCRIPTS (if missing)
log "Checking helper scripts (~/.local/bin)"
BIN="$HOME/.local/bin"

write_if_missing "$BIN/osd.sh" << 'EOF'
#!/bin/bash
# Volume / brightness keys + dunst notification
case "$1" in
  vol-up)   wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ ;;
  vol-down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
  mute)     wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
  bri-up)   brightnessctl set 5%+ >/dev/null ;;
  bri-down) brightnessctl set 5%- >/dev/null ;;
esac

case "$1" in
  vol-*|mute)
    out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
    vol=$(echo "$out" | awk '{printf "%d", $2*100}')
    if echo "$out" | grep -q MUTED; then
      notify-send -h string:x-dunst-stack-tag:osd -h int:value:0 "Volume" "Muted"
    else
      notify-send -h string:x-dunst-stack-tag:osd -h int:value:$vol "Volume" "$vol%"
    fi ;;
  bri-*)
    bri=$(brightnessctl -m | cut -d, -f4 | tr -d %)
    notify-send -h string:x-dunst-stack-tag:osd -h int:value:$bri "Brightness" "$bri%" ;;
esac
EOF

write_if_missing "$BIN/screenshot.sh" << 'EOF'
#!/bin/bash
# Usage: screenshot.sh area | full
dir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"
mkdir -p "$dir"
file="$dir/$(date +%F_%H-%M-%S).png"

if [ "$1" = "area" ]; then
  region=$(slurp) || exit 0
  grim -g "$region" "$file" || exit 1
else
  grim "$file" || exit 1
fi

wl-copy < "$file"
notify-send -i "$file" "Screenshot taken" "Saved and copied to clipboard"
EOF

write_if_missing "$BIN/record.sh" << 'EOF'
#!/bin/bash
# Usage: record.sh full | area   (the same shortcut starts and stops the recording)
exec 9>/tmp/record.lock
flock -n 9 || exit 0

dir="$(xdg-user-dir VIDEOS 2>/dev/null || echo "$HOME/Videos")/Recordings"
mkdir -p "$dir"

# Already recording: stop it
if pgrep -x wf-recorder >/dev/null; then
  pkill -INT -x wf-recorder
  while pgrep -x wf-recorder >/dev/null; do sleep 0.2; done
  notify-send "Screen recording stopped" "Recording saved"
  exit 0
fi

file="$dir/$(date +%F_%H-%M-%S).mp4"
# openSUSE ships no libx264, so use libopenh264
opts=(-c libopenh264 -x yuv420p -f "$file")

if [ "$1" = "area" ]; then
  region=$(slurp) || exit 0
  opts=(-g "$region" "${opts[@]}")
fi

notify-send "Screen recording started" "Press the same shortcut to stop"
flock -u 9
exec wf-recorder "${opts[@]}" 2>/tmp/record.log
EOF

write_if_missing "$BIN/battery-watch.sh" << 'EOF'
#!/bin/bash
# Notifies when the charger is plugged in / unplugged and when the battery is low
exec 9>/tmp/battery-watch.lock
flock -n 9 || exit 0

bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1)
ac=$(grep -l Mains /sys/class/power_supply/*/type 2>/dev/null | head -n1 | xargs -r dirname)
[ -z "$bat" ] && exit 0
[ -z "$ac" ] && ac=/sys/class/power_supply/ACAD

last_ac=$(cat "$ac/online")
warned20=0; warned10=0

check() {
  cap=$(cat "$bat/capacity")
  online=$(cat "$ac/online")

  if [ "$online" != "$last_ac" ]; then
    if [ "$online" = "1" ]; then
      notify-send "Charger" "Charger plugged in (${cap}%)"
    else
      notify-send "Charger" "Charger unplugged (${cap}%)"
    fi
    last_ac="$online"
  fi

  if [ "$online" = "0" ]; then
    if [ "$cap" -le 10 ] && [ $warned10 -eq 0 ]; then
      notify-send -u critical "Battery critically low" "${cap}% left, plug in the charger!"; warned10=1
    elif [ "$cap" -le 20 ] && [ $warned20 -eq 0 ]; then
      notify-send -u normal "Battery low" "${cap}% left"; warned20=1
    fi
  else
    warned20=0; warned10=0
  fi
}

check
# React instantly to power events; fall back to a check every 60 s
udevadm monitor --udev --subsystem-match=power_supply 2>/dev/null | while read -r -t 60 _ || true; do
  check
done
EOF

write_if_missing "$BIN/crash-watch.sh" << 'EOF'
#!/bin/bash
# Notifies when an application crashes (needs systemd-coredump)
exec 9>/tmp/crash-watch.lock
flock -n 9 || exit 0

journalctl -f -n0 -o cat SYSLOG_IDENTIFIER=systemd-coredump 2>/dev/null | \
while read -r line; do
  case "$line" in
    *"Process "*"dumped core"*)
      app=$(echo "$line" | sed -E 's/.*\(([^)]+)\).*/\1/')
      notify-send -u critical "Application crashed" "$app closed unexpectedly"
      ;;
  esac
done
EOF

write_if_missing "$BIN/special-watch.sh" << 'EOF'
#!/bin/bash
# Waybar module: shows a star while the special workspace is open
sig="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t "$XDG_RUNTIME_DIR/hypr/" | head -n1)}"
sock="$XDG_RUNTIME_DIR/hypr/$sig/.socket2.sock"

print() {
  name=$(HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl monitors -j | jq -r '.[0].specialWorkspace.name')
  if [ -n "$name" ] && [ "$name" != "null" ]; then
    echo '{"text":"★","class":"special","tooltip":"Special workspace open"}'
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
EOF

write_if_missing "$BIN/cava-waybar.sh" << 'EOS'
#!/bin/bash
# Waybar module: cava bars (flat line when silent)
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
EOS

chmod +x "$BIN"/*.sh 2>/dev/null || true

# ---------------------------------------------------------------- 5) HYPR SIDE FILES (if missing)
log "Checking Hypr side files"

write_if_missing "$HOME/.config/hypr/hypridle.conf" << 'EOF'
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch dpms on
}

# 2.5 min: dim the screen
listener {
    timeout = 150
    on-timeout = brightnessctl -s set 10%
    on-resume = brightnessctl -r
}

# 5 min: lock
listener {
    timeout = 300
    on-timeout = loginctl lock-session
}

# 5.5 min: turn the screen off
listener {
    timeout = 330
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on
}

# 15 min: suspend
listener {
    timeout = 900
    on-timeout = systemctl suspend
}
EOF

write_if_missing "$HOME/.config/hypr/hyprlock.conf" << 'EOF'
general {
    hide_cursor = true
}

background {
    monitor =
    path = screenshot
    blur_passes = 3
    blur_size = 6
    brightness = 0.6
}

label {
    monitor =
    text = $TIME
    color = rgba(245, 236, 215, 1.0)
    font_size = 90
    font_family = Source Code Pro
    position = 0, 160
    halign = center
    valign = center
}

input-field {
    monitor =
    size = 300, 50
    outline_thickness = 2
    outer_color = rgba(245, 236, 215, 1.0)
    inner_color = rgba(28, 28, 30, 0.85)
    font_color = rgba(245, 236, 215, 1.0)
    check_color = rgba(224, 160, 48, 1.0)
    fail_color = rgba(200, 70, 70, 1.0)
    placeholder_text = Password
    fail_text = Wrong password
    rounding = 0
    position = 0, -40
    halign = center
    valign = center
}
EOF

# hyprpaper: hide the quote Hyprland draws on top of the wallpaper (splash)
HP="$HOME/.config/hypr/hyprpaper.conf"
if [ -f "$HP" ]; then
  grep -q '^splash' "$HP" || sed -i '1i splash = false' "$HP"
else
  mkdir -p "$(dirname "$HP")"
  echo "splash = false" > "$HP"
fi

# ---------------------------------------------------------------- 6) DUNST / WLOGOUT / WAYPAPER MENU (if missing)
write_if_missing "$HOME/.config/dunst/dunstrc" << 'EOF'
[global]
    follow = mouse
    width = (300, 650)
    height = (0, 200)
    origin = top-right
    offset = (16, 48)
    notification_limit = 5

    padding = 12
    horizontal_padding = 16
    frame_width = 2
    corner_radius = 0
    separator_height = 6
    separator_color = "#00000000"

    progress_bar = true
    progress_bar_height = 6
    progress_bar_frame_width = 0
    progress_bar_corner_radius = 0

    font = Source Code Pro 11
    format = "<b>%s</b>\n%b"
    alignment = left
    show_age_threshold = -1
    icon_position = left
    max_icon_size = 32
    sticky_history = no
    mouse_left_click = close_current
    mouse_right_click = close_all

[urgency_low]
    background = "#1c1c1ee6"
    foreground = "#cfc8b8"
    frame_color = "#595959"
    highlight = "#595959"
    timeout = 4

[urgency_normal]
    background = "#1c1c1ee6"
    foreground = "#f5ecd7"
    frame_color = "#f5ecd7"
    highlight = "#f5ecd7"
    timeout = 6

[urgency_critical]
    background = "#1c1c1ee6"
    foreground = "#ffffff"
    frame_color = "#e0a030"
    highlight = "#e0a030"
    timeout = 0
EOF

# Note: with Hyprland's Lua config, the old "hyprctl dispatch exit" does NOT work.
write_if_missing "$HOME/.config/wlogout/layout" << 'EOF'
{
    "label" : "lock",
    "action" : "loginctl lock-session",
    "text" : "Lock",
    "keybind" : "l"
}
{
    "label" : "hibernate",
    "action" : "systemctl hibernate",
    "text" : "Hibernate",
    "keybind" : "h"
}
{
    "label" : "logout",
    "action" : "hyprctl dispatch 'hl.dsp.exit()'",
    "text" : "Logout",
    "keybind" : "e"
}
{
    "label" : "shutdown",
    "action" : "systemctl poweroff",
    "text" : "Shutdown",
    "keybind" : "s"
}
{
    "label" : "suspend",
    "action" : "systemctl suspend",
    "text" : "Suspend",
    "keybind" : "u"
}
{
    "label" : "reboot",
    "action" : "systemctl reboot",
    "text" : "Reboot",
    "keybind" : "r"
}
EOF

# Make Waypaper show up in wofi/rofi (~ does not work in Exec=, so $HOME is expanded here)
mkdir -p "$HOME/.local/share/applications"
if [ ! -e "$HOME/.local/share/applications/waypaper.desktop" ]; then
  cat > "$HOME/.local/share/applications/waypaper.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Waypaper
Comment=Wallpaper picker
Exec=$HOME/.local/bin/waypaper
Icon=preferences-desktop-wallpaper
Terminal=false
Categories=Settings;
EOF
  log "created: ~/.local/share/applications/waypaper.desktop"
fi
rm -f "$HOME/.cache/wofi-drun"

# ---------------------------------------------------------------- 7) DARK THEME (GTK + Qt/KDE)
log "Setting up the dark theme"
write_if_missing "$HOME/.config/gtk-3.0/settings.ini" << 'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
EOF
write_if_missing "$HOME/.config/gtk-4.0/settings.ini" << 'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
EOF

# dconf can fail outside a running session, hence || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'   || true
gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'     || true
gsettings set org.gnome.desktop.interface cursor-size 24             || true
gsettings set org.gnome.desktop.sound event-sounds false             || true

# Make KDE apps (Dolphin, Kate) open dark under Hyprland
if command -v kwriteconfig6 >/dev/null 2>&1; then
  kwriteconfig6 --file kdeglobals --group General --key ColorScheme BreezeDark
  kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Breeze
  kwriteconfig6 --file knotifyrc  --group Sounds --key "No sound" true
else
  warn "kwriteconfig6 not found: set the KDE color scheme manually if Dolphin/Kate open white"
fi

# ---------------------------------------------------------------- 8) SERVICES
log "Configuring services"
sudo systemctl enable --now bluetooth || warn "Could not enable the bluetooth service"
# Waybar is started by the Hyprland autostart; disable the systemd unit to avoid two bars
systemctl --user disable --now waybar.service 2>/dev/null || true

# ---------------------------------------------------------------- DONE
echo
log "Installation finished."
if [ ${#FAILED[@]} -gt 0 ]; then
  warn "Packages that could not be installed (names may differ, try 'zypper search'): ${FAILED[*]}"
fi
[ -d "$BACKUP" ] && log "Backup of your previous configs: $(short "$BACKUP")"
cat << 'MSG'

Next steps:
  1) Log out and log back into Hyprland (needed for environment variables and autostart).
  2) Run 'waypaper' and pick a wallpaper folder (for example ~/Pictures/Wallpapers).
  3) If Waybar shows up twice, make sure hyprland.lua starts it only once.
  4) Autostart should contain: waybar, hyprpaper or waypaper --restore, dunst, hypridle,
     battery-watch.sh, crash-watch.sh and two "wl-paste --watch cliphist store" lines.
MSG
