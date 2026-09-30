import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "chaz.todo"
  ipcTarget: "chaz.todo"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dimForeground: Qt.darker(contentForeground, 1.5)

  property var items: []
  property string view: "list"
  property string selectedId: ""
  property bool loaded: false
  property bool dirty: false
  property var deletionUndoStack: []
  readonly property int selectedIndex: indexOf(selectedId)
  readonly property int openCount: {
    var count = 0
    for (var i = 0; i < items.length; i++) if (!items[i].completed) count++
    return count
  }
  readonly property int completedCount: items.length - openCount
  readonly property var selectedItem: selectedIndex >= 0 ? items[selectedIndex] : null
  readonly property var detailItem: selectedItem || ({})

  onOpenedChanged: {
    if (opened) {
      if (items.length && selectedIndex < 0) selectedId = items[0].id
      focusKeyCatcher()
    } else {
      view = "list"
      selectedId = ""
    }
  }

  function indexOf(id) {
    for (var i = 0; i < items.length; i++) if (items[i] && items[i].id === id) return i
    return -1
  }
  function focusKeyCatcher() { Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
  function focusNameField() { Qt.callLater(function() { nameField.forceActiveFocus() }) }
  function focusEditDescription() { Qt.callLater(function() { editDescriptionField.forceActiveFocus() }) }

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/tathagat11.checklist-todo/"
  readonly property string savePath: stateDir + "todos.json"

  function applyLoaded(raw) {
    // A directory event can belong to this instance's previous atomic write
    // or another monitor. Never let it replace newer local mutations that are
    // still inside the save debounce window.
    if (loaded && dirty) return
    var next = Model.parse(raw)
    if (loaded && Model.serialize(next) === Model.serialize(items)) return
    items = next
    loaded = true
    if (opened && items.length && selectedIndex < 0) selectedId = items[0].id
  }
  function saveNow() { if (loaded) saveFile.setText(Model.serialize(items)) }
  function scheduleSave() { dirty = true; saveTimer.restart() }
  function reloadFromDisk() { saveFile.reload(); stateDirWatch.reload() }

  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", root.stateDir]
    onExited: Qt.callLater(root.reloadFromDisk)
  }
  FileView {
    id: saveFile
    path: root.savePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyLoaded(text())
    onLoadFailed: if (!root.loaded) root.applyLoaded("")
    onSaved: root.dirty = false
  }
  FileView {
    id: stateDirWatch
    path: root.stateDir
    watchChanges: true
    printErrors: false
    onFileChanged: if (!root.dirty) dirReloadTimer.restart()
  }
  Timer { id: dirReloadTimer; interval: 150; onTriggered: if (root.loaded && !root.dirty) saveFile.reload() }
  Timer { id: saveTimer; interval: 300; onTriggered: root.saveNow() }
  Component.onCompleted: ensureDirProc.running = true

  function addItem(name, description) {
    var cleanName = Model.squish(name)
    if (cleanName === "") return "empty"
    var next = items.slice()
    var item = { id: Model.makeId(), name: cleanName, description: Model.cleanDescription(description), completed: false }
    next.push(item)
    items = next
    selectedId = item.id
    scheduleSave()
    return cleanName
  }
  function replaceAt(index, item) {
    var next = items.slice()
    next[index] = item
    items = next
    scheduleSave()
  }
  function toggleItem(id) {
    var index = indexOf(id)
    if (index < 0) return
    var item = items[index]
    replaceAt(index, { id: item.id, name: item.name, description: item.description, completed: !item.completed })
  }
  function rememberDeletion() {
    var stack = deletionUndoStack.slice()
    stack.push({ items: items.slice(), selectedId: selectedId })
    if (stack.length > 20) stack.shift()
    deletionUndoStack = stack
  }
  function undoDeletion() {
    if (!deletionUndoStack.length) return
    var stack = deletionUndoStack.slice()
    var snapshot = stack.pop()
    deletionUndoStack = stack
    items = snapshot.items.slice()
    selectedId = snapshot.selectedId || (snapshot.items.length ? snapshot.items[0].id : "")
    scheduleSave()
  }
  function deleteItem(id) {
    var index = indexOf(id)
    if (index < 0) return
    rememberDeletion()
    var next = items.slice()
    next.splice(index, 1)
    items = next
    selectedId = next.length ? next[Math.min(index, next.length - 1)].id : ""
    scheduleSave()
  }
  function clearCompleted() {
    if (!completedCount) return
    rememberDeletion()
    var next = []
    for (var i = 0; i < items.length; i++) if (!items[i].completed) next.push(items[i])
    items = next
    selectedId = next.length ? next[0].id : ""
    scheduleSave()
  }
  function moveSelection(delta) {
    if (!items.length) return
    // Read from the source properties synchronously. The selectedIndex binding
    // can remain stale until the next QML evaluation pass when keys arrive in
    // a burst, which made rapid J/K presses reuse the previous row.
    var currentIndex = indexOf(selectedId)
    var nextIndex = currentIndex < 0 ? 0 : Math.max(0, Math.min(items.length - 1, currentIndex + delta))
    selectedId = items[nextIndex].id
    Qt.callLater(function() { listScroll.contentY = Math.max(0, Math.min(listScroll.contentHeight - listScroll.height, nextIndex * Style.space(46))) })
  }
  function reorderSelection(delta) {
    // Recompute after every mutation so auto-repeat and fast H/L sequences
    // always move the item from its actual current position.
    var from = indexOf(selectedId)
    var to = from + delta
    if (from < 0 || to < 0 || to >= items.length) return
    var next = items.slice()
    var moving = next[from]
    next.splice(from, 1)
    next.splice(to, 0, moving)
    items = next
    scheduleSave()
  }
  function activateSelection() {
    if (view === "list" && indexOf(selectedId) >= 0) toggleItem(selectedId)
  }
  function updateDescription(id, description) {
    var index = indexOf(id)
    if (index < 0) return false
    var item = items[index]
    replaceAt(index, {
      id: item.id,
      name: item.name,
      description: Model.cleanDescription(description),
      completed: item.completed
    })
    return true
  }
  function openDetail(id) { selectedId = id; view = "detail" }
  function beginEditDescription() {
    if (indexOf(selectedId) < 0) return
    editDescriptionField.text = detailItem.description || ""
    view = "edit"
    focusEditDescription()
  }
  function cancelEditDescription() { view = "detail"; focusKeyCatcher() }
  function saveEditDescription() {
    if (!updateDescription(selectedId, editDescriptionField.text)) { backToList(); return }
    view = "detail"
    focusKeyCatcher()
  }
  function beginCompose() {
    nameField.text = ""
    descriptionField.text = ""
    view = "compose"
    focusNameField()
  }
  function cancelCompose() { view = "list"; focusKeyCatcher() }
  function saveCompose() {
    if (addItem(nameField.text, descriptionField.text) === "empty") { focusNameField(); return }
    view = "list"
    focusKeyCatcher()
  }
  function backToList() { view = "list"; focusKeyCatcher() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(bodyColumn.implicitHeight, Style.space(540))

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        // Editors own every key while an entry is being composed.
        if (nameField.activeFocus || descriptionField.activeFocus || editDescriptionField.activeFocus) return

        if (event.key === Qt.Key_Escape) {
          if (root.view === "list") root.close()
          else if (root.view === "compose") root.cancelCompose()
          else if (root.view === "edit") root.cancelEditDescription()
          else root.backToList()
          event.accepted = true
          return
        }

        if (root.view === "detail") {
          if (event.key === Qt.Key_D) {
            root.backToList()
            event.accepted = true
          } else if (event.key === Qt.Key_E) {
            root.beginEditDescription()
            event.accepted = true
          }
          return
        }
        if (root.view !== "list") return

        var plain = event.modifiers === Qt.NoModifier
        if (plain && (event.key === Qt.Key_Left || event.key === Qt.Key_H)) {
          root.reorderSelection(-1)
          event.accepted = true
        } else if (plain && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) {
          root.reorderSelection(1)
          event.accepted = true
        } else if (plain && (event.key === Qt.Key_Up || event.key === Qt.Key_K)) {
          root.moveSelection(-1)
          event.accepted = true
        } else if (plain && (event.key === Qt.Key_Down || event.key === Qt.Key_J)) {
          root.moveSelection(1)
          event.accepted = true
        } else if (event.key === Qt.Key_D) {
          if (root.indexOf(root.selectedId) >= 0) root.openDetail(root.selectedId)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          root.activateSelection()
          event.accepted = true
        } else if (event.key === Qt.Key_X) {
          if (root.indexOf(root.selectedId) >= 0) root.deleteItem(root.selectedId)
          event.accepted = true
        } else if (event.key === Qt.Key_U) {
          root.undoDeletion()
          event.accepted = true
        } else if (event.key === Qt.Key_N || event.key === Qt.Key_Plus || event.text === "+") {
          root.beginCompose()
          event.accepted = true
        }
      }

      Flickable {
        id: listScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: bodyColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: bodyColumn
          width: listScroll.width
          spacing: Style.spacing.lg

          Column {
            visible: root.view === "list"
            width: parent.width
            spacing: Style.spacing.md

            Item {
              width: parent.width
              height: Math.max(title.implicitHeight, addButton.implicitHeight)
              Text {
                id: title
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Todos"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                anchors.right: clearButton.left
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: root.openCount + " open"
                color: root.dimForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
              Button {
                id: clearButton
                anchors.right: addButton.left
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: "Clear completed"
                visible: root.completedCount > 0
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.clearCompleted()
              }
              PanelActionButton {
                id: addButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰐕"
                tooltipText: "New todo"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.beginCompose()
              }
            }

            Text {
              visible: root.items.length === 0
              width: parent.width
              text: "Nothing here yet. Press + to add a todo."
              wrapMode: Text.WordWrap
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              topPadding: Style.spacing.md
              bottomPadding: Style.spacing.md
            }

            Repeater {
              model: root.items
              delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: bodyColumn.width
                height: Style.space(42)
                readonly property bool selected: root.selectedId === modelData.id

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: row.selected ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent"
                  border.width: row.selected ? 1 : 0
                  border.color: root.dimForeground
                }
                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openDetail(row.modelData.id)
                }
                Text {
                  id: checkbox
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.lg
                  anchors.verticalCenter: parent.verticalCenter
                  text: row.modelData.completed ? "󰄵" : "󰄱"
                  color: row.modelData.completed ? Color.accent : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.subtitle
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.spacing.sm
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) { root.selectedId = row.modelData.id; root.toggleItem(row.modelData.id); mouse.accepted = true }
                  }
                }
                Text {
                  anchors.left: checkbox.right
                  anchors.leftMargin: Style.spacing.controlGap
                  anchors.right: reorderButtons.left
                  anchors.rightMargin: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                  text: row.modelData.name
                  elide: Text.ElideRight
                  color: row.modelData.completed ? root.dimForeground : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.strikeout: row.modelData.completed
                }
                Row {
                  id: reorderButtons
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xs
                  PanelActionButton {
                    iconText: "󰁝"
                    tooltipText: "Move up (Left arrow or H)"
                    enabled: row.index > 0
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: { root.selectedId = row.modelData.id; root.reorderSelection(-1) }
                  }
                  PanelActionButton {
                    iconText: "󰁅"
                    tooltipText: "Move down (Right arrow or L)"
                    enabled: row.index < root.items.length - 1
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: { root.selectedId = row.modelData.id; root.reorderSelection(1) }
                  }
                }
              }
            }

            Text {
              visible: root.items.length > 0
              width: parent.width
              text: "↑/K and ↓/J select  •  ←/H and →/L reorder  •  D details  •  N/+ add  •  Space/Enter complete  •  X delete  •  U undo"
              wrapMode: Text.WordWrap
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            visible: root.view === "compose"
            width: parent.width
            spacing: Style.spacing.md
            Text { text: "New todo"; color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.title; font.bold: true }
            TextField {
              id: nameField
              width: parent.width
              placeholderText: "Name"
              foreground: root.contentForeground
              font.family: root.contentFontFamily
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.cancelCompose(); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { descriptionField.forceActiveFocus(); event.accepted = true }
              }
            }
            QQC.TextArea {
              id: descriptionField
              width: parent.width
              height: Style.space(120)
              placeholderText: "Description"
              wrapMode: TextEdit.Wrap
              color: root.contentForeground
              selectionColor: Color.accent
              selectedTextColor: root.contentForeground
              placeholderTextColor: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              padding: Style.spacing.md
              background: Rectangle {
                color: Style.controlFill(descriptionField.activeFocus, descriptionField.hovered, root.contentForeground, Color.accent)
                border.width: descriptionField.activeFocus ? 2 : 1
                border.color: descriptionField.activeFocus ? Color.accent : root.dimForeground
                radius: Style.cornerRadius
              }
              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) { root.cancelCompose(); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  if (event.modifiers & Qt.ControlModifier)
                    descriptionField.insert(descriptionField.cursorPosition, "\n")
                  else
                    root.saveCompose()
                  event.accepted = true
                }
              }
            }
            Text {
              text: "Enter saves  •  Ctrl+Enter adds a line"
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
            Row {
              anchors.right: parent.right
              spacing: Style.spacing.md
              Button { text: "Cancel"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: root.cancelCompose() }
              Button { text: "Save"; bordered: true; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: root.saveCompose() }
            }
          }

          Column {
            visible: root.view === "detail"
            width: parent.width
            spacing: Style.spacing.md
            Row {
              spacing: Style.spacing.md
              PanelActionButton { iconText: "󰁍"; tooltipText: "Back"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: root.backToList() }
              Text { text: root.detailItem.name || ""; color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.title; font.bold: true }
            }
            Text {
              width: parent.width
              text: root.detailItem.description || "No description."
              wrapMode: Text.WordWrap
              color: root.detailItem.description ? root.contentForeground : root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }
            Button {
              text: "Edit description"
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.beginEditDescription()
            }
            Text {
              text: "Press D to close details  •  E to edit"
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            visible: root.view === "edit"
            width: parent.width
            spacing: Style.spacing.md
            Text {
              text: "Edit description"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            QQC.TextArea {
              id: editDescriptionField
              width: parent.width
              height: Style.space(180)
              placeholderText: "Description"
              wrapMode: TextEdit.Wrap
              color: root.contentForeground
              selectionColor: Color.accent
              selectedTextColor: root.contentForeground
              placeholderTextColor: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              padding: Style.spacing.md
              background: Rectangle {
                color: Style.controlFill(editDescriptionField.activeFocus, editDescriptionField.hovered, root.contentForeground, Color.accent)
                border.width: editDescriptionField.activeFocus ? 2 : 1
                border.color: editDescriptionField.activeFocus ? Color.accent : root.dimForeground
                radius: Style.cornerRadius
              }
              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelEditDescription()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  if (event.modifiers & Qt.ControlModifier)
                    editDescriptionField.insert(editDescriptionField.cursorPosition, "\n")
                  else
                    root.saveEditDescription()
                  event.accepted = true
                }
              }
            }
            Text {
              text: "Enter saves  •  Ctrl+Enter adds a line"
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
            Row {
              anchors.right: parent.right
              spacing: Style.spacing.md
              Button { text: "Cancel"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: root.cancelEditDescription() }
              Button { text: "Save"; bordered: true; foreground: root.contentForeground; fontFamily: root.contentFontFamily; onClicked: root.saveEditDescription() }
            }
          }
        }
      }
    }
  }
}
