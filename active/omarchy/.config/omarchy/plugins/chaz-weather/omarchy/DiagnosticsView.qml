pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  required property color foreground
  required property color statusColor
  required property string fontFamily
  required property string status
  required property var rows
  property bool testing: false
  property bool copied: false

  signal testRequested()
  signal copyRequested()

  spacing: Style.space(14)

  Row {
    width: root.width
    spacing: Style.space(10)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "󰋼"
      textFormat: Text.PlainText
      color: root.statusColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.iconLarge
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        text: "WEATHER DIAGNOSTICS"
        textFormat: Text.PlainText
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
      }

      Text {
        text: root.status
        textFormat: Text.PlainText
        color: root.statusColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
    }
  }

  PanelSeparator {
    foreground: root.foreground
  }

  Column {
    width: root.width
    spacing: Style.space(12)

    Repeater {
      model: root.rows

      Item {
        id: diagnosticRow
        required property var modelData
        width: root.width
        implicitHeight: Math.max(rowLabel.implicitHeight, rowValue.implicitHeight)
        height: implicitHeight

        Text {
          id: rowLabel
          x: Style.space(12)
          width: Style.space(142)
          text: diagnosticRow.modelData.label.toUpperCase()
          textFormat: Text.PlainText
          color: Qt.darker(root.foreground, 1.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        Text {
          id: rowValue
          x: Style.space(170)
          width: Math.max(0, diagnosticRow.width - x - Style.space(12))
          text: diagnosticRow.modelData.value
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  PanelSeparator {
    foreground: root.foreground
  }

  Item {
    width: root.width
    implicitHeight: Math.max(actionHint.implicitHeight, actionButtons.implicitHeight)
    height: implicitHeight

    Text {
      id: actionHint
      anchors.left: parent.left
      anchors.right: actionButtons.left
      anchors.rightMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      text: root.testing ? "Checking weather services…" : "Checks run only on demand"
      textFormat: Text.PlainText
      color: Qt.darker(root.foreground, 1.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      id: actionButtons
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      PanelActionButton {
        iconText: "󰆏"
        tooltipText: root.copied ? "Copied" : "Copy diagnostic report"
        foreground: Qt.darker(root.foreground, 1.55)
        hoverColor: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        size: Style.space(20)
        onClicked: root.copyRequested()
      }

      PanelActionButton {
        iconText: "󰑐"
        tooltipText: "Test now"
        foreground: Qt.darker(root.foreground, 1.55)
        hoverColor: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        size: Style.space(20)
        enabled: !root.testing
        onClicked: root.testRequested()
      }
    }
  }
}
