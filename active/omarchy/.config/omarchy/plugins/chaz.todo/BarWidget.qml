import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "chaz.todo"

  property bool ipcRegistrationReady: false
  readonly property var panel: panelLoader.item
  readonly property bool opened: panel ? panel.opened === true : false
  readonly property int itemCount: panel ? panel.items.length : 0
  readonly property int openCount: panel ? panel.openCount : 0
  readonly property bool popoutSwitchClosing: panel ? panel.popoutSwitchClosing === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }
  function open() { if (panel) panel.open() }
  function close() { if (panel) panel.close() }
  function togglePanel() { if (panel) panel.toggle() }
  function closeForPopoutSwitch() { if (panel) panel.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onCompleted: ipcRegistrationTimer.start()

  Timer { id: ipcRegistrationTimer; interval: 100; onTriggered: root.ipcRegistrationReady = true }
  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  IpcHandler {
    enabled: root.ipcRegistrationReady
    target: root.moduleName
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function add(name: string, description: string): string {
      return root.panel ? root.panel.addItem(name, description) : "unavailable"
    }
    function remove(id: string): string {
      if (!root.panel) return "unavailable"
      root.panel.deleteItem(id)
      return "ok"
    }
    function clearCompleted(): string {
      if (!root.panel) return "unavailable"
      root.panel.clearCompleted()
      return "ok"
    }
    function status(): string {
      return root.openCount + " open, " + (root.itemCount - root.openCount) + " completed"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄲"
    fontSize: Style.bar.iconFont
    fixedWidth: root.vertical ? -1 : Style.bar.iconSlot
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    tooltipText: root.itemCount ? root.openCount + " open / " + root.itemCount + " total" : "Todo list"
    onPressed: function(pressedButton) {
      if (pressedButton === Qt.LeftButton) root.togglePanel()
    }
  }
}
