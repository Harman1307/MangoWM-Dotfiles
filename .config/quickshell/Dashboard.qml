import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt5Compat.GraphicalEffects

PanelWindow {
    id: dashboard

    property bool showing: UIState.activeDropdown === "dashboard"
    property bool _visible: false
    property real panelWidth:  screen ? Math.min(380, Math.max(320, screen.width * 0.26))  : 360
    property real panelHeight: screen ? Math.min(820, Math.max(600, screen.height * 0.82)) : 720

    visible: _visible
    anchors { top: true; right: true }
    margins { top: 44; right: 12 }
    implicitWidth:  panelWidth
    implicitHeight: panelHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dashboard"

    function a(c, o) { return Qt.rgba(c.r, c.g, c.b, o) }

    property string uptime: "..."
    property var pfpList: []
    property bool qsExpanded:  false
    property bool powerOverlay: false
    property bool pfpPicker:   false
    property var expandedGroups: ({})

    property bool wifiOn:    true
    property bool btOn:      false
    property bool micMuted:  false

    ListModel { id: groupedModel }

    function rebuildGrouped() {
        var groups = {}
        var order  = []
        var notifs = UIState.notifications
        for (var i = 0; i < notifs.length; i++) {
            var n   = notifs[i]
            var app = n.app || "Unknown"
            if (!groups[app]) { groups[app] = []; order.push(app) }
            groups[app].push(n)
        }

        var newApps = {}
        for (var j = 0; j < order.length; j++)
            newApps[order[j]] = groups[order[j]]

        for (var k = groupedModel.count - 1; k >= 0; k--) {
            if (!newApps[groupedModel.get(k).app])
                groupedModel.remove(k)
        }

        for (var l = 0; l < order.length; l++) {
            var app2  = order[l]
            var found = false
            for (var m = 0; m < groupedModel.count; m++) {
                if (groupedModel.get(m).app === app2) {
                    var oldCount = JSON.parse(groupedModel.get(m).items).length
                    var newCount = groups[app2].length
                    var oldBump  = groupedModel.get(m).bump
                    groupedModel.set(m, {
                        app:   app2,
                        items: JSON.stringify(groups[app2]),
                        bump:  newCount > oldCount ? oldBump + 1 : oldBump
                    })
                    found = true
                    break
                }
            }
            if (!found)
                groupedModel.insert(l, { app: app2, items: JSON.stringify(groups[app2]), bump: 0 })
        }
    }

    Component.onCompleted: {
        pfpListProc.running = true
        rebuildGrouped()
    }

    Connections {
        target: UIState
        function onNotificationsChanged() { rebuildGrouped() }
    }

    onShowingChanged: {
        if (showing) {
            _visible = true
            uptimeProc.running = true
            stateProc.running  = true
        } else {
            closeDelay.start()
        }
    }

    Timer {
        id: closeDelay
        interval: Animations.exitDuration + 60
        onTriggered: {
            _visible     = false
            qsExpanded   = false
            powerOverlay = false
            pfpPicker    = false
            expandedGroups = ({})
        }
    }

    function isGroupExpanded(app) { return expandedGroups[app] === true }

    function toggleGroup(app) {
        var copy   = Object.assign({}, expandedGroups)
        copy[app]  = !copy[app]
        expandedGroups = copy
    }

    Process {
        id: pfpListProc
        command: ["bash", "-c", "ls -1 ~/.config/quickshell/assets/pfps/*.{jpg,png} 2>/dev/null"]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { pfpList = data.trim().split("\n").filter(l => l.length > 0) }
        }
    }

    Process {
        id: uptimeProc
        command: ["bash", "-c", "uptime -p | sed 's/up //'"]
        stdout: SplitParser { onRead: data => uptime = data.trim() }
    }

    Process {
        id: stateProc
        command: ["bash", "-c", [
            "w=$(nmcli radio wifi 2>/dev/null)",
            "b=$(bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off)",
            "m=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED && echo 1 || echo 0)",
            "echo \"$w|$b|$m\""
        ].join("; ")]
        stdout: SplitParser {
            onRead: data => {
                var p  = data.trim().split("|")
                wifiOn    = p[0] === "enabled"
                btOn      = p[1] === "on"
                micMuted  = p[2] === "1"
            }
        }
    }

    Process { id: wifiToggleProc }
    Process { id: btToggleProc }
    Process { id: micToggleProc }
    Process { id: randomWallProc; command: ["bash", "-c", "~/.config/scripts/random-wallpaper.sh"] }

    function toggleWifi() {
        wifiOn = !wifiOn
        wifiToggleProc.command = ["nmcli", "radio", "wifi", wifiOn ? "on" : "off"]
        wifiToggleProc.running = true
    }

    function toggleBt() {
        btOn = !btOn
        btToggleProc.command = ["bluetoothctl", "power", btOn ? "on" : "off"]
        btToggleProc.running = true
    }

    function toggleMic() {
        micMuted = !micMuted
        micToggleProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]
        micToggleProc.running = true
    }

    property var quickSettings: [
        { icon: "󰤨", iconOff: "󰤭", label: "WiFi",        active: () => wifiOn,                   toggle: toggleWifi },
        { icon: "󰂯", iconOff: "󰂲", label: "BT",          active: () => btOn,                     toggle: toggleBt },
        { icon: "󰍶", iconOff: "󰍷", label: "DND",         active: () => UIState.dndEnabled,       toggle: UIState.toggleDnd },
        { icon: "󰐥", iconOff: "󰐥", label: "Power",       active: () => false,                    toggle: () => { powerOverlay = true } },
        { icon: "󰖔", iconOff: "󰖕", label: "Dark",        active: () => UIState.darkMode,         toggle: UIState.toggleDarkMode },
        { icon: "󰂵", iconOff: "󰂺", label: "Glass",       active: () => UIState.transparencyEnabled, toggle: UIState.toggleTransparency },
        { icon: "󰍬", iconOff: "󰍭", label: "Mic",         active: () => !micMuted,                toggle: toggleMic },
        { icon: "󰒝", iconOff: "󰒝", label: "Random Wall", active: () => false,                    toggle: () => { randomWallProc.running = true } }
    ]

    Rectangle {
        id: bg
        width:   parent.width
        height:  parent.height
        x:       showing ? 0 : panelWidth + 20
        opacity: showing ? 1 : 0
        scale:   showing ? 1 : 0.97
        transformOrigin: Item.TopRight
        color:  a(Colors.bg, UIState.transparencyEnabled ? 0.82 : 1)
        radius: 16

        Behavior on x {
            NumberAnimation { duration: Animations.enterDuration; easing.type: Easing.OutExpo }
        }
        Behavior on opacity {
            NumberAnimation { duration: Animations.medium; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: Animations.enterDuration; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            ColorAnimation { duration: Animations.slow }
        }

        Item {
            anchors.fill: parent
            anchors.margins: 20

            Column {
                id: mainCol
                anchors.fill: parent
                spacing: 14

                Row {
                    width:   parent.width
                    height:  68
                    spacing: 16

                    Item {
                        width:  62; height: 62
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: 31
                            color:  a(Colors.accent, 0.1)
                            border.width: 2.5
                            border.color: a(Colors.accent, 0.35)
                        }

                        Image {
                            id: pfpImg
                            anchors.fill: parent
                            anchors.margins: 3
                            source: pfpList.length > 0 ? "file://" + pfpList[UIState.pfpIndex] : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(128, 128)
                            smooth: true
                            antialiasing: true
                            visible: false
                        }

                        Rectangle {
                            id: pfpMask
                            anchors.fill: pfpImg
                            radius: width / 2
                            visible: false
                        }

                        OpacityMask {
                            anchors.fill: pfpImg
                            source: pfpImg
                            maskSource: pfpMask
                            visible: pfpList.length > 0
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "󰀄"
                            color: Colors.accent
                            font { pixelSize: 28; family: "JetBrainsMono Nerd Font" }
                            visible: pfpList.length === 0
                        }

                        scale: pfpMa.containsMouse ? 1.06 : 1
                        Behavior on scale {
                            NumberAnimation { duration: Animations.medium; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                        }

                        MouseArea {
                            id: pfpMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pfpPicker = !pfpPicker
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            text: Quickshell.env("USER")
                            color: Colors.fg
                            font { pixelSize: 20; family: "JetBrainsMono Nerd Font"; bold: true }
                        }

                        Text {
                            text: uptime
                            color: a(Colors.fg, 0.35)
                            font { pixelSize: 11; family: "JetBrainsMono Nerd Font" }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: a(Colors.fg, 0.06) }

                Column {
                    width: parent.width
                    spacing: 8

                    Item {
                        width:  parent.width
                        height: qsExpanded ? 124 : 58
                        clip:   true

                        Behavior on height {
                            NumberAnimation { duration: Animations.medium; easing.type: Easing.OutExpo }
                        }

                        Grid {
                            id: qsGrid
                            width:   parent.width
                            columns: 4
                            spacing: 8

                            Repeater {
                                model: quickSettings

                                Rectangle {
                                    property bool isSecondRow: index >= 4
                                    property bool shouldShow:  !isSecondRow || qsExpanded
                                    property bool isDarkTile:  index === 4
                                    property bool isOn:        modelData.active()

                                    width:  (qsGrid.width - 24) / 4
                                    height: 58
                                    radius: 14
                                    color:  isOn ? a(Colors.accent, 0.15) : qsMa.containsMouse ? a(Colors.fg, 0.07) : a(Colors.surface, 0.8)
                                    border.width: isOn ? 1 : 0
                                    border.color: a(Colors.accent, 0.25)
                                    opacity:      shouldShow ? 1 : 0
                                    scale:        shouldShow ? (qsMa.pressed ? 0.92 : 1) : 0.82
                                    transformOrigin: Item.Top

                                    Behavior on color   { ColorAnimation  { duration: Animations.fast } }
                                    Behavior on opacity { NumberAnimation { duration: Animations.medium; easing.type: Easing.OutCubic } }
                                    Behavior on scale   {
                                        NumberAnimation { duration: Animations.medium; easing.type: Easing.OutBack; easing.overshoot: Animations.springPower }
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 5

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text:  isOn ? modelData.icon : modelData.iconOff
                                            color: isOn ? Colors.accent : a(Colors.fg, 0.35)
                                            font { pixelSize: 18; family: "JetBrainsMono Nerd Font" }
                                            Behavior on color { ColorAnimation { duration: Animations.fast } }
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text:  modelData.label
                                            color: isOn ? Colors.accent : a(Colors.fg, 0.25)
                                            font { pixelSize: 8; family: "JetBrainsMono Nerd Font" }
                                            Behavior on color { ColorAnimation { duration: Animations.fast } }
                                        }
                                    }

                                    Rectangle {
                                        visible: isDarkTile && UIState.darkModeLocked
                                        anchors { top: parent.top; right: parent.right; topMargin: 4; rightMargin: 4 }
                                        width: 16; height: 16; radius: 8
                                        color: a(Colors.accent, 0.25)

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰌾"
                                            color: Colors.accent
                                            font { pixelSize: 8; family: "JetBrainsMono Nerd Font" }
                                        }
                                    }

                                    MouseArea {
                                        id: qsMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: function(mouse) {
                                            if (mouse.button === Qt.RightButton && isDarkTile)
                                                UIState.toggleDarkModeLock()
                                            else
                                                modelData.toggle()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width:  36; height: 16; radius: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        color:    expandMa.containsMouse ? a(Colors.fg, 0.08) : a(Colors.fg, 0.04)
                        rotation: qsExpanded ? 180 : 0

                        Behavior on rotation { NumberAnimation { duration: Animations.medium; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                        Behavior on color    { ColorAnimation  { duration: Animations.fast } }

                        Text {
                            anchors.centerIn: parent
                            text:  "󰅀"
                            color: a(Colors.fg, 0.35)
                            font { pixelSize: 11; family: "JetBrainsMono Nerd Font" }
                        }

                        MouseArea {
                            id: expandMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: qsExpanded = !qsExpanded
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: a(Colors.fg, 0.06) }

                Column {
                    width:   parent.width
                    spacing: 16

                    SliderRow {
                        width:     parent.width
                        icon:      UIState.volume == 0 ? "󰝟" : UIState.volume < 50 ? "󰖀" : "󰕾"
                        iconColor: Colors.accent
                        value:     UIState.volume
                        onMoved:   v => UIState.setVolume(v)
                    }

                    SliderRow {
                        width:     parent.width
                        icon:      UIState.brightness < 30 ? "󰃞" : UIState.brightness < 70 ? "󰃟" : "󰃠"
                        iconColor: Colors.yellow
                        value:     UIState.brightness
                        onMoved:   v => UIState.setBrightness(v)
                    }
                }

                Rectangle { width: parent.width; height: 1; color: a(Colors.fg, 0.06) }

                Item {
                    width: parent.width; height: 18

                    Text {
                        text:  "Notifications"
                        color: a(Colors.fg, 0.45)
                        font { pixelSize: 12; family: "JetBrainsMono Nerd Font"; bold: true }
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    }

                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 8

                        Text {
                            text:  UIState.notifications.length > 0 ? UIState.notifications.length : ""
                            color: a(Colors.fg, 0.3)
                            font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                        }

                        Text {
                            text:  UIState.notifications.length > 0 ? "Clear all" : ""
                            color: clearMa.containsMouse ? Colors.accent : a(Colors.accent, 0.5)
                            font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                            Behavior on color { ColorAnimation { duration: Animations.fast } }

                            MouseArea {
                                id: clearMa
                                anchors.fill: parent; anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: UIState.notifications.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: UIState.clearNotifs()
                            }
                        }
                    }
                }

                Item {
                    width:  parent.width
                    height: parent.height - y
                    clip:   true

                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color:  a(Colors.surface, 0.5)
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: UIState.notifications.length === 0
                        text:    "All clear 󰸞"
                        color:   a(Colors.fg, 0.15)
                        font { pixelSize: 12; family: "JetBrainsMono Nerd Font" }
                    }

                    ListView {
                        id: notifList
                        anchors.fill: parent
                        anchors.margins: 10
                        clip:   true
                        model:  groupedModel
                        spacing: 8
                        boundsBehavior: Flickable.StopAtBounds

                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Animations.medium; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "x"; from: 24; to: 0; duration: Animations.medium; easing.type: Easing.OutExpo }
                            }
                        }

                        remove: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Animations.fast; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "x"; to: 24; duration: Animations.fast; easing.type: Easing.OutCubic }
                            }
                        }

                        displaced: Transition {
                            NumberAnimation { property: "y"; duration: Animations.medium; easing.type: Easing.OutExpo }
                        }

                        delegate: Item {
                            id: groupDelegate
                            width:  notifList.width
                            height: groupCol.implicitHeight
                            clip:   true

                            property string groupApp:    model.app
                            property var parsedItems:    JSON.parse(model.items)
                            property bool expanded:      isGroupExpanded(model.app)
                            property int itemCount:      parsedItems.length
                            property var latestItem:     parsedItems[0]
                            property int bump:           model.bump

                            onBumpChanged: {
                                if (bump > 0) {
                                    headerFlashAnim.start()
                                    badgePopAnim.start()
                                }
                            }

                            Column {
                                id: groupCol
                                width:   parent.width
                                spacing: 6

                                Rectangle {
                                    id: groupHeader
                                    width:  parent.width
                                    height: 36
                                    radius: 12
                                    color:  groupHeaderMa.containsMouse ? a(Colors.accent, 0.1) : a(Colors.fg, 0.04)
                                    border.width: 1
                                    border.color: groupHeaderMa.containsMouse ? a(Colors.accent, 0.15) : "transparent"

                                    Behavior on color { ColorAnimation { duration: Animations.fast } }

                                    SequentialAnimation {
                                        id: headerFlashAnim
                                        ColorAnimation { target: groupHeader; property: "color"; to: a(Colors.accent, 0.2); duration: 120 }
                                        ColorAnimation { target: groupHeader; property: "color"; to: a(Colors.fg, 0.04); duration: Animations.slow; easing.type: Easing.OutCubic }
                                    }

                                    Row {
                                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                        spacing: 8

                                        Text {
                                            text: "󰅂"
                                            color: a(Colors.fg, 0.35)
                                            font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                                            anchors.verticalCenter: parent.verticalCenter
                                            rotation: groupDelegate.expanded ? 90 : 0
                                            Behavior on rotation {
                                                NumberAnimation { duration: Animations.medium; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                                            }
                                        }

                                        Rectangle {
                                            width: 6; height: 6; radius: 3
                                            color: Colors.accent
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text:  groupDelegate.groupApp.toUpperCase()
                                            color: a(Colors.accent, 0.7)
                                            font { pixelSize: 9; family: "JetBrainsMono Nerd Font"; bold: true; letterSpacing: 0.8 }
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Row {
                                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                        spacing: 10

                                        Rectangle {
                                            id: countBadge
                                            width:  countText.implicitWidth + 12
                                            height: 20; radius: 10
                                            color:  a(Colors.accent, 0.12)
                                            anchors.verticalCenter: parent.verticalCenter

                                            SequentialAnimation {
                                                id: badgePopAnim
                                                NumberAnimation { target: countBadge; property: "scale"; to: 1.4; duration: Animations.snap; easing.type: Easing.OutQuad }
                                                NumberAnimation { target: countBadge; property: "scale"; to: 1.0; duration: Animations.medium; easing.type: Easing.OutBack; easing.overshoot: Animations.springPower }
                                            }

                                            Text {
                                                id: countText
                                                anchors.centerIn: parent
                                                text:  groupDelegate.itemCount
                                                color: Colors.accent
                                                font { pixelSize: 9; family: "JetBrainsMono Nerd Font"; bold: true }
                                            }
                                        }

                                        Text {
                                            text:  "󰅖"
                                            color: groupDismissMa.containsMouse ? Colors.red : a(Colors.fg, 0.25)
                                            font { pixelSize: 12; family: "JetBrainsMono Nerd Font" }
                                            anchors.verticalCenter: parent.verticalCenter
                                            Behavior on color { ColorAnimation { duration: Animations.fast } }

                                            MouseArea {
                                                id: groupDismissMa
                                                anchors.fill: parent; anchors.margins: -6
                                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    groupDismissAnim.targetApp = groupDelegate.groupApp
                                                    groupDismissAnim.start()
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: groupHeaderMa
                                        anchors.fill: parent
                                        anchors.rightMargin: 70
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: toggleGroup(groupDelegate.groupApp)
                                    }
                                }

                                Rectangle {
                                    visible: !groupDelegate.expanded
                                    width:   parent.width
                                    height:  visible ? previewContent.implicitHeight + 16 : 0
                                    radius:  10
                                    color:   previewMa.containsMouse ? a(Colors.fg, 0.045) : a(Colors.fg, 0.025)
                                    Behavior on color { ColorAnimation { duration: Animations.fast } }

                                    MouseArea {
                                        id: previewMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: toggleGroup(groupDelegate.groupApp)
                                    }

                                    Column {
                                        id: previewContent
                                        x: 14; y: 8
                                        width:   parent.width - 28
                                        spacing: 3

                                        Text {
                                            text:  groupDelegate.latestItem ? groupDelegate.latestItem.title : ""
                                            color: Colors.fg
                                            font { pixelSize: 10; family: "JetBrainsMono Nerd Font"; bold: true }
                                            width: parent.width; elide: Text.ElideRight
                                        }

                                        Text {
                                            text:  groupDelegate.latestItem ? groupDelegate.latestItem.body : ""
                                            color: a(Colors.fg, 0.4)
                                            font { pixelSize: 9; family: "JetBrainsMono Nerd Font" }
                                            width: parent.width; elide: Text.ElideRight
                                            visible: text !== ""
                                        }

                                        Text {
                                            text:    groupDelegate.itemCount > 1 ? "+" + (groupDelegate.itemCount - 1) + " more" : ""
                                            color:   a(Colors.accent, 0.5)
                                            font { pixelSize: 9; family: "JetBrainsMono Nerd Font" }
                                            visible: groupDelegate.itemCount > 1
                                        }
                                    }
                                }

                                Item {
                                    width:  parent.width
                                    height: groupDelegate.expanded ? expandedCol.implicitHeight : 0
                                    clip:   true

                                    Behavior on height {
                                        NumberAnimation { duration: Animations.medium; easing.type: Easing.OutExpo }
                                    }

                                    Column {
                                        id: expandedCol
                                        width:   parent.width
                                        spacing: 6

                                        Repeater {
                                            model: groupDelegate.expanded ? groupDelegate.parsedItems : []

                                            Rectangle {
                                                id: notifCard
                                                width:  parent.width
                                                height: nTitle.implicitHeight + (nBody.visible ? nBody.implicitHeight + 6 : 0) + 32
                                                radius: 12
                                                color:  nItemMa.containsMouse ? a(Colors.fg, 0.055) : a(Colors.fg, 0.03)
                                                border.width: nItemMa.containsMouse ? 1 : 0
                                                border.color: a(Colors.accent, 0.12)
                                                opacity: 0
                                                x: 16

                                                Behavior on color { ColorAnimation { duration: Animations.fast } }

                                                Component.onCompleted: cardAppearAnim.start()

                                                ParallelAnimation {
                                                    id: cardAppearAnim
                                                    NumberAnimation { target: notifCard; property: "opacity"; from: 0; to: 1; duration: Animations.medium; easing.type: Easing.OutCubic }
                                                    NumberAnimation { target: notifCard; property: "x"; from: 16; to: 0; duration: Animations.medium; easing.type: Easing.OutExpo }
                                                }

                                                SequentialAnimation {
                                                    id: cardDismissAnim
                                                    ParallelAnimation {
                                                        NumberAnimation { target: notifCard; property: "opacity"; to: 0; duration: Animations.fast; easing.type: Easing.OutCubic }
                                                        NumberAnimation { target: notifCard; property: "x"; to: 24; duration: Animations.fast; easing.type: Easing.OutCubic }
                                                    }
                                                    ScriptAction { script: UIState.dismissNotif(modelData.id) }
                                                }

                                                MouseArea {
                                                    id: nItemMa
                                                    anchors.fill: parent
                                                    anchors.rightMargin: 30
                                                    hoverEnabled: true
                                                }

                                                Text {
                                                    id: nTitle
                                                    x: 14; y: 12
                                                    width: notifCard.width - 42
                                                    text:  modelData.title
                                                    color: Colors.fg
                                                    font { pixelSize: 11; family: "JetBrainsMono Nerd Font"; bold: true }
                                                    wrapMode: Text.WordWrap
                                                }

                                                Text {
                                                    id: nBody
                                                    x: 14
                                                    anchors.top: nTitle.bottom
                                                    anchors.topMargin: 6
                                                    width: notifCard.width - 42
                                                    text:  modelData.body
                                                    color: a(Colors.fg, 0.5)
                                                    font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                                                    wrapMode: Text.WordWrap
                                                    lineHeight: 1.35
                                                    visible: modelData.body !== ""
                                                }

                                                Text {
                                                    anchors { right: parent.right; top: parent.top; rightMargin: 10; topMargin: 12 }
                                                    text:  "󰅖"
                                                    color: nDismissMa.containsMouse ? Colors.red : a(Colors.fg, 0.2)
                                                    font { pixelSize: 11; family: "JetBrainsMono Nerd Font" }
                                                    Behavior on color { ColorAnimation { duration: Animations.fast } }

                                                    MouseArea {
                                                        id: nDismissMa
                                                        anchors.fill: parent; anchors.margins: -6
                                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: cardDismissAnim.start()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            SequentialAnimation {
                                id: groupDismissAnim
                                property string targetApp: ""
                                ParallelAnimation {
                                    NumberAnimation { target: groupDelegate; property: "opacity"; to: 0; duration: Animations.fast; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: groupDelegate; property: "x"; to: 24; duration: Animations.fast; easing.type: Easing.OutCubic }
                                }
                                ScriptAction { script: UIState.dismissGroup(groupDismissAnim.targetApp) }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: pfpPickerOverlay
            anchors.fill: parent
            color:   a(Colors.bg, UIState.transparencyEnabled ? 0.95 : 1)
            radius:  16
            opacity: pfpPicker ? 1 : 0
            scale:   pfpPicker ? 1 : 0.97
            visible: opacity > 0
            transformOrigin: Item.Center

            Behavior on opacity { NumberAnimation { duration: Animations.medium; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: Animations.medium; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
            Behavior on color   { ColorAnimation  { duration: Animations.slow } }

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16

                Item {
                    width: parent.width; height: 28

                    Text {
                        text:  "Choose Avatar"
                        color: Colors.fg
                        font { pixelSize: 16; family: "JetBrainsMono Nerd Font"; bold: true }
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    }

                    Text {
                        text:  "󰅖"
                        color: pfpCloseMa.containsMouse ? Colors.fg : a(Colors.fg, 0.4)
                        font { pixelSize: 16; family: "JetBrainsMono Nerd Font" }
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        Behavior on color { ColorAnimation { duration: Animations.fast } }

                        MouseArea {
                            id: pfpCloseMa
                            anchors.fill: parent; anchors.margins: -6
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: pfpPicker = false
                        }
                    }
                }

                Flickable {
                    width:         parent.width
                    height:        parent.height - 44
                    contentHeight: pfpGrid.height
                    clip:          true
                    boundsBehavior: Flickable.StopAtBounds

                    Grid {
                        id: pfpGrid
                        width:   parent.width
                        columns: 4
                        spacing: 12

                        Repeater {
                            model: pfpList

                            Item {
                                required property int index
                                required property string modelData
                                width:  (pfpGrid.width - 36) / 4
                                height: width

                                scale: pfpItemMa.containsMouse ? 1.06 : 1
                                Behavior on scale {
                                    NumberAnimation { duration: Animations.medium; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: width / 2
                                    color: UIState.pfpIndex === index ? a(Colors.accent, 0.2) : pfpItemMa.containsMouse ? a(Colors.fg, 0.1) : a(Colors.surface, 0.8)
                                    border.width: UIState.pfpIndex === index ? 2.5 : 0
                                    border.color: Colors.accent

                                    Behavior on color { ColorAnimation { duration: Animations.fast } }
                                    Behavior on border.width { NumberAnimation { duration: Animations.fast } }
                                }

                                Image {
                                    id: pfpItemImg
                                    anchors.fill: parent
                                    anchors.margins: 5
                                    source: "file://" + modelData
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize: Qt.size(96, 96)
                                    smooth: true
                                    antialiasing: true
                                    visible: false
                                }

                                Rectangle {
                                    id: pfpItemMask
                                    anchors.fill: pfpItemImg
                                    radius: width / 2
                                    visible: false
                                }

                                OpacityMask {
                                    anchors.fill: pfpItemImg
                                    source: pfpItemImg
                                    maskSource: pfpItemMask
                                }

                                MouseArea {
                                    id: pfpItemMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { UIState.setPfpIndex(index); pfpPicker = false }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: powerScreen
            anchors.fill: parent
            color:   a(Colors.bg, UIState.transparencyEnabled ? 0.95 : 1)
            radius:  16
            opacity: powerOverlay ? 1 : 0
            scale:   powerOverlay ? 1 : 0.97
            visible: opacity > 0
            transformOrigin: Item.Center

            Behavior on opacity { NumberAnimation { duration: Animations.medium; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: Animations.medium; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
            Behavior on color   { ColorAnimation  { duration: Animations.slow } }

            Column {
                anchors.centerIn: parent
                spacing: 28

                Text {
                    text:  "Power"
                    color: Colors.fg
                    font { pixelSize: 20; family: "JetBrainsMono Nerd Font"; bold: true }
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Grid {
                    columns: 2
                    spacing: 18
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: [
                            { icon: "󰐥", label: "Shutdown", color: Colors.red,    cmd: "systemctl poweroff" },
                            { icon: "󰜉", label: "Reboot",   color: Colors.yellow, cmd: "systemctl reboot" },
                            { icon: "󰒲", label: "Suspend",  color: Colors.green,  cmd: "systemctl suspend" },
                            { icon: "󰌾", label: "Lock",     color: Colors.accent, cmd: "hyprlock" }
                        ]

                        Rectangle {
                            width:  (panelWidth - 96) / 2
                            height: 82
                            radius: 16
                            color:  pwrMa.containsMouse ? a(modelData.color, 0.15) : a(Colors.surface, 0.8)
                            scale:  pwrMa.pressed ? 0.92 : 1

                            Behavior on color { ColorAnimation { duration: Animations.fast } }
                            Behavior on scale { NumberAnimation { duration: Animations.snap; easing.type: Easing.OutQuad } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text:  modelData.icon
                                    color: pwrMa.containsMouse ? modelData.color : a(modelData.color, 0.6)
                                    font { pixelSize: 26; family: "JetBrainsMono Nerd Font" }
                                    Behavior on color { ColorAnimation { duration: Animations.fast } }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text:  modelData.label
                                    color: a(Colors.fg, 0.4)
                                    font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                                }
                            }

                            MouseArea {
                                id: pwrMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { powerProc.command = ["bash", "-c", modelData.cmd]; powerProc.running = true }
                            }
                        }
                    }
                }

                Rectangle {
                    width:  100; height: 34; radius: 17
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: backMa.containsMouse ? a(Colors.fg, 0.08) : a(Colors.surface, 0.8)
                    scale: backMa.pressed ? 0.92 : 1

                    Behavior on color { ColorAnimation { duration: Animations.fast } }
                    Behavior on scale { NumberAnimation { duration: Animations.snap; easing.type: Easing.OutQuad } }

                    Text {
                        anchors.centerIn: parent
                        text:  "Back"
                        color: a(Colors.fg, 0.5)
                        font { pixelSize: 11; family: "JetBrainsMono Nerd Font" }
                    }

                    MouseArea {
                        id: backMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: powerOverlay = false
                    }
                }
            }
        }
    }

    component SliderRow: Item {
        property string icon
        property color  iconColor
        property int    value
        signal moved(int v)

        height: 24

        Row {
            anchors.fill: parent
            spacing: 14

            Text {
                width: 22
                text:  icon
                color: iconColor
                font { pixelSize: 16; family: "JetBrainsMono Nerd Font" }
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                width:  parent.width - 68
                height: 6
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent; radius: 3
                    color: a(Colors.fg, 0.08)
                }

                Rectangle {
                    width:  parent.width * value / 100
                    height: parent.height; radius: 3
                    color:  iconColor
                    Behavior on width { NumberAnimation { duration: 40 } }
                }

                Rectangle {
                    x: Math.max(0, (parent.width * value / 100) - 7)
                    anchors.verticalCenter: parent.verticalCenter
                    width:  14; height: 14; radius: 7
                    color:  iconColor
                    scale:   sliderMa.containsMouse || sliderMa.pressed ? 1 : 0.6
                    opacity: sliderMa.containsMouse || sliderMa.pressed ? 1 : 0

                    Behavior on scale   { NumberAnimation { duration: Animations.snap; easing.type: Easing.OutBack; easing.overshoot: Animations.springPower } }
                    Behavior on opacity { NumberAnimation { duration: Animations.snap } }
                }

                MouseArea {
                    id: sliderMa
                    anchors.fill: parent; anchors.margins: -12
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onPressed:         mouse => updateVal(mouse.x)
                    onPositionChanged: mouse => { if (pressed) updateVal(mouse.x) }
                    function updateVal(x) { moved(Math.round(Math.max(0, Math.min(100, x / parent.width * 100)))) }
                }
            }

            Text {
                width: 28
                text:  value
                color: a(Colors.fg, 0.4)
                font { pixelSize: 11; family: "JetBrainsMono Nerd Font" }
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Process { id: powerProc }
}