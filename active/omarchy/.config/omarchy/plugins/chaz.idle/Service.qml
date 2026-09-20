import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Wayland._IdleNotify

Item {
  id: root

  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stayAwakeStateDir: home + "/.local/state/omarchy/indicators"
  readonly property string stayAwakeStatePath: stayAwakeStateDir + "/stay-awake"
  readonly property var idleConfig: shell && shell.shellConfig && shell.shellConfig.idle ? shell.shellConfig.idle : ({})
  readonly property int lockTimeoutSeconds: secondsFromConfig(idleConfig.lock, 1800)
  readonly property int suspendTimeoutSeconds: Math.max(lockTimeoutSeconds, secondsFromConfig(idleConfig.suspend, 2700))
  readonly property int suspendDelaySeconds: suspendTimeoutSeconds - lockTimeoutSeconds
  readonly property bool idleEnabled: stayAwakeStateLoaded && !stayAwake

  property bool stayAwake: false
  property bool stayAwakeStateLoaded: false
  property bool inIdleCycle: false
  property bool hasPendingStayAwakePersist: false
  property bool pendingStayAwakePersist: false
  property string lastEvent: "starting"
  property string lastEventAt: ""

  function secondsFromConfig(value, fallback) {
    var parsed = Number(value)
    if (!isFinite(parsed) || parsed < 0) return fallback
    return Math.floor(parsed)
  }

  function logEvent(event) {
    root.lastEventAt = new Date().toISOString()
    root.lastEvent = event
    console.log("hyprdots idle " + root.lastEventAt + " " + event)
  }

  function startIdleCycle() {
    if (root.inIdleCycle || !root.idleEnabled) return
    root.inIdleCycle = true
    root.logEvent("lock-timeout")
    if (!lockProcess.running) lockProcess.running = true
    if (root.suspendDelaySeconds === 0) {
      if (!suspendProcess.running) suspendProcess.running = true
    } else {
      suspendTimer.restart()
    }
  }

  function cancelIdleCycle(reason) {
    suspendTimer.stop()
    if (root.inIdleCycle) root.logEvent("idle-cancelled: " + reason)
    root.inIdleCycle = false
  }

  function handleIdleChanged() {
    if (!root.idleEnabled) return
    if (idleMonitor.isIdle) root.startIdleCycle()
    else root.cancelIdleCycle("activity")
  }

  function persistStayAwake(value) {
    var command = value
      ? "mkdir -p \"$HOME/.local/state/omarchy/indicators\" && touch \"$HOME/.local/state/omarchy/indicators/stay-awake\""
      : "rm -f \"$HOME/.local/state/omarchy/indicators/stay-awake\""

    if (stayAwakeStateWriter.running) {
      root.pendingStayAwakePersist = !!value
      root.hasPendingStayAwakePersist = true
      return
    }
    stayAwakeStateWriter.command = ["bash", "-lc", command]
    stayAwakeStateWriter.running = true
  }

  function refreshStayAwakeState() {
    if (!stayAwakeStateProbe.running) stayAwakeStateProbe.running = true
  }

  function applyStayAwake(value, persist) {
    if (persist) root.persistStayAwake(value)
    root.stayAwake = !!value
    root.stayAwakeStateLoaded = true
    if (root.stayAwake) root.cancelIdleCycle("stay-awake")
    else Qt.callLater(root.handleIdleChanged)
    return root.stayAwake ? "disabled" : "enabled"
  }

  function statusJson() {
    return JSON.stringify({
      enabled: root.idleEnabled,
      stayAwake: root.stayAwake,
      idle: idleMonitor.isIdle,
      inIdleCycle: root.inIdleCycle,
      lock: root.lockTimeoutSeconds,
      suspend: root.suspendTimeoutSeconds,
      suspendTimer: suspendTimer.running,
      lastEvent: root.lastEvent,
      lastEventAt: root.lastEventAt
    })
  }

  IdleMonitor {
    id: idleMonitor
    enabled: root.idleEnabled
    timeout: root.lockTimeoutSeconds
    respectInhibitors: true
    onIsIdleChanged: root.handleIdleChanged()
  }

  Timer {
    id: suspendTimer
    interval: root.suspendDelaySeconds * 1000
    repeat: false
    onTriggered: {
      if (!root.idleEnabled || !root.inIdleCycle) return
      root.logEvent("suspend-timeout")
      if (!suspendProcess.running) suspendProcess.running = true
    }
  }

  Process {
    id: lockProcess
    command: ["bash", "-lc", "omarchy-system-lock"]
  }

  Process {
    id: suspendProcess
    command: ["systemctl", "suspend"]
  }

  Process {
    id: stayAwakeStateProbe
    command: ["bash", "-lc", "mkdir -p \"$HOME/.local/state/omarchy/indicators\"; [[ -f \"$HOME/.local/state/omarchy/indicators/stay-awake\" ]] && echo yes || echo no"]
    stdout: SplitParser {
      onRead: function(line) { root.applyStayAwake(String(line).trim() === "yes", false) }
    }
    onExited: function() { stayAwakeStateDirWatcher.reload() }
  }

  Process {
    id: stayAwakeStateWriter
    onExited: function() {
      if (root.hasPendingStayAwakePersist) {
        var pending = root.pendingStayAwakePersist
        root.hasPendingStayAwakePersist = false
        root.persistStayAwake(pending)
      } else {
        root.refreshStayAwakeState()
      }
    }
  }

  FileView {
    id: stayAwakeStateDirWatcher
    path: root.stayAwakeStateDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.refreshStayAwakeState()
  }

  Component.onCompleted: {
    root.logEvent("service-ready")
    root.refreshStayAwakeState()
  }

  IpcHandler {
    target: "idle"

    function status(): string { return root.statusJson() }
    function debug(): string { return root.statusJson() }
    function enable(): string { return root.applyStayAwake(false, true) }
    function disable(): string { return root.applyStayAwake(true, true) }
    function toggle(): string { return root.applyStayAwake(!root.stayAwake, true) }
  }
}
