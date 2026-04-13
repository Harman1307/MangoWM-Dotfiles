import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    property string time: ""
    property bool wifi: false
    property bool bt: false
    property int bat: 100
    property bool plug: false
    property bool batFull: plug && bat >= 100
    property real pulse: 1
    property int tag: 1
    property var occ: [false,false,false,false,false]
    property bool barReady: false

    function a(c, o) { return Qt.rgba(c.r, c.g, c.b, o) }

    function parseTagOutput(data) {
        var lines = data.trim().split("\n")
        var newOcc = [false, false, false, false, false]
        for (var i = 0; i < lines.length; i++) {
            var p = lines[i].split(" ")
            if (p.length >= 5 && p[1] === "tag") {
                var n = parseInt(p[2])
                if (n >= 1 && n <= 5) {
                    if (parseInt(p[3]) === 1) tag = n
                    newOcc[n - 1] = parseInt(p[4]) > 0
                }
            }
        }
        occ = newOcc
    }

    function volIcon() {
        if (UIState.muted) return "󰖁"
        if (UIState.volume > 60) return "󰕾"
        if (UIState.volume > 25) return "󰖀"
        return "󰕿"
    }

    function batIcon() {
        if (batFull) return "󰁹"
        if (plug) return "󰂄"
        if (bat > 90) return "󰁹"
        if (bat > 70) return "󰂁"
        if (bat > 50) return "󰁿"
        if (bat > 30) return "󰁾"
        if (bat > 15) return "󰁼"
        return "󰂃"
    }

    function batColor() {
        if (batFull) return Colors.green
        if (plug) return Colors.accent
        if (bat <= 15) return Colors.red
        if (bat <= 30) return Colors.yellow
        return Colors.green
    }

    function adjustVol(delta) {
        UIState.setVolume(Math.max(0, Math.min(100, UIState.volume + delta)))
    }

    Process {
        id: tagWatch
        command: ["mmsg", "-w", "-t"]
        running: true
        stdout: SplitParser { splitMarker: ""; onRead: data => parseTagOutput(data) }
        onExited: tagRestart.start()
    }

    Timer { id: tagRestart; interval: 1000; onTriggered: tagWatch.running = true }

    Process {
        id: tagGet
        command: ["mmsg", "-g", "-t"]
        running: true
        stdout: SplitParser { splitMarker: ""; onRead: data => parseTagOutput(data) }
    }

    Process { id: tagSet }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: time = Qt.formatDateTime(new Date(), "h:mm A")
    }

    Process {
        id: wifiWatch
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser { onRead: data => wifiDebounce.restart() }
        onExited: wifiWatchRestart.start()
    }

    Timer { id: wifiWatchRestart; interval: 1000; onTriggered: wifiWatch.running = true }
    Timer { id: wifiDebounce; interval: 80; onTriggered: wifiProc.running = true }

    Process {
        id: wifiProc
        command: ["bash", "-c", "nmcli -t -f active dev wifi 2>/dev/null | grep -q yes && echo 1 || echo 0"]
        running: true
        stdout: SplitParser { onRead: data => wifi = data.trim() === "1" }
    }

    Process {
        id: btWatch
        command: ["dbus-monitor", "--system", "type='signal',sender='org.bluez'"]
        running: true
        stdout: SplitParser { onRead: data => btDebounce.restart() }
        onExited: btWatchRestart.start()
    }

    Timer { id: btWatchRestart; interval: 1000; onTriggered: btWatch.running = true }
    Timer { id: btDebounce; interval: 80; onTriggered: btProc.running = true }

    Process {
        id: btProc
        command: ["bash", "-c", "for m in $(bluetoothctl devices 2>/dev/null | awk '{print $2}'); do bluetoothctl info $m 2>/dev/null | grep -q 'Connected: yes' && echo 1 && exit; done; echo 0"]
        running: true
        stdout: SplitParser { onRead: data => bt = data.trim() === "1" }
    }

    Process {
        id: batWatch
        command: ["upower", "--monitor-detail"]
        running: true
        stdout: SplitParser { onRead: data => batDebounce.restart() }
        onExited: batWatchRestart.start()
    }

    Timer { id: batWatchRestart; interval: 1000; onTriggered: batWatch.running = true }
    Timer { id: batDebounce; interval: 80; onTriggered: batProc.running = true }

    Process {
        id: batProc
        command: ["bash", "-c", "c=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); s=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1); [ -z \"$c\" ] && c=100; echo \"$c|$s\""]
        running: true
        stdout: SplitParser {
            onRead: data => { var p = data.trim().split("|"); bat = parseInt(p[0]) || 100; plug = (p[1] === "Charging" || p[1] === "Full") }
        }
    }

    Process { id: volToggle; command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"] }

    SequentialAnimation {
        running: plug && !batFull
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "pulse"; to: 0.4; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "pulse"; to: 1; duration: 900; easing.type: Easing.InOutSine }
    }

    Timer {
        id: startDelay
        interval: 80
        running: Colors.currentTheme !== ""
        onTriggered: barReady = true
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            property var modelData
            screen: modelData
            anchors { top: true; left: true; right: true }
            height: 38
            color: "transparent"
            exclusionMode: ExclusionMode.Exclusive
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "bar"

            Rectangle {
                id: barBg
                anchors.fill: parent
                anchors.topMargin: 5
                anchors.leftMargin: barReady ? 8 : parent.width * 0.42
                anchors.rightMargin: barReady ? 8 : parent.width * 0.42
                anchors.bottomMargin: 3
                radius: 12
                color: a(Colors.surface, UIState.barOpacity)
                border.width: 1
                border.color: a(Colors.fg, 0.06)
                opacity: barReady ? 1 : 0
                scale: barReady ? 1 : 0.95

                Behavior on anchors.leftMargin { NumberAnimation { duration: 700; easing.type: Easing.OutExpo } }
                Behavior on anchors.rightMargin { NumberAnimation { duration: 700; easing.type: Easing.OutExpo } }
                Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    opacity: barReady ? 1 : 0
                    scale: barReady ? 1 : 0.9

                    Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 550; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 14

                        Item {
                            width: clockText.implicitWidth; height: 22
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                id: clockText
                                anchors.centerIn: parent
                                text: time
                                color: clockMa.containsMouse ? Colors.accent : Colors.fg
                                font { pixelSize: 11; family: "JetBrainsMono Nerd Font"; letterSpacing: 0.5 }
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            Rectangle {
                                anchors { bottom: parent.bottom; bottomMargin: 1; horizontalCenter: parent.horizontalCenter }
                                width: clockMa.containsMouse ? parent.width + 4 : 0
                                height: 2; radius: 1
                                color: a(Colors.accent, 0.6)
                                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                            }

                            MouseArea {
                                id: clockMa
                                anchors.fill: parent; anchors.margins: -8
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: UIState.toggleDropdown("calendar")
                            }
                        }

                        Row {
                            spacing: 3
                            anchors.verticalCenter: parent.verticalCenter

                            Repeater {
                                model: 5

                                Item {
                                    required property int index
                                    property bool active: tag === index + 1
                                    property bool used: occ[index]
                                    property bool show: active || used
                                    property bool hov: tagMa.containsMouse

                                    width: show ? pill.width + 4 : 0
                                    height: 22; clip: true
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: width > 0

                                    Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }

                                    onActiveChanged: { if (active) activePop.restart() }

                                    SequentialAnimation {
                                        id: activePop
                                        NumberAnimation { target: pill; property: "scale"; to: 1.2; duration: 100; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: pill; property: "scale"; to: 1.0; duration: 250; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                                    }

                                    Rectangle {
                                        id: pill
                                        width: tagNum.implicitWidth + 16; height: 18; radius: 9
                                        anchors.centerIn: parent
                                        color: active ? a(Colors.accent, 0.2) : hov ? a(Colors.fg, 0.08) : "transparent"
                                        border.width: active ? 1 : 0
                                        border.color: a(Colors.accent, 0.3)

                                        Behavior on color { ColorAnimation { duration: 200 } }

                                        Text {
                                            id: tagNum
                                            anchors.centerIn: parent
                                            text: index + 1
                                            color: active ? Colors.accent : hov ? Colors.fg : a(Colors.fg, 0.5)
                                            font { pixelSize: 10; family: "JetBrainsMono Nerd Font"; bold: active }
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                    }

                                    MouseArea {
                                        id: tagMa
                                        anchors.fill: parent; anchors.margins: -4
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { tagSet.command = ["mmsg", "-s", "-t", String(index + 1)]; tagSet.running = true }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        anchors.centerIn: parent
                        width: mediaVisible ? centerRow.implicitWidth : 0
                        height: parent.height

                        property bool mediaVisible: UIState.hasMedia

                        opacity: mediaVisible ? 1 : 0
                        scale: mediaVisible ? 1 : 0.8

                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }

                        Row {
                            id: centerRow
                            anchors.centerIn: parent
                            spacing: 10

                            Row {
                                spacing: 2
                                anchors.verticalCenter: parent.verticalCenter

                                Repeater {
                                    model: 12
                                    Rectangle {
                                        required property int index
                                        width: 2.5
                                        height: Math.max(3, UIState.cava[index] * 16)
                                        radius: 1.25
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: UIState.mediaState !== "playing" ? a(Colors.accent, 0.15 + UIState.cava[index] * 0.6)
                                             : UIState.cava[index] > 0.7 ? Colors.accent
                                             : a(Colors.accent, 0.4 + UIState.cava[index] * 0.5)

                                        Behavior on height { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
                                    }
                                }
                            }

                            Text {
                                text: UIState.mediaState === "playing" ? "󰏤" : "󰐊"
                                color: a(Colors.fg, 0.4)
                                font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Item {
                                width: mediaLabel.implicitWidth; height: 22
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    id: mediaLabel
                                    anchors.centerIn: parent
                                    text: UIState.mediaDisplay
                                    color: mediaMa.containsMouse ? Colors.fg : a(Colors.fg, UIState.mediaState === "playing" ? 0.65 : 0.4)
                                    font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }

                                Rectangle {
                                    anchors { bottom: parent.bottom; bottomMargin: 1; horizontalCenter: parent.horizontalCenter }
                                    width: mediaMa.containsMouse ? parent.width + 4 : 0
                                    height: 2; radius: 1
                                    color: a(Colors.accent, 0.5)
                                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                }
                            }
                        }

                        MouseArea {
                            id: mediaMa
                            anchors.fill: parent; anchors.margins: -8
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) UIState.toggleDropdown("media")
                                else UIState.doMedia("play-pause")
                            }
                            onWheel: function(wheel) { UIState.doMedia(wheel.angleDelta.y > 0 ? "next" : "previous") }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Row {
                            spacing: 6
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                text: wifi ? "󰤨" : "󰤭"
                                color: wifi ? Colors.accent : a(Colors.fg, 0.3)
                                font { pixelSize: 13; family: "JetBrainsMono Nerd Font" }
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: bt ? "󰂯" : "󰂲"
                                color: bt ? a(Colors.fg, 0.7) : a(Colors.fg, 0.25)
                                font { pixelSize: 12; family: "JetBrainsMono Nerd Font" }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Item {
                            width: volRow.width; height: 22
                            anchors.verticalCenter: parent.verticalCenter

                            Row {
                                id: volRow
                                spacing: 5; anchors.centerIn: parent

                                Text {
                                    text: volIcon()
                                    color: UIState.muted ? a(Colors.fg, 0.25) : volMa.containsMouse ? Colors.fg : a(Colors.fg, 0.7)
                                    font { pixelSize: 13; family: "JetBrainsMono Nerd Font" }
                                    anchors.verticalCenter: parent.verticalCenter
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }

                                Text {
                                    text: UIState.volume
                                    color: UIState.muted ? a(Colors.fg, 0.25) : volMa.containsMouse ? Colors.fg : a(Colors.fg, 0.55)
                                    font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                                    anchors.verticalCenter: parent.verticalCenter
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }

                            MouseArea {
                                id: volMa
                                anchors.fill: parent; anchors.margins: -8
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: volToggle.running = true
                                onWheel: function(wheel) { adjustVol(wheel.angleDelta.y > 0 ? 5 : -5) }
                            }
                        }

                        Item {
                            width: batRow.width; height: 22
                            anchors.verticalCenter: parent.verticalCenter

                            Row {
                                id: batRow
                                spacing: 4; anchors.centerIn: parent

                                Text {
                                    text: batIcon()
                                    color: batColor()
                                    font { pixelSize: 14; family: "JetBrainsMono Nerd Font" }
                                    opacity: plug && !batFull ? pulse : 1
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: bat + "%"
                                    color: batColor()
                                    font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: bat <= 30 || plug || batMa.containsMouse ? 1 : 0.6
                                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                            }

                            MouseArea {
                                id: batMa
                                anchors.fill: parent; anchors.margins: -6
                                hoverEnabled: true
                            }
                        }

                        Item {
                            width: 22; height: 22
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.centerIn: parent
                                width: dma.containsMouse || UIState.activeDropdown === "dashboard" ? 20 : 17
                                height: width; radius: width / 2
                                color: dma.containsMouse || UIState.activeDropdown === "dashboard" ? a(Colors.accent, 0.2) : a(Colors.fg, 0.06)
                                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰺔"
                                color: dma.containsMouse || UIState.activeDropdown === "dashboard" ? Colors.accent : a(Colors.fg, 0.4)
                                font { pixelSize: dma.containsMouse ? 12 : 11; family: "JetBrainsMono Nerd Font" }
                                Behavior on color { ColorAnimation { duration: 200 } }
                                Behavior on font.pixelSize { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                            }

                            MouseArea {
                                id: dma
                                anchors.fill: parent; anchors.margins: -8
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: UIState.toggleDropdown("dashboard")
                            }
                        }
                    }
                }
            }
        }
    }
}