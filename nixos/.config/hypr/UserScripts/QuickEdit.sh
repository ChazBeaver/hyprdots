#!/bin/bash
# Rofi menu for Quick Edit / View of Settings (SUPER E)

# define your preferred text editor and terminal to use
editor=${EDITOR:-nvim}
tty=kitty

configs="$HOME/.config/hypr/configs"
UserConfigs="$HOME/.config/hypr/UserConfigs"
UserScripts="$HOME/.config/hypr/UserScripts"
Waybar="$HOME/.config/waybar"
Scripts="$HOME/.config/hypr/scripts"

menu(){
  printf "1. edit Env-variables\n"
  printf "2. edit Window-Rules\n"
  printf "3. edit Startup_Apps\n"
  printf "4. edit User-Keybinds\n"
  printf "5. edit Monitors\n"
  printf "6. edit Laptop-Keybinds\n"
  printf "7. edit User-Settings\n"
  printf "8. edit Decorations & Animations\n"
  printf "9. edit Workspace-Rules\n"
  printf "10. edit Default-Settings\n"
  printf "11. edit Default-Keybinds\n"
  printf "12. edit RofiBeats Music Stations\n"
  printf "13. edit Quick Files Menu\n"
  printf "14. edit Waybar Modules\n"
  printf "15. edit Help Legend/Key Hints\n"
  printf "16. edit NixOS-Hyprland\n"
  printf "17. edit app-dotfiles\n"
  printf "18. edit hypr-dotfiles\n"
  printf "19. yazi Projects\n"
}

main() {
    choice=$(menu | rofi -i -dmenu -config ~/.config/rofi/config-compact.rasi | cut -d. -f1)
    case $choice in
        1)
            $tty $editor "$UserConfigs/ENVariables.conf"
            ;;
        2)
            $tty $editor "$UserConfigs/WindowRules.conf"
            ;;
        3)
            $tty $editor "$UserConfigs/Startup_Apps.conf"
            ;;
        4)
            $tty $editor "$UserConfigs/UserKeybinds.conf"
            ;;
        5)
            $tty $editor "$UserConfigs/Monitors.conf"
            ;;
        6)
            $tty $editor "$UserConfigs/Laptops.conf"
            ;;
        7)
            $tty $editor "$UserConfigs/UserSettings.conf"
            ;;
        8)
            $tty $editor "$UserConfigs/UserDecorAnimations.conf"
            ;;
        9)
            $tty $editor "$UserConfigs/WorkspaceRules.conf"
            ;;            
		    10)
            $tty $editor "$configs/Settings.conf"
            ;;
        11)
            $tty $editor "$configs/Keybinds.conf"
            ;;
        12)
            $tty $editor "$UserScripts/RofiBeats.sh"
            ;;
        13)
            $tty $editor "$UserScripts/QuickEdit.sh"
            ;;
        14)
            $tty $editor "$Waybar/Modules"
            ;;
        15)
            $tty $editor "$Scripts/KeyHints.sh"
            ;;
        16)
            $tty $editor "/home/chaz/Documents/Chaz_Hyprland/NixOS-Hyprland"
            ;;
        17)
            $tty $editor "/home/chaz/Projects/app-dotfiles"
            ;;
        18)
            $tty $editor "/home/chaz/Projects/hypr-dotfiles"
            ;;
        19)
            $tty "yazi" "/home/chaz/Projects"
            ;;
        *)
            ;;
    esac
}

main
