import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool passwordVisible: false
  property bool syncingPasswordText: false
  property string weatherText: ""

  readonly property string placeholderText: "Enter Password"
  readonly property string lockFontFamily: "FiraCode Nerd Font Mono"
  // This installed Fira Code build uses the default form for a slashed zero;
  // enabling the OpenType `zero` alternate selects the dotted form instead.
  readonly property var lockFontFeatures: ({ "zero": 0 })
  readonly property int fieldWidth: 160
  readonly property int fieldHeight: 27
  readonly property int fieldFontSize: Math.round(Style.font.heading * 0.5625)
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 0.665)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.095)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 6) : 0
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  // Cache-busts the lock background by appending `?v=`. Adding a query
  // string keeps Image's loader happy while forcing it to reload when the
  // user picks a new background mid-session.
  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function togglePasswordVisible() {
    passwordVisible = !passwordVisible
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: {
    syncPasswordText()
    if (passwordText.length === 0) passwordVisible = false
  }
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: root.lockFontFamily
    font.features: root.lockFontFeatures
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
      blur: 1.0
      blurMax: 128
      blurMultiplier: 1.25
      contrast: -0.08
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    Rectangle {
      id: inputField
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: Math.min(300, root.height * 0.3)
      color: "transparent"
      border.color: root.errorState ? Color.lock.borderError : Color.lock.borderActive
      border.width: 1
      radius: 6
      antialiasing: true
      opacity: passwordInput.text.length > 0 || root.authenticatingPassword || root.failureMessage.length > 0 ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: 140 }
      }

      TextInput {
        id: passwordInput
        anchors.fill: parent
        anchors.topMargin: inputField.border.width
        // Reserve the fingerprint icon's width on both sides so the centered
        // dots stay symmetric and never slide under the icon as they grow.
        anchors.rightMargin: inputField.border.width + 9 + root.fingerprintReserve
        anchors.bottomMargin: inputField.border.width
        anchors.leftMargin: inputField.border.width + 9 + root.fingerprintReserve
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        activeFocusOnPress: true
        clip: true
        enabled: root.inputEnabled && !root.authenticatingPassword
        readOnly: root.authenticatingPassword
        echoMode: root.passwordVisible ? TextInput.Normal : TextInput.Password
        passwordCharacter: "\u25CF"
        passwordMaskDelay: 0
        color: Color.lock.text
        selectionColor: Color.lock.selection
        selectedTextColor: Color.lock.text
        font.family: root.lockFontFamily
        font.features: root.lockFontFeatures
        font.pixelSize: text.length > 0 && !root.passwordVisible ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
        font.letterSpacing: text.length > 0 && !root.passwordVisible ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
        cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
        cursorDelegate: Rectangle {
          width: 2
          color: Color.lock.text
          visible: passwordInput.cursorVisible
        }

        onTextChanged: {
          if (!root.syncingPasswordText) root.passwordTextEdited(text)
          if (text.length > 0) {
            root.wakeRequested()
          }
          if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
        }

        onAccepted: {
          var submitted = root.passwordText
          root.passwordTextEdited("")
          if (submitted.length > 0) root.submitPassword(submitted)
        }

        Keys.onPressed: function(event) {
          root.wakeRequested()
          if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
            root.passwordTextEdited("")
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_E) {
            root.togglePasswordVisible()
            event.accepted = true
          }
        }
      }

      Text {
        anchors.fill: passwordInput
        text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
        visible: passwordInput.text.length === 0
        color: root.authenticatingPassword ? Color.lock.text : (root.failureMessage.length > 0 ? Color.lock.textError : Color.lock.placeholder)
        font.family: root.lockFontFamily
        font.features: root.lockFontFeatures
        font.pixelSize: root.fieldFontSize
        font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }

      // Fingerprint hint pinned inside the field's right edge when a sensor is
      // enrolled, so the user knows they can touch to unlock instead of typing.
      // Matches hyprlock, which draws its fingerprint icon in the same spot.
      Text {
        id: fingerprintIcon
        objectName: "fingerprintIndicator"
        anchors.right: parent.right
        anchors.rightMargin: inputField.border.width + 9
        anchors.verticalCenter: parent.verticalCenter
        visible: root.fingerprintConfigured
        text: "󰈷"
        color: Color.lock.placeholder
        // Keep the Nerd Font here because this character is an icon glyph.
        font.family: Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }

    Column {
      id: clockAndDate
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -Math.min(90, root.height * 0.09)
      spacing: Math.max(8, root.height * 0.012)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDateTime(lockClock.date, "hh:mmAP")
        color: "white"
        font.family: root.lockFontFamily
        font.features: root.lockFontFeatures
        font.pixelSize: Math.min(360, root.height * 0.3)
        font.weight: Font.Light
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDateTime(lockClock.date, "dddd, MMMM d")
        color: Color.lock.text
        font.family: root.lockFontFamily
        font.features: root.lockFontFeatures
        font.pixelSize: Math.min(50, root.height * 0.046)
      }

    }

    Text {
      id: weather
      anchors.horizontalCenter: parent.horizontalCenter
      // Place the weather almost halfway from the date to the password field.
      y: clockAndDate.y + clockAndDate.height
        + ((inputField.y - (clockAndDate.y + clockAndDate.height)) * 0.45)
        - (height / 2)
      visible: root.weatherText.length > 0
      text: root.weatherText
      color: Color.lock.placeholder
      font.family: root.lockFontFamily
      font.features: root.lockFontFeatures
      font.pixelSize: Math.min(30, root.height * 0.03)
    }
  }

  SystemClock {
    id: lockClock
    precision: SystemClock.Seconds
  }

  Process {
    id: weatherProcess
    command: ["omarchy-weather-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.weatherText = String(text || "").trim()
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.weatherText = ""
    }
  }

  Timer {
    interval: 600000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!weatherProcess.running) weatherProcess.running = true
  }
}
