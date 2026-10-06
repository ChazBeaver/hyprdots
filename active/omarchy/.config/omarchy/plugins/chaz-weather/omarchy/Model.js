// Direct Open-Meteo model, following Omarchy's weather Model.js/Panel.qml.
// Presentation compatibility follows Meteobar 0.5.4; see ../UPSTREAM/LICENSE.
function optional(value) { return typeof value === "number" && isFinite(value) ? value : null }
function automatic(location) { return !String(location || "").trim() || String(location).trim().toLowerCase() === "auto" }
function requestKey(location, units) { return JSON.stringify([automatic(location) ? "" : String(location).trim(), units]) }
function locationParts(input) {
  var parts = String(input || "").split(",").map(function(v) { return v.trim() })
  return { name: parts[0] || input, qualifiers: parts.slice(1).filter(function(v) { return v !== "" }) }
}
function geocodeUrl(input) {
  var p = locationParts(input)
  return "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(p.name)
    + "&count=" + (p.qualifiers.length ? 5 : 1)
}
function resolvedLocation(name, lat, lon, region, country) {
  if (typeof name !== "string" || !name.trim() || optional(lat) === null || optional(lon) === null
      || Math.abs(lat) > 90 || Math.abs(lon) > 180) throw new Error("No usable location in the answer")
  return { latitude: lat, longitude: lon, name: [name, region, country].filter(function(p) {
    return typeof p === "string" && p !== ""
  }).join(", "), short: name }
}
function resolveLocation(data, source, input) {
  if (!data || typeof data !== "object") throw new Error("Invalid location response")
  if (source === "ipinfo") {
    var coords = String(data.loc || "").split(",")
    if (coords.length !== 2 || coords.some(function(v) { return v.trim() === "" })) throw new Error("No usable coordinates")
    return resolvedLocation(String(data.city || "").trim(), Number(coords[0]), Number(coords[1]), data.region, data.country)
  }
  if (source === "ipwho") {
    if (data.success !== true) throw new Error("Location lookup failed")
    return resolvedLocation(data.city, data.latitude, data.longitude, data.region, data.country_code)
  }
  var results = data.results || [], q = locationParts(input).qualifiers
  if (!results.length) throw new Error("No results for the configured location")
  var matches = results.filter(function(r) {
    return q.every(function(token) {
      if (token.length === 2) return String(r.country_code || "").toLowerCase() === token.toLowerCase()
      return [r.admin1, r.admin2, r.admin3, r.admin4, r.country].some(function(v) {
        return String(v || "").toLowerCase().indexOf(token.toLowerCase()) >= 0
      })
    })
  })
  var r = matches[0] || results[0]
  return resolvedLocation(r.name, r.latitude, r.longitude, r.admin1, r.country_code)
}
function forecastUrl(location, units) {
  return "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(location.latitude)
    + "&longitude=" + encodeURIComponent(location.longitude)
    + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,wind_direction_10m,pressure_msl,precipitation,uv_index"
    + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,wind_speed_10m_max,uv_index_max"
    + "&timezone=auto&forecast_days=6&hourly=temperature_2m,weather_code,precipitation_probability"
    + "&temperature_unit=" + (units === "imperial" ? "fahrenheit" : "celsius")
    + "&wind_speed_unit=" + (units === "imperial" ? "mph" : "kmh")
}
function parse(raw) {
  if (typeof raw !== "string" || raw.length > 1048576) throw new Error("Weather response exceeds the size limit")
  var data
  try { data = JSON.parse(raw) } catch (e) { throw new Error("Invalid JSON from weather service") }
  if (!data || typeof data !== "object" || data.error) throw new Error("Weather service returned an invalid response")
  return data
}
function validateWeather(data) {
  var c = data && data.current, d = data && data.daily, h = data && data.hourly
  if (!c || optional(c.temperature_2m) === null || optional(c.weather_code) === null || optional(c.is_day) === null)
    throw new Error("Current conditions are missing or invalid")
  function vectors(obj, required, numeric) {
    if (!obj || !Array.isArray(obj.time)) throw new Error("Forecast is missing")
    required.forEach(function(k) {
      if (!Array.isArray(obj[k]) || obj[k].length !== obj.time.length) throw new Error("Forecast arrays have mismatched lengths")
    })
    if (obj.time.some(function(v) { return typeof v !== "string" })) throw new Error("Invalid forecast time")
    numeric.forEach(function(k) {
      if (obj[k].some(function(v) { return optional(v) === null })) throw new Error("Invalid forecast value")
    })
  }
  vectors(d, ["weather_code", "temperature_2m_max", "temperature_2m_min", "sunrise", "sunset"], ["weather_code", "temperature_2m_max", "temperature_2m_min"])
  if (h) vectors(h, ["temperature_2m", "weather_code"], ["temperature_2m", "weather_code"])
  return data
}
function dayLabel(date, index, language) {
  var d = new Date(date + "T12:00:00Z")
  if (isNaN(d.getTime())) return date
  if (!index) return language === "de" ? "Heute" : "Today"
  return (language === "de" ? ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"] : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])[d.getUTCDay()] + " " + d.getUTCDate()
}
function normalize(entry, units, iconSet, language, palette, condition, now) {
  var w = validateWeather(entry.weather), c = w.current, d = w.daily, h = w.hourly
  var info = condition(c.weather_code, c.is_day === 1, iconSet, language)
  var current = {
    temperature: c.temperature_2m, feels_like: optional(c.apparent_temperature), humidity_pct: optional(c.relative_humidity_2m),
    wind_speed: optional(c.wind_speed_10m), wind_direction_deg: optional(c.wind_direction_10m),
    wind_direction: optional(c.wind_direction_10m) === null ? null : ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.max(0, Math.floor((c.wind_direction_10m + 22.5) / 45)) % 8],
    pressure: optional(c.pressure_msl), precipitation: optional(c.precipitation), uv_index: optional(c.uv_index),
    weather_code: c.weather_code, is_day: c.is_day === 1, icon: info.icon, description: info.description, condition: info.condition
  }
  var ref = c.time || (optional(w.utc_offset_seconds) !== null ? new Date((now || Date.now()) + w.utc_offset_seconds * 1000).toISOString().slice(0, 16) : "")
  var hourly = []
  for (var i = 0; h && i < h.time.length && hourly.length < 12; i++) {
    var time = h.time[i]
    if (ref && time < ref && time.slice(0, 13) !== ref.slice(0, 13)) continue
    var dayIndex = d.time.indexOf(time.slice(0, 10))
    var isDay = dayIndex < 0 || (time >= d.sunrise[dayIndex] && time < d.sunset[dayIndex])
    info = condition(h.weather_code[i], isDay, iconSet, language)
    hourly.push({ time: time, temperature: h.temperature_2m[i], weather_code: h.weather_code[i], is_day: isDay,
      icon: info.icon, description: info.description, precip_pct: optional((h.precipitation_probability || [])[i]) })
  }
  var daily = []
  for (var j = 0; j < d.time.length && j < 6; j++) {
    info = condition(d.weather_code[j], true, iconSet, language)
    daily.push({ date: d.time[j], temperature_min: d.temperature_2m_min[j], temperature_max: d.temperature_2m_max[j],
      weather_code: d.weather_code[j], icon: info.icon, description: info.description, label: dayLabel(d.time[j], j, language),
      precip_pct: optional((d.precipitation_probability_max || [])[j]), uv_index_max: optional((d.uv_index_max || [])[j]),
      sunrise: d.sunrise[j], sunset: d.sunset[j] })
  }
  return { location: entry.location.name, location_short: entry.location.short,
    units: { temperature: units === "imperial" ? "°F" : "°C", wind_speed: units === "imperial" ? "mph" : "km/h", pressure: "hPa" },
    icon_set: iconSet, current: current, hourly: hourly, daily: daily, palette: palette,
    cache: { fetched_at: entry.fetchedAt, stale: false, stale_reason: null } }
}
function cached(raw, key) {
  try {
    var e = parse(raw)
    if (e.version !== 1 || e.key !== key || !e.location || typeof e.location.name !== "string" || !isFinite(Date.parse(e.fetchedAt))) return null
    validateWeather(e.weather)
    return e
  } catch (e) { return null }
}
function fresh(entry, now) {
  var age = entry ? now - Date.parse(entry.fetchedAt) : -1
  return age >= 0 && age < 60000
}
function language(env) {
  for (var i = 0; i < env.length; i++) {
    var value = String(env[i] || "").trim()
    if (value) return value.split(/[_@.\-]/)[0].toLowerCase() === "de" ? "de" : "en"
  }
  return "en"
}
if (typeof module !== "undefined") module.exports = {
  automatic: automatic, requestKey: requestKey, geocodeUrl: geocodeUrl, resolveLocation: resolveLocation,
  forecastUrl: forecastUrl, parse: parse, validateWeather: validateWeather, normalize: normalize,
  cached: cached, fresh: fresh, language: language
}
