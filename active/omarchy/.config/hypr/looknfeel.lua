-- Keep Quattro's appearance, gaps, borders, and animations; square corners are
-- the only static personal appearance override.
hl.config({
  decoration = {
    rounding = 0,
  },
})

-- Opt another application in to Omarchy's standard transparency.
-- Find its class with: hyprctl clients
-- o.transparent_window("my-app")
-- o.transparent_window("my-app", "0.9 0.85") -- Custom active/inactive opacity.
