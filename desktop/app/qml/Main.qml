import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import io.github.molotovgit.multiplex

// The Multiplex window: the paired phones on the left, the one picked on
// the right with what can be done with it. Everything it shows and does
// comes from the Backend (Rust); this file is layout and keys only.
ApplicationWindow {
    id: win
    width: 900
    height: 680
    minimumWidth: 720
    minimumHeight: 560
    visible: true
    title: "Multiplex"
    color: "#0e0e10"

    Material.theme: Material.Dark
    Material.accent: backend.accent
    Material.roundedScale: backend.radius

    Backend { id: backend }

    readonly property color ink: "#f2f2f4"
    readonly property color muted: "#8e8e96"
    readonly property color panel: "#17171a"
    readonly property color line: "#2a2a30"
    readonly property color good: "#3ddc84"
    readonly property color warn: "#ffb347"

    function parsed(text, otherwise) {
        try {
            return JSON.parse(text)
        } catch (e) {
            return otherwise
        }
    }

    readonly property var phones: parsed(backend.phones, [])
    readonly property var access: parsed(backend.access, ({}))
    readonly property var checks: parsed(backend.checks, [])
    readonly property var kept: parsed(backend.kept, [])
    readonly property var pairing: parsed(backend.pairing, ({}))
    property int picked: 0
    readonly property var phone: phones.length > 0 ? phones[Math.min(picked, phones.length - 1)] : null
    // "", "pair", "checks", "kept", "help" or "unpair"
    property string overlay: ""
    property int now: Math.floor(Date.now() / 1000)

    readonly property var switches: [
        { key: "desktop", title: qsTr("Desktop"), what: qsTr("See this computer's screen: the panel, and with Input the remote desktop") },
        { key: "input", title: qsTr("Input"), what: qsTr("Act here: the panel's buttons, the touchpad, the remote desktop") },
        { key: "files", title: qsTr("Files"), what: qsTr("Browse, send and fetch files") },
        { key: "clipboard", title: qsTr("Clipboard"), what: qsTr("Share the clipboard, open links, read the text in a picture") },
        { key: "terminal", title: qsTr("Terminal"), what: qsTr("A shell, and any other command") },
        { key: "tunnels", title: qsTr("Tunnels"), what: qsTr("Forward ports") }
    ]

    function allowed(key) {
        if (!phone)
            return false
        var its = access[phone.name]
        return its === undefined ? true : its[key] !== false
    }

    function status(p) {
        if (!p.connected)
            return qsTr("Not connected")
        if (p.battery === null || p.battery === undefined)
            return qsTr("Connected")
        return p.charging ? qsTr("Connected · %1%, charging").arg(p.battery) : qsTr("Connected · %1%").arg(p.battery)
    }

    function countdown(until) {
        var left = Math.max(0, until - now)
        var seconds = left % 60
        return Math.floor(left / 60) + ":" + (seconds < 10 ? "0" : "") + seconds
    }

    function pair() {
        overlay = "pair"
        backend.startPairing()
    }

    function closeOverlay() {
        if (overlay === "pair" && pairing.code !== undefined)
            backend.cancelPairing()
        else if (overlay === "pair")
            backend.pairing = "{}"
        overlay = ""
    }

    function pick(step) {
        if (phones.length > 0)
            picked = Math.max(0, Math.min(phones.length - 1, picked + step))
    }

    // Everything the window can be asked to do, by key, by button, or (for
    // its tests) by name.
    function act(what) {
        if (what === "help")
            overlay = overlay === "help" ? "" : "help"
        else if (what === "close")
            closeOverlay()
        else if (what === "confirm" && overlay === "unpair" && phone !== null) {
            backend.unpair(phone.name)
            picked = 0
            overlay = ""
        } else if (overlay !== "")
            return
        else if (what === "pair")
            pair()
        else if (what === "checks") {
            overlay = "checks"
            backend.checkComputer()
        } else if (what === "kept") {
            overlay = "kept"
            backend.readKept()
        } else if (what.indexOf("phone:") === 0) {
            // By name: the bar widget opens the window on one phone.
            for (var i = 0; i < phones.length; i++)
                if (phones[i].name === what.substring(6))
                    picked = i
        } else if (what === "up")
            pick(-1)
        else if (what === "down")
            pick(1)
        else if (phone === null)
            return
        else if (what === "send")
            backend.chooseAndSend(phone.name)
        else if (what === "ring")
            backend.ring(phone.name)
        else if (what === "unpair")
            overlay = "unpair"
        else if (what.indexOf("switch:") === 0) {
            var one = switches[parseInt(what.substring(7)) - 1]
            if (one !== undefined)
                backend.allow(phone.name, one.key, !allowed(one.key))
        } else if (what.indexOf("drop:") === 0)
            backend.sendFiles(phone.name, what.substring(5))
    }

    onPairingChanged: {
        if (pairing.paired !== undefined) {
            backend.notice = qsTr("Paired with %1.").arg(pairing.paired)
            backend.pairing = "{}"
            overlay = ""
            for (var i = 0; i < phones.length; i++) {
                if (phones[i].name === pairing.paired)
                    picked = i
            }
        }
    }

    // The phones' state is read again every few seconds, and the theme with it.
    Timer { interval: 3000; running: true; repeat: true; onTriggered: backend.refresh() }
    Timer { interval: 1000; running: win.overlay === "pair"; repeat: true; onTriggered: win.now = Math.floor(Date.now() / 1000) }

    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; onActivated: win.act("help") }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; onActivated: { win.closeOverlay(); Qt.quit() } }
    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: win.overlay !== ""; onActivated: win.act("close") }
    Shortcut { sequences: ["Return", "Enter"]; context: Qt.ApplicationShortcut; enabled: win.overlay === "unpair"; onActivated: win.act("confirm") }
    Shortcut { sequence: "P"; context: Qt.ApplicationShortcut; onActivated: win.act("pair") }
    Shortcut { sequence: "D"; context: Qt.ApplicationShortcut; onActivated: win.act("checks") }
    Shortcut { sequence: "T"; context: Qt.ApplicationShortcut; onActivated: win.act("kept") }
    // What is kept is read again while its list is open.
    Timer { interval: 1500; running: win.overlay === "kept"; repeat: true; onTriggered: backend.readKept() }
    Shortcut { sequences: ["Space", "S"]; context: Qt.ApplicationShortcut; enabled: win.overlay === ""; onActivated: win.act("send") }
    Shortcut { sequence: "R"; context: Qt.ApplicationShortcut; onActivated: win.act("ring") }
    Shortcut { sequence: "Delete"; context: Qt.ApplicationShortcut; onActivated: win.act("unpair") }
    Shortcut { sequences: ["Up", "K"]; context: Qt.ApplicationShortcut; onActivated: win.act("up") }
    Shortcut { sequences: ["Down", "J"]; context: Qt.ApplicationShortcut; onActivated: win.act("down") }
    Repeater {
        model: win.switches
        Item {
            required property int index
            Shortcut { sequence: String(index + 1); context: Qt.ApplicationShortcut; onActivated: win.act("switch:" + (index + 1)) }
        }
    }

    component Ink: Text {
        color: win.ink
        textFormat: Text.PlainText
        font.pixelSize: 14
        elide: Text.ElideRight
    }

    // A flat button drawn here, not by the style: it looks the same on
    // every renderer, and takes the theme's accent and corners.
    component Act: Button {
        id: act
        // "main" is filled with the accent, "quiet" has no frame until hovered.
        property string kind: ""
        implicitHeight: 36
        leftPadding: 16
        rightPadding: 16
        opacity: enabled ? 1 : 0.4
        contentItem: Text {
            text: act.text
            textFormat: Text.PlainText
            font.pixelSize: 14
            font.bold: act.kind === "main"
            color: act.kind === "main" ? backend.ink : win.ink
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: backend.radius
            color: act.kind === "main" ? (act.down ? Qt.darker(backend.accent, 1.2) : backend.accent)
                : (act.down ? "#303037" : (act.hovered ? "#26262c" : (act.kind === "quiet" ? "transparent" : "#1f1f24")))
            border.color: act.kind === "main" ? "transparent" : (act.kind === "quiet" && !act.hovered ? "transparent" : win.line)
            border.width: act.visualFocus ? 2 : 1
        }
    }

    component Key: Rectangle {
        property string name: ""
        implicitWidth: Math.max(22, keyText.implicitWidth + 12)
        implicitHeight: 22
        radius: Math.min(4, backend.radius)
        color: "transparent"
        border.color: win.line
        Text { id: keyText; anchors.centerIn: parent; text: parent.name; color: win.muted; font.pixelSize: 12; textFormat: Text.PlainText }
    }

    component Sheet: Rectangle {
        // A panel over the window, with the rest dimmed behind it.
        id: sheet
        default property alias content: sheetBody.data
        property string heading: ""
        property int sheetWidth: 480
        anchors.fill: parent
        color: "#d0000000"
        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: win.closeOverlay() }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(sheet.sheetWidth, parent.width - 48)
            height: Math.min(sheetColumn.implicitHeight + 48, parent.height - 48)
            radius: backend.radius
            color: win.panel
            border.color: win.line
            MouseArea { anchors.fill: parent }
            ColumnLayout {
                id: sheetColumn
                anchors.fill: parent
                anchors.margins: 24
                spacing: 16
                Ink { text: sheet.heading; font.pixelSize: 20; font.bold: true; Layout.fillWidth: true }
                ColumnLayout { id: sheetBody; Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12 }
            }
        }
    }

    // Right-to-left languages mirror the window.
    Item {
        id: everything
        anchors.fill: parent

        Rectangle { anchors.fill: parent; color: win.color }

        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ColumnLayout {
                    spacing: 2
                    Ink { text: "Multiplex"; font.pixelSize: 24; font.bold: true }
                    Ink {
                        color: win.muted
                        text: win.phones.length === 0 ? qsTr("This computer and your phone, as one")
                            : (win.phones.length === 1 ? qsTr("1 phone paired") : qsTr("%1 phones paired").arg(win.phones.length))
                              + " · " + qsTr("%1 connected").arg(win.phones.filter(function (p) { return p.connected }).length)
                    }
                }
                Item { Layout.fillWidth: true }
                Act {
                    text: qsTr("Terminals")
                    kind: "quiet"
                    onClicked: win.act("kept")
                }
                Key { name: "T" }
                Act {
                    text: qsTr("This computer")
                    kind: "quiet"
                    onClicked: win.act("checks")
                }
                Key { name: "D" }
                Act {
                    text: qsTr("Pair a phone")
                    kind: "main"
                    onClicked: win.act("pair")
                }
                Key { name: "P" }
            }

            // No phone yet: one thing to do.
            ColumnLayout {
                visible: win.phones.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                Item { Layout.fillHeight: true }
                Ink { text: qsTr("No phone is paired yet"); font.pixelSize: 20; Layout.alignment: Qt.AlignHCenter }
                Ink {
                    color: win.muted
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Install Multiplex on the phone, then press P here and scan the code it shows.")
                }
                Item { Layout.fillHeight: true }
            }

            RowLayout {
                visible: win.phones.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 18

                // The phones.
                Rectangle {
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true
                    radius: backend.radius
                    color: win.panel
                    border.color: win.line
                    ListView {
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        spacing: 4
                        model: win.phones
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: 62
                            radius: backend.radius
                            color: index === win.picked ? "#26262c" : "transparent"
                            border.color: index === win.picked ? backend.accent : "transparent"
                            MouseArea { anchors.fill: parent; onClicked: win.picked = index }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12
                                Rectangle { width: 10; height: 10; radius: 5; color: modelData.connected ? win.good : "#55555c" }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Ink { text: modelData.name; font.pixelSize: 15; font.bold: true; Layout.fillWidth: true }
                                    Ink { text: win.status(modelData); color: win.muted; font.pixelSize: 13; Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }

                // The one that is picked.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: backend.radius
                    color: win.panel
                    border.color: drop.containsDrag ? backend.accent : win.line
                    border.width: drop.containsDrag ? 2 : 1

                    DropArea {
                        id: drop
                        anchors.fill: parent
                        enabled: win.phone !== null
                        onDropped: function (dropped) {
                            if (dropped.hasUrls) {
                                win.act("drop:" + dropped.urls.join("\n"))
                                dropped.accept()
                            }
                        }
                    }

                    ColumnLayout {
                        visible: win.phone !== null
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 14

                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true
                            Ink { text: win.phone ? win.phone.name : ""; font.pixelSize: 20; font.bold: true; Layout.fillWidth: true }
                            Ink { text: win.phone ? win.status(win.phone) : ""; color: win.phone && win.phone.connected ? win.good : win.muted; Layout.fillWidth: true }
                        }

                        RowLayout {
                            spacing: 8
                            Layout.fillWidth: true
                            Act { text: qsTr("Send files…"); kind: "main"; onClicked: win.act("send") }
                            Key { name: "S" }
                            Item { width: 6 }
                            Act { text: qsTr("Ring it"); enabled: win.phone && win.phone.connected; onClicked: win.act("ring") }
                            Key { name: "R" }
                            Item { Layout.fillWidth: true }
                            Act { text: qsTr("Unpair"); kind: "quiet"; onClicked: win.act("unpair") }
                            Key { name: "Del" }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: win.line }

                        Ink { text: qsTr("What it may do on this computer"); color: win.muted; font.pixelSize: 13 }

                        // The six switches; on a short window the list scrolls in its place.
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 10
                            boundsBehavior: Flickable.StopAtBounds
                            model: win.switches
                            delegate: RowLayout {
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                spacing: 12
                                Key { name: String(index + 1) }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Ink { text: modelData.title; font.pixelSize: 15; Layout.fillWidth: true }
                                    Ink { text: modelData.what; color: win.muted; font.pixelSize: 12; Layout.fillWidth: true }
                                }
                                Switch {
                                    checked: win.allowed(modelData.key)
                                    onToggled: {
                                        win.act("switch:" + (index + 1))
                                        // Shown as the computer has it, not as it was clicked.
                                        checked = Qt.binding(function () { return win.allowed(modelData.key) })
                                    }
                                }
                            }
                        }

                        Ink {
                            Layout.fillWidth: true
                            color: win.muted
                            font.pixelSize: 12
                            text: drop.containsDrag ? qsTr("Let go to send to %1").arg(win.phone ? win.phone.name : "") : qsTr("Files dropped here go to this phone.")
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                BusyIndicator { running: backend.busy; visible: backend.busy; implicitWidth: 18; implicitHeight: 18 }
                Ink { text: backend.notice; color: win.muted; Layout.fillWidth: true }
                Key { name: "?" }
                Ink { text: qsTr("keys"); color: win.muted; font.pixelSize: 12 }
                Item { width: 4 }
                Key { name: "Q" }
                Ink { text: qsTr("quit"); color: win.muted; font.pixelSize: 12 }
            }
        }

        // Pairing: the code as a picture for the phone's camera.
        Sheet {
            visible: win.overlay === "pair"
            sheetWidth: 520
            heading: win.pairing.computer !== undefined ? qsTr("Pair a phone with %1").arg(win.pairing.computer) : qsTr("Pair a phone")

            Ink {
                visible: win.pairing.code !== undefined
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                color: win.muted
                text: qsTr("In Multiplex on the phone: Pair a computer, then scan this code.")
            }
            Rectangle {
                visible: win.pairing.code !== undefined
                Layout.alignment: Qt.AlignHCenter
                width: qr.width
                height: qr.height
                color: "white"
                Canvas {
                    id: qr
                    property var rows: win.pairing.qr !== undefined ? win.pairing.qr : []
                    // Four light squares all round, as a QR code needs.
                    readonly property int cell: rows.length > 0 ? Math.max(2, Math.floor(Math.min(400, win.height - 280) / (rows.length + 8))) : 2
                    width: cell * (rows.length + 8)
                    height: width
                    onRowsChanged: requestPaint()
                    onCellChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.fillStyle = "white"
                        ctx.fillRect(0, 0, width, height)
                        ctx.fillStyle = "black"
                        for (var y = 0; y < rows.length; y++) {
                            for (var x = 0; x < rows[y].length; x++) {
                                if (rows[y].charAt(x) === "1")
                                    ctx.fillRect((x + 4) * cell, (y + 4) * cell, cell, cell)
                            }
                        }
                    }
                }
            }
            Ink {
                visible: win.pairing.code !== undefined
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("The code works for %1 more").arg(win.countdown(win.pairing.expires))
            }
            Ink {
                visible: win.pairing.expired !== undefined
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                text: qsTr("The code has expired. Nothing was paired.")
            }
            Ink {
                visible: win.pairing.error !== undefined
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                color: win.warn
                text: win.pairing.error !== undefined ? win.pairing.error : ""
            }
            BusyIndicator {
                visible: win.pairing.code === undefined && win.pairing.expired === undefined && win.pairing.error === undefined
                Layout.alignment: Qt.AlignHCenter
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                Act {
                    visible: win.pairing.expired !== undefined || win.pairing.error !== undefined
                    text: qsTr("New code")
                    kind: "main"
                    onClicked: backend.startPairing()
                }
                Act { text: win.pairing.code !== undefined ? qsTr("Cancel") : qsTr("Close"); onClicked: win.closeOverlay() }
                Key { name: "Esc" }
            }
        }

        // What this computer is ready for.
        Sheet {
            visible: win.overlay === "checks"
            sheetWidth: 640
            heading: qsTr("This computer")

            BusyIndicator { visible: win.checks.length === 0; Layout.alignment: Qt.AlignHCenter }
            ListView {
                visible: win.checks.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, win.height - 220)
                clip: true
                spacing: 8
                model: win.checks
                delegate: RowLayout {
                    required property var modelData
                    width: ListView.view.width
                    spacing: 10
                    Ink {
                        Layout.preferredWidth: 16
                        Layout.alignment: Qt.AlignTop
                        font.bold: true
                        color: modelData.ok === true ? win.good : (modelData.ok === false && modelData.required ? "#ff5f57" : win.warn)
                        text: modelData.ok === true ? "✓" : (modelData.ok === false ? (modelData.required ? "✗" : "–") : "?")
                    }
                    Ink { Layout.preferredWidth: 150; Layout.alignment: Qt.AlignTop; text: modelData.name; font.bold: true }
                    Ink { Layout.fillWidth: true; text: modelData.detail; color: win.muted; wrapMode: Text.WordWrap; elide: Text.ElideNone }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Ink { Layout.fillWidth: true; color: win.muted; font.pixelSize: 12; text: qsTr("multiplex setup in a terminal prepares what is missing.") }
                Act { text: qsTr("Close"); onClicked: win.closeOverlay() }
                Key { name: "Esc" }
            }
        }

        // The terminals the session server keeps: what the phone can pick up.
        Sheet {
            visible: win.overlay === "kept"
            sheetWidth: 640
            heading: qsTr("Terminals kept running")

            Ink {
                visible: win.kept.length === 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                color: win.muted
                text: qsTr("Nothing is kept right now. A terminal window is kept from the moment it opens, and stays when its window closes with something running in it.")
            }
            ListView {
                visible: win.kept.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, win.height - 220)
                clip: true
                spacing: 8
                model: win.kept
                delegate: RowLayout {
                    required property var modelData
                    width: ListView.view.width
                    spacing: 10
                    Ink { Layout.preferredWidth: 16; font.bold: true; color: modelData.wants ? win.warn : win.muted; text: modelData.wants ? "!" : "·" }
                    Ink { Layout.preferredWidth: 170; text: modelData.what; font.bold: modelData.wants }
                    Ink { Layout.fillWidth: true; text: modelData.where; color: win.muted }
                    Act { text: qsTr("Open"); kind: "quiet"; onClicked: backend.openKept(modelData.id) }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Ink { Layout.fillWidth: true; color: win.muted; font.pixelSize: 12; text: qsTr("Each is also on the phone, under Agents.") }
                Act { text: qsTr("Close"); onClicked: win.closeOverlay() }
                Key { name: "Esc" }
            }
        }

        // Removing a phone is asked about first.
        Sheet {
            visible: win.overlay === "unpair"
            heading: win.phone ? qsTr("Unpair %1?").arg(win.phone.name) : ""
            Ink {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                color: win.muted
                text: qsTr("It can no longer log in to this computer. Connections it has open stay until they close. To use it again, pair it again.")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                Act { text: qsTr("Keep it"); onClicked: win.overlay = "" }
                Act {
                    text: qsTr("Unpair")
                    kind: "main"
                    onClicked: win.act("confirm")
                }
            }
        }

        // Every key.
        Sheet {
            visible: win.overlay === "help"
            heading: qsTr("Keys")
            Repeater {
                model: [
                    ["P", qsTr("Pair a phone")],
                    ["↑ ↓", qsTr("Pick a phone")],
                    ["S", qsTr("Send files to it (Space does the same)")],
                    ["R", qsTr("Make it ring, to find it")],
                    ["1 – 6", qsTr("Switch what it may do on or off")],
                    ["Del", qsTr("Unpair it (Enter confirms)")],
                    ["D", qsTr("What this computer is ready for")],
                    ["T", qsTr("The terminals kept running")],
                    ["Esc", qsTr("Close what is open")],
                    ["Q", qsTr("Quit")]
                ]
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    Item {
                        Layout.preferredWidth: 64
                        implicitHeight: 22
                        Key { name: modelData[0] }
                    }
                    Ink { text: modelData[1]; Layout.fillWidth: true }
                }
            }
        }
    }

    Timer {
        id: shotTimer
        interval: 1200
        onTriggered: {
            var started = everything.grabToImage(function (result) {
                console.log("picture saved:", result.saveToFile(backend.shot))
                Qt.quit()
            })
            if (!started) {
                console.log("the window could not be pictured")
                Qt.exit(1)
            }
        }
    }

    Component.onCompleted: {
        // What to do first, as keys would, one after the other: from how
        // the window was started (`--pair`, `--send <phone>`), and for its
        // tests and pictures from MULTIPLEX_APP_VIEW ("down,unpair").
        var first = JSON.parse(backend.view)
        for (var i = 0; i < first.length; i++)
            win.act(first[i])
        if (backend.shot.length > 0) {
            // A picture is always of the window at its usual size.
            win.width = 900
            win.height = 680
            console.log("picturing the window into", backend.shot)
            shotTimer.start()
        }
    }
}
