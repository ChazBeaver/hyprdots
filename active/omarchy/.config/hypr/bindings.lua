-- Personal keybindings layered over Omarchy Quattro defaults.

-- System actions.
o.bind("SUPER + R", "Restart Omarchy Shell", "omarchy restart shell")
hl.unbind("SUPER + ALT + CTRL + H")
o.bind("SUPER + ALT + CTRL + H", "Suspend System", "systemctl suspend")
o.bind("SUPER + ALT + CTRL + P", "Power Off System", "systemctl poweroff")

-- Replace Omarchy's legacy weather notification with Meteobar's panel.
hl.unbind("SUPER + CTRL + ALT + W")
o.bind("SUPER + CTRL + ALT + W", "Toggle Meteobar", "omarchy-shell shell toggle chaz-weather")

-- Theme menu uses a personal modifier chord.
hl.unbind("SUPER + SHIFT + CTRL + SPACE")
o.bind("SUPER + ALT + CTRL + SPACE", "Theme menu", "omarchy-menu toggle theme")

-- Focused-display brightness via Quattro's native hardware abstraction.
hl.unbind("SUPER + CTRL + UP")
o.bind("SUPER + CTRL + UP", "Brightness up", "omarchy brightness display +20%")
hl.unbind("SUPER + CTRL + DOWN")
o.bind("SUPER + CTRL + DOWN", "Brightness down", "omarchy brightness display 20%-")

-- Personal visual-mode cycle replaces Quattro's focused-window transparency toggle.
hl.unbind("SUPER + BACKSPACE")
o.bind("SUPER + BACKSPACE", "Cycle visual mode", "hypr-opacity-cycle")

-- Adjacent workspace and group navigation.
hl.unbind("SUPER + comma")
o.bind("SUPER + comma", "Workspace left", hl.dsp.focus({ workspace = "-1" }))
hl.unbind("SUPER + PERIOD")
o.bind("SUPER + PERIOD", "Workspace right", hl.dsp.focus({ workspace = "+1" }))

hl.unbind("SUPER + SHIFT + comma")
o.bind("SUPER + SHIFT + comma", "Move window one workspace left", hl.dsp.window.move({ workspace = "-1" }))
hl.unbind("SUPER + SHIFT + PERIOD")
o.bind("SUPER + SHIFT + PERIOD", "Move window one workspace right", hl.dsp.window.move({ workspace = "+1" }))

hl.unbind("SUPER + ALT + comma")
o.bind("SUPER + ALT + comma", "Previous grouped window", hl.dsp.group.prev())
hl.unbind("SUPER + ALT + PERIOD")
o.bind("SUPER + ALT + PERIOD", "Next grouped window", hl.dsp.group.next())

hl.unbind("SUPER + ALT + CTRL + comma")
o.bind("SUPER + ALT + CTRL + comma", "Move grouped window left", hl.dsp.group.move_window({ forward = false }))
hl.unbind("SUPER + ALT + CTRL + PERIOD")
o.bind("SUPER + ALT + CTRL + PERIOD", "Move grouped window right", hl.dsp.group.move_window({ forward = true }))

-- Notification controls use omarchy-shell instead of the retired Mako daemon.
hl.unbind("SUPER + SHIFT + ALT + M")
o.bind("SUPER + SHIFT + ALT + M", "Dismiss all notifications", "omarchy-shell notifications dismissAll")
hl.unbind("SUPER + SHIFT + ALT + N")
o.bind("SUPER + SHIFT + ALT + N", "Show last notification", "omarchy-shell notifications invokeLast")
hl.unbind("SUPER + CTRL + comma")
hl.unbind("SUPER + SHIFT + ALT + PERIOD")
o.bind_toggle("SUPER + SHIFT + ALT + PERIOD", "Toggle silencing notifications", "notification-silencing")

-- Applications and web apps.
hl.unbind("SUPER + ALT + SEMICOLON")
o.bind("SUPER + ALT + SEMICOLON", "Passwords", { launch = "keepassxc" })
o.bind("SUPER + ALT + L", "LocalSend", { launch = "localsend" })
o.bind("SUPER + ALT + A", "Claude", { webapp = "https://claude.ai/new" })

hl.unbind("SUPER + SHIFT + E")
o.bind("SUPER + SHIFT + E", "Gmail", { webapp = "https://www.gmail.com" })
hl.unbind("SUPER + SHIFT + C")
o.bind("SUPER + SHIFT + C", "Google Calendar", { webapp = "https://calendar.google.com/calendar/" })

hl.unbind("SUPER + SHIFT + W")
o.bind("SUPER + SHIFT + W", "LibreOffice Writer", { launch = "libreoffice --writer" })
o.bind("SUPER + ALT + W", "Typora", { launch = "typora --enable-wayland-ime" })

hl.unbind("SUPER + SHIFT + D")
o.bind("SUPER + SHIFT + D", "Discord", { launch = "gtk-launch Discord" })

o.bind("SUPER + ALT + N", "Projects editor", "omarchy-launch-editor $HOME/Projects/home")
o.bind("SUPER + ALT + D", "Docker", { tui = "lazydocker" })
o.bind("SUPER + ALT + Y", "Yazi tasks", [[ghostty -e yazi "$HOME/Documents/notes"]])
o.bind("SUPER + ALT + CTRL + Y", "Yazi projects", [[ghostty -e yazi "$HOME/Projects/home"]])
