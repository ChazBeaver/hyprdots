// Meteobar 0.5.4's theme projection, retained for identical panel colors.
// MIT, copyright (c) 2026 mryll. See ../LICENSE.
function valid(value) { return typeof value === "string" && /^#(?:[\da-f]{3}|[\da-f]{4}|[\da-f]{6}|[\da-f]{8})$/i.test(value) }
function rgb(value) {
  var h = value.slice(1)
  if (h.length <= 4) h = h.split("").map(function(v) { return v + v }).join("")
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]
}
function hex(values) { return "#" + values.map(function(v) { return ("0" + Math.round(v).toString(16)).slice(-2) }).join("") }
function blend(a, b) {
  var x = rgb(a), y = rgb(b)
  return hex(x.map(function(v, i) { return (v + y[i]) / 2 }))
}
function thermal(text, hue) {
  // Rust uses f32 here. Match its rounding at every operation, including
  // half-channel boundaries that otherwise differ by one RGB value.
  var f = Math.fround, v = rgb(text).map(function(n) { return f(n / 255) })
  var l = Math.max(f(0.32), Math.min(f(0.72), f(f(Math.max.apply(null, v) + Math.min.apply(null, v)) / 2)))
  var c = f(f(1 - Math.abs(f(f(2 * l) - 1))) * f(0.55)), h = f(f(hue) * 6)
  var x = f(c * f(1 - Math.abs(f(f(h % 2) - 1)))), m = f(l - f(c / 2))
  var channels = [[c,x,0], [x,c,0], [0,c,x], [0,x,c], [x,0,c], [c,0,x]][Math.floor(h)]
  return hex(channels.map(function(n) { return f(Math.max(0, Math.min(1, f(n + m))) * 255) }))
}
function palette(toml, pywal) {
  var colors = { text: "#abb2bf", dim: "#5c6370", accent: "#61afef", green: "#98c379", yellow: "#e5c07b" }
  var map = {}, special = {}, wal = {}
  if (toml !== null) {
    String(toml).split("\n").forEach(function(line) {
      line = line.trim()
      if (!line || line[0] === "#") return
      var at = line.indexOf("=")
      if (at >= 0) map[line.slice(0, at).trim()] = line.slice(at + 1).trim().replace(/^"+|"+$/g, "")
    })
  } else {
    try { var parsed = JSON.parse(pywal || "{}"); special = parsed.special || {}; wal = parsed.colors || {} } catch (e) {}
    map = { foreground: special.foreground, background: special.background,
      accent: valid(wal.color4) ? wal.color4 : special.cursor, green: wal.color2, yellow: wal.color3 }
  }
  function first(keys, fallback) {
    for (var i = 0; i < keys.length; i++) if (valid(map[keys[i]])) return map[keys[i]]
    return fallback
  }
  colors.text = first(["foreground"], colors.text)
  colors.accent = first(["accent"], colors.accent)
  colors.green = first(["green", "color2"], colors.green)
  colors.yellow = first(["yellow", "color3"], colors.yellow)
  if (valid(map.foreground) && valid(map.background)) colors.dim = blend(map.foreground, map.background)
  return { text: colors.text, dim: colors.dim, accent: colors.accent,
    temp_cold: thermal(colors.text, 0.58), temp_warm: thermal(colors.text, 0.02),
    precip_ramp: [{ pct: 0, color: colors.green }, { pct: 30, color: colors.yellow }, { pct: 60, color: colors.accent }] }
}
if (typeof module !== "undefined") module.exports = { palette: palette }
