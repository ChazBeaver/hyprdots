local state_home = os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")
local state_path = state_home .. "/hyprdots/opacity-mode"

local modes = {
  transparent = { blur = true, size = 4, passes = 2, active = 0.85, inactive = 0.75, fullscreen = 0.85 },
  blur = { blur = true, size = 2, passes = 2, active = 0.95, inactive = 0.90, fullscreen = 0.95 },
  opaque = { blur = false, size = 1, passes = 1, active = 1.00, inactive = 1.00, fullscreen = 1.00 },
}

local selected = "transparent"
local state_file = io.open(state_path, "r")
if state_file then
  local persisted = state_file:read("*l")
  state_file:close()
  if modes[persisted] then selected = persisted end
end

local mode = modes[selected]
hl.config({
  decoration = {
    active_opacity = mode.active,
    inactive_opacity = mode.inactive,
    fullscreen_opacity = mode.fullscreen,
    blur = {
      enabled = mode.blur,
      size = mode.size,
      passes = mode.passes,
      new_optimizations = true,
      xray = false,
      ignore_opacity = false,
    },
  },
})

-- These late rules intentionally beat Quattro app-specific opacity rules.
o.window(".*", { opacity = string.format("%.2f %.2f", mode.active, mode.inactive) })
o.window({ fullscreen = true }, { opacity = string.format("%.2f %.2f", mode.fullscreen, mode.fullscreen) })
