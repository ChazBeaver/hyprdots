#!/bin/bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Script for changing blurs on the fly

notif="$HOME/.config/swaync/images/bell.png"

# Get the current state of "decoration:blur:passes"
STATE=$(hyprctl -j getoption decoration:blur:passes | jq ".int")

# Determine the next state in the cycle
NEXT_STATE=$(( (STATE % 3) + 1 ))

# Switch based on the next state
case $NEXT_STATE in
    1)
        hyprctl keyword decoration:blur:size 1
        hyprctl keyword decoration:blur:passes 1
        hyprctl keyword decoration:active_opacity 0.75
        hyprctl keyword decoration:inactive_opacity 0.65
        hyprctl keyword decoration:fullscreen_opacity 0.75
        notify-send -e -u low -i "$notif" "Transparent"
        ;;
    2)
        hyprctl keyword decoration:blur:size 4
        hyprctl keyword decoration:blur:passes 2
        hyprctl keyword decoration:active_opacity 0.85
        hyprctl keyword decoration:inactive_opacity 0.75
        hyprctl keyword decoration:fullscreen_opacity 0.85
        notify-send -e -u low -i "$notif" "Blur"
        ;;
    3)
        hyprctl keyword decoration:blur:size 50
        hyprctl keyword decoration:blur:passes 3
        hyprctl keyword decoration:active_opacity 3
        hyprctl keyword decoration:inactive_opacity 0.9
        hyprctl keyword decoration:fullscreen_opacity 3
        notify-send -e -u low -i "$notif" "Opaque"
        ;;
esac
