import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "Conditions.js" as Conditions
import "Palette.js" as Palette

// Fetch in the shell, as Omarchy's stock weather plugin does. The UI keeps
// its existing report shape, but there is no installed weather executable.
QtObject {
  id: root
  property string location: ""
  property string units: "imperial"
  property string iconSet: "nerd"
  readonly property string language: Model.language([Quickshell.env("LC_ALL"), Quickshell.env("LC_MESSAGES"), Quickshell.env("LANG")])
  readonly property string requestKey: Model.requestKey(location, units)
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/chaz-weather"
  readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
  property var report: null
  property string errorMessage: ""
  property bool busy: false
  property bool stale: false
  property var lastAttemptAt: null
  property bool ready: false
  property bool queued: false
  property string activeKey: ""
  property string activeLocation: ""
  property string activeUnits: "imperial"
  property var resolved: null
  property var entry: null
  property var cacheEntries: ({})
  property bool awaitingCache: false
  property bool cacheWritable: false
  property string stage: ""
  property string primaryTheme: ""
  property string legacyTheme: ""
  property bool primaryLoaded: false
  property bool legacyLoaded: false
  property string walTheme: ""
  readonly property var palette: Palette.palette(primaryLoaded ? primaryTheme : legacyLoaded ? legacyTheme : null, walTheme)

  onRequestKeyChanged: {
    // Never re-label old data with a new location or new units.
    entry = null
    report = null
    errorMessage = ""
    stale = false
    queued = true
    Qt.callLater(refresh)
  }
  onIconSetChanged: render()
  onPaletteChanged: render()

  function render() {
    if (!entry || entry.key !== requestKey) return
    try {
      var next = Model.normalize(entry, units, iconSet, language, palette, Conditions.condition)
      next.cache.stale = stale
      next.cache.stale_reason = stale ? "fetch_error" : null
      report = next
    } catch (e) { errorMessage = "Cached weather is invalid" }
  }
  function refresh() {
    if (!ready || busy) { queued = true; return }
    queued = false
    busy = true
    lastAttemptAt = new Date()
    activeKey = requestKey
    activeLocation = location
    activeUnits = units
    currentTheme.reload(); oldTheme.reload(); pywal.reload()
    entry = cacheEntries[activeKey] || null
    if (entry) { afterCache(); return }
    awaitingCache = true
    var path = cacheDir + "/" + Qt.md5(activeKey) + ".json"
    if (cache.path === path) cache.reload()
    else cache.path = path
  }
  function afterCache() {
    awaitingCache = false
    if (activeKey !== requestKey) { finish(); return }
    if (Model.fresh(entry, Date.now())) {
      stale = false; errorMessage = ""; render(); finish(); return
    }
    // Keep the prior report's freshness while fetching. On a cold start,
    // publish an expired disk entry only if the request actually fails.
    if (Model.automatic(activeLocation)) request("ipinfo", "https://ipinfo.io/json", 5)
    else request("geocode", Model.geocodeUrl(activeLocation), 10)
  }
  function request(kind, url, seconds) {
    stage = kind
    // Defer until the previous Process has fully stopped emitting signals.
    Qt.callLater(function() { http.get(url, kind, seconds) })
  }
  function acceptResponse(kind, body, error) {
    if (activeKey !== requestKey) { finish(); return }
    try {
      if (error) throw new Error(error)
      var data = Model.parse(body)
      if (kind !== "forecast") {
        resolved = Model.resolveLocation(data, kind, activeLocation)
        request("forecast", Model.forecastUrl(resolved, activeUnits), 10)
        return
      }
      Model.validateWeather(data)
      entry = { version: 1, key: activeKey, location: resolved, weather: data,
        fetchedAt: localTimestamp(new Date()) }
      cacheEntries[activeKey] = entry
      stale = false; errorMessage = ""; render()
      if (cacheWritable) {
        cache.path = cacheDir + "/" + Qt.md5(activeKey) + ".json"
        cache.setText(JSON.stringify(entry))
      }
      finish()
    } catch (e) {
      if (kind === "ipinfo") { request("ipwho", "https://ipwho.is/", 5); return }
      stale = true
      // The previous backend serves usable cached data as a successful
      // response with a stale marker, not as a separate error panel.
      errorMessage = entry ? "" : (kind === "forecast" ? "Forecast" : "Location") + ": " + String(e.message || "Invalid response")
      render()
      finish()
    }
  }
  function localTimestamp(d) {
    var offset = -d.getTimezoneOffset(), abs = Math.abs(offset)
    function pad(n) { return ("0" + n).slice(-2) }
    return Qt.formatDateTime(d, "yyyy-MM-ddTHH:mm:ss") + (offset >= 0 ? "+" : "-") + pad(Math.floor(abs / 60)) + ":" + pad(abs % 60)
  }
  function finish() {
    busy = false
    if (queued || activeKey !== requestKey) Qt.callLater(refresh)
  }

  property WeatherRequest http: WeatherRequest { onFinished: function(tag, body, error) { root.acceptResponse(tag, body, error) } }
  property FileView cache: FileView {
    path: ""
    printErrors: false
    atomicWrites: true
    onLoaded: {
      if (!root.awaitingCache) return
      root.entry = Model.cached(text(), root.activeKey)
      if (root.entry) root.cacheEntries[root.activeKey] = root.entry
      root.afterCache()
    }
    onLoadFailed: if (root.awaitingCache) root.afterCache()
  }
  property Process ensureCache: Process {
    command: ["mkdir", "-p", "-m", "700", root.cacheDir]
    onExited: function(code) { root.cacheWritable = code === 0; root.ready = true; Qt.callLater(root.refresh) }
  }
  property FileView currentTheme: FileView {
    path: root.stateDir + "/omarchy/current/theme/colors.toml"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { root.primaryTheme = text(); root.primaryLoaded = true }
    onLoadFailed: root.primaryLoaded = false
  }
  property FileView oldTheme: FileView {
    path: root.configDir + "/omarchy/current/theme/colors.toml"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { root.legacyTheme = text(); root.legacyLoaded = true }
    onLoadFailed: root.legacyLoaded = false
  }
  property FileView pywal: FileView {
    path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/wal/colors.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.walTheme = text()
    onLoadFailed: root.walTheme = ""
  }
  Component.onCompleted: ensureCache.running = true
}
