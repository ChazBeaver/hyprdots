-- Personal Hyprland entrypoint for Omarchy Quattro.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Load the supported Omarchy baseline first, then personal overrides.
require("default.hypr.omarchy")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.privacy")

-- Preserve Omarchy's dynamic toggles, but make the persisted personal opacity
-- mode authoritative by loading it last.
require("default.hypr.toggles")
require("hypr.opacity")
