import QtQuick
import Quickshell.Io

// Omarchy's Process + StdioCollector fetch pattern with bounded output and
// completion ordering: stdout and process exit may arrive in either order.
QtObject {
  id: root
  property bool busy: false
  property bool outputDone: false
  property bool exited: false
  property int status: -1
  property string output: ""
  property string requestTag: ""
  signal finished(string tag, string body, string error)

  function get(url, tag, seconds) {
    if (busy) return false
    busy = true
    outputDone = false
    exited = false
    status = -1
    output = ""
    requestTag = tag
    process.command = ["curl", "--disable", "--fail", "--silent", "--show-error",
      "--proto", "=https", "--max-time", String(seconds), "--max-filesize", "1048576", url]
    watchdog.interval = (seconds + 2) * 1000
    watchdog.start()
    process.running = true
    // A missing executable emits neither started nor exited.
    Qt.callLater(function() { if (root.busy && !process.running && !root.exited) fallback.restart() })
    return true
  }
  function complete() {
    if (!busy || !outputDone || !exited) return
    busy = false
    fallback.stop()
    watchdog.stop()
    var error = status !== 0 ? "Request failed (curl exit " + status + ")" : ""
    if (!error && (!output.trim() || output.length > 1048576)) error = "Empty or oversized service response"
    finished(requestTag, error ? "" : output, error)
  }
  property Process process: Process {
    onRunningChanged: if (!running && root.busy) fallback.restart()
    onExited: function(code) { root.status = code; root.exited = true; root.complete() }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { root.output = text; root.outputDone = true; root.complete() }
    }
    // Do not forward curl's URLs/errors into logs or copied diagnostics.
    stderr: StdioCollector { waitForEnd: true }
  }
  property Timer fallback: Timer {
    interval: 300
    onTriggered: {
      if (!root.busy || process.running) return
      root.exited = true
      root.outputDone = true
      root.complete()
    }
  }
  property Timer watchdog: Timer {
    onTriggered: {
      process.running = false
      root.status = 28
      root.exited = true
      root.outputDone = true
      root.complete()
    }
  }
}
