# Hyprland Dotfiles (Beta)

You can get Hyprland ready for use by copying/cloning these configuration folders directly into your `~/.config/` directory.

This setup is designed to be tailored to your specific needs while embracing a minimalist style so don't be afraid to edit the code!

---

> [!WARNING]
> It is recommended to have a KDE Plasma environment already present on the system.
> **ATTENTION**
> These dotfiles have not been fully tested on other environments. You assume full responsibility for using or modifying them.

---

## Key Components Included
- **Window Manager:** Hyprland
- **Bar:** Waybar
- **Launcher:** Rofi
- **Terminal:** Kitty
- **Notification Daemon:** Dunst
- **Power Menu:** Wlogout
- **Wallpaper Manager:** Waypaper

## Quick Start
```bash
git clone [https://github.com/furkan-zxc/dotfiles.git](https://github.com/furkan-zxc/dotfiles.git)
cd dotfiles
# Copy the config files to ~/.config/
cp -r hypr waybar rofi kitty dunst wlogout waypaper ~/.config/
cp -r battery-watch.sh crash-watch.sh screenshot.sh special-watch.sh ~/.local/bin/
cp -r hyprland ~/.local/share/
