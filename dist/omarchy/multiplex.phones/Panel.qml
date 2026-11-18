import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "Where.js" as Where

// Multiplex in the Omarchy bar: a phone while one is connected, and a panel
// with the paired phones. All it knows comes from `multiplex devices
// --json`, and all it does is run the `multiplex` command; what it decides
// is in Model.js, where it is tested.
Panel {
  id: root
  moduleName: "multiplex.phones"
  ipcTarget: "multiplex.phones"
  manageIpc: false

  property var phones: []
  // The command answered the last time it was asked.
  property bool found: false
  // Asked, and no answer yet: still so at the next tick means the command
  // could not even be started.
  property bool waiting: false
  property int row: 0
  property int col: 0
  property bool cursorActive: false
  property string notice: ""
  property string ringing: ""

  readonly property var state: Model.summary(phones, found)
  // Coding agents on this computer that wait for an answer.
  property int agentsWaiting: 0
  readonly property string waitingWords: agentsWaiting > 0 ? strings.t("bar.waiting").arg(agentsWaiting) : ""
  readonly property bool showBattery: setting("showBattery", false) === true
  readonly property int every: Math.max(3, Math.min(600, Math.round(Number(setting("refreshIntervalSec", 10))) || 10))
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string statusText: sentence("status")
  readonly property string tooltip: sentence("tooltip")

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // "status" for the panel, "tooltip" for the bar: the same four states.
  function sentence(kind) {
    var now = Model.statusKey(root.state)
    var key = kind + "." + now.key
    return now.count < 0 ? strings.t(key) : strings.tn(key, now.count).arg(Commons.I18n.formatNumber(now.count))
  }

  function phoneStatus(phone) {
    if (!phone) return ""
    var text = strings.t(Model.phoneStatusKey(phone))
    return phone.battery === null ? text : text.arg(Commons.I18n.formatNumber(phone.battery))
  }

  function refresh() {
    if (listProc.running) return
    if (root.waiting) {
      root.found = false
      root.phones = []
    }
    root.waiting = true
    listProc.running = true
    if (!agentsProc.running) agentsProc.running = true
  }

  function setCursor(toRow, toCol) {
    root.row = toRow
    root.col = Math.max(0, Math.min(Model.columns(root.phones, toRow) - 1, toCol))
    root.cursorActive = true
  }

  function moveCursor(dx, dy) {
    var next = Model.move(root.phones, root.row, root.col, dx, dy)
    root.row = next.row
    root.col = next.col
  }

  // Ringing is asked here and answered in the panel; everything else opens
  // the Multiplex window, as its own program, and the panel steps aside.
  function run(place) {
    var argv = Model.command(Where.multiplex, place)
    if (argv.length === 0) return
    if (place.kind === "ring") {
      if (ringProc.running) return
      root.ringing = Model.shownName(place.phone)
      root.notice = ""
      ringProc.command = argv
      ringProc.running = true
      return
    }
    Quickshell.execDetached(["uwsm-app", "--"].concat(argv))
    root.close()
  }

  function toggleBattery() {
    root.settings = Object.assign({}, root.settings, { showBattery: !root.showBattery })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  ShellIpc {
    target: "multiplex.phones"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function refresh() { root.refresh() }
  }

  onOpenedChanged: {
    if (!opened) return
    root.notice = ""
    root.cursorActive = false
    root.row = 0
    root.col = 0
    root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: listProc
    command: [Where.multiplex, "devices", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.waiting = false
        root.phones = Model.parseDevices(text)
      }
    }
    onExited: function(exitCode) {
      root.found = exitCode === 0
    }
  }

  Process {
    id: agentsProc
    command: [Where.multiplex, "agents"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.agentsWaiting = Model.agentsWaiting(text)
    }
  }

  Process {
    id: ringProc
    onExited: function(exitCode) {
      root.notice = strings.t(exitCode === 0 ? "ring.asked" : "ring.failed").arg(root.ringing)
    }
  }

  // Often while the panel is open, seldom otherwise: asking costs about a
  // millisecond, but there is no reason to ask more than is looked at.
  Timer {
    interval: (root.opened ? 2 : root.every) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.icon(root.state)
    labelText: vertical ? "" : Model.withWaiting(Model.barLabel(root.state, root.showBattery), root.waitingWords)
    slotSize: Style.bar.iconSlot * (labelText !== "" ? 2 : 1)
    dimmed: root.state.connected === 0
    active: root.state.low
    tooltipText: root.opened ? "" : (root.agentsWaiting > 0 ? strings.tn("tooltip.agents", root.agentsWaiting).arg(root.agentsWaiting) + "\n" + root.tooltip : root.tooltip)
    onPressed: function(b) {
      if (b === Qt.RightButton) root.run({ kind: "open" })
      else if (b === Qt.MiddleButton) root.toggleBattery()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.run(Model.placeAt(root.phones, root.row, root.col))
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: Model.icon(root.state)
            color: root.state.connected > 0 ? (root.state.low ? root.urgent : root.foreground) : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: Style.duration(200) } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: strings.t("title")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.statusText.toUpperCase()
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.phones.length === 0
          width: parent.width
          text: root.found ? strings.t("hint.none") : strings.t("hint.missing")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator {
          visible: root.phones.length > 0
          foreground: root.foreground
        }

        Column {
          visible: root.phones.length > 0
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: strings.t("phones")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.phones
            PhoneRow {
              required property var modelData
              required property int index
              width: parent.width
              phone: modelData
              rowIndex: index
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.notice !== ""
            width: parent.width
            text: root.notice
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        Row {
          id: lastRow
          width: parent.width
          spacing: Style.space(6)
          readonly property bool rowHasCursor: root.cursorActive && root.row === root.phones.length

          Button {
            width: (lastRow.width - lastRow.spacing) / 2
            iconText: Model.GLYPH.pair
            text: strings.t("action.pair")
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: root.found
            hasCursor: lastRow.rowHasCursor && root.col === 0
            onHovered: function(isHovered) { if (isHovered) root.setCursor(root.phones.length, 0) }
            onClicked: root.run({ kind: "pair" })
          }

          Button {
            width: (lastRow.width - lastRow.spacing) / 2
            iconText: Model.GLYPH.open
            text: strings.t("action.open")
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: root.found
            hasCursor: lastRow.rowHasCursor && root.col === 1
            onHovered: function(isHovered) { if (isHovered) root.setCursor(root.phones.length, 1) }
            onClicked: root.run({ kind: "open" })
          }
        }
      }
    }
  }

  // One paired phone: who it is, how it is, and what can be done with it.
  // Its name is the phone's own word for itself, so it is shown as plain
  // text here and never passed to a tooltip.
  component PhoneRow: CursorSurface {
    id: phoneRow
    property var phone: null
    property int rowIndex: 0
    readonly property bool rowHasCursor: root.cursorActive && root.row === rowIndex
    readonly property bool low: Model.isLow(phone)

    hasCursor: rowHasCursor
    foreground: root.foreground
    implicitHeight: Math.max(labels.implicitHeight, sendButton.implicitHeight) + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) root.setCursor(phoneRow.rowIndex, root.row === phoneRow.rowIndex ? root.col : 0)
      onClicked: if (phoneRow.phone) root.run({ kind: "show", phone: phoneRow.phone.name })
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: phoneRow.phone && phoneRow.phone.connected ? Model.GLYPH.phone : Model.GLYPH.noPhone
        color: phoneRow.phone && phoneRow.phone.connected ? (phoneRow.low ? root.urgent : root.foreground) : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        // The two glyphs are not equally wide; the names beside them
        // should still start in one line.
        horizontalAlignment: Text.AlignHCenter
        Layout.preferredWidth: Math.ceil(Style.font.icon * 1.4)
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: labels
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: phoneRow.phone ? phoneRow.phone.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: root.phoneStatus(phoneRow.phone)
          color: phoneRow.low ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        id: sendButton
        iconText: Model.GLYPH.send
        tooltipText: strings.t("action.send")
        foreground: root.foreground
        fontFamily: root.fontFamily
        hasCursor: phoneRow.rowHasCursor && root.col === 0
        Layout.alignment: Qt.AlignVCenter
        onHovered: function(isHovered) { if (isHovered) root.setCursor(phoneRow.rowIndex, 0) }
        onClicked: if (phoneRow.phone) root.run({ kind: "send", phone: phoneRow.phone.name })
      }

      PanelActionButton {
        visible: !!phoneRow.phone && phoneRow.phone.connected
        iconText: Model.GLYPH.ring
        tooltipText: strings.t("action.ring")
        foreground: root.foreground
        fontFamily: root.fontFamily
        hasCursor: phoneRow.rowHasCursor && root.col === 1
        Layout.alignment: Qt.AlignVCenter
        onHovered: function(isHovered) { if (isHovered) root.setCursor(phoneRow.rowIndex, 1) }
        onClicked: if (phoneRow.phone) root.run({ kind: "ring", phone: phoneRow.phone.name })
      }
    }
  }
}
