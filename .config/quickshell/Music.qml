import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt5Compat.GraphicalEffects

PanelWindow {
    id: music

    property bool showing: UIState.activeDropdown === "media"
    property bool _visible: false
    property bool pickerOpen: false
    property int pickerTab: 0

    property var gifFiles: []
    property bool gifsLoaded: false
    property int previewIndex: 0
    property int displayMode: UIState.mediaDisplayMode
    property bool vinylWithArt: UIState.mediaVinylWithArt
    property bool applyingGif: false
    property string gifSource: ""
    property bool gifReady: false

    property real vinylRotation: 0
    property bool vinylHeld: false
    property real dragStartPos: 0
    property real lastX: 0
    property real totalDrag: 0

    property string vinylAsset: "file://" + Quickshell.env("HOME") + "/.config/quickshell/assets/Vinyl.png"

    visible: _visible
    anchors { top: true; bottom: true; left: true; right: true }
    margins.top: 38
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "music"
    WlrLayershell.keyboardFocus: showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function a(c, o) { return Qt.rgba(c.r, c.g, c.b, o) }

    function formatTime(s) {
        var m   = Math.floor(s / 60)
        var sec = Math.floor(s % 60)
        return m + ":" + (sec < 10 ? "0" : "") + sec
    }

    function gifName(path) {
        var parts = path.split("/")
        return parts[parts.length - 1].replace(".gif", "")
    }

    function isVinylMode() { return displayMode === 1 }

    function resumePlayback() {
        if (!vinylHeld) return
        var finalPos = Math.max(0, Math.min(UIState.mediaLen, dragStartPos + totalDrag * (UIState.mediaLen / 800)))
        vinylHeld    = false
        totalDrag    = 0
        UIState.mediaPos = finalPos
        seekAndPlayProc.command = ["bash", "-c", "mpc seek " + Math.floor(finalPos) + " && mpc play"]
        seekAndPlayProc.running = true
        unblockPoll.start()
    }

    function reloadGif() {
        gifReady  = false
        gifSource = ""
        gifClearDelay.start()
    }

    Timer {
        id: gifClearDelay
        interval: 60
        onTriggered: {
            gifSource  = "file://" + UIState._gifPath + "/current.gif"
            applyingGif = false
            gifReadyDelay.start()
        }
    }

    Timer {
        id: gifReadyDelay
        interval: 80
        onTriggered: gifReady = true
    }

    Timer {
        id: unblockPoll
        interval: 2500
        onTriggered: UIState.blockMediaPosUpdate = false
    }

    onShowingChanged: {
        if (showing) {
            _visible   = true
            pickerOpen = false
            pickerTab  = displayMode
            if (displayMode === 0 && gifSource === "") reloadGif()
        } else {
            closeDelay.start()
        }
    }

    Timer {
        id: closeDelay
        interval: 300
        onTriggered: { _visible = false; pickerOpen = false }
    }

    Timer {
        id: rotationTimer
        interval: 16
        repeat: true
        running: UIState.mediaState === "playing" && !vinylHeld && _visible && isVinylMode()
        onTriggered: vinylRotation += 0.4
    }

    Timer {
        id: seekDebounce
        interval: 80
        onTriggered: {
            if (!vinylHeld || UIState.mediaLen <= 0) return
            var seekDelta = totalDrag * (UIState.mediaLen / 800)
            var newPos    = Math.max(0, Math.min(UIState.mediaLen, dragStartPos + seekDelta))
            UIState.mediaPos = newPos
        }
    }

    Process { id: pauseProc }
    Process { id: seekAndPlayProc }
    Process { id: seekClickProc }

    function loadGifs() {
        gifFiles     = []
        gifsLoaded   = false
        previewIndex = 0
        gifListProc.running = true
    }

    function applyGif() {
        if (applyingGif || gifFiles.length === 0 || previewIndex >= gifFiles.length) return
        applyingGif          = true
        gifApplyProc.command = ["cp", gifFiles[previewIndex], UIState._gifPath + "/current.gif"]
        gifApplyProc.running = true
    }

    Process {
        id: gifListProc
        command: ["bash", "-c", "find '" + UIState._gifPath + "' -maxdepth 1 -name '*.gif' ! -name 'current.gif' -type f 2>/dev/null | sort"]
        stdout: SplitParser {
            onRead: data => {
                var f = data.trim()
                if (f.length > 0) {
                    var cur = gifFiles.slice()
                    cur.push(f)
                    gifFiles = cur
                }
            }
        }
        onExited: {
            gifsLoaded = true
            if (gifFiles.length > 0)
                previewIndex = Math.min(UIState.gifIndex, gifFiles.length - 1)
        }
    }

    Process {
        id: gifApplyProc
        onExited: code => {
            if (code === 0) {
                UIState.setGifIndex(previewIndex)
                pickerOpen = false
                gifReloadDelay.start()
            } else {
                applyingGif = false
            }
        }
    }

    Timer {
        id: gifReloadDelay
        interval: 250
        onTriggered: reloadGif()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: UIState.closeDropdowns()
    }

    Rectangle {
        id: card
        width: Math.min(parent.width - 40, 460)
        height: pickerOpen ? 420 : 210
        anchors.horizontalCenter: parent.horizontalCenter
        y: showing ? 8 : -440
        radius: 18
        color: a(Colors.bg, UIState.transparencyEnabled ? 0.92 : 1)
        border.width: 1
        border.color: a(Colors.fg, 0.08)

        Behavior on y      { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        Behavior on color  { ColorAnimation  { duration: 300 } }

        MouseArea { anchors.fill: parent }

        focus: showing

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (pickerOpen) pickerOpen = false
                else UIState.closeDropdowns()
                event.accepted = true
            } else if (event.key === Qt.Key_Space && !pickerOpen) {
                UIState.doMedia("play-pause")
                event.accepted = true
            } else if (event.key === Qt.Key_N && !pickerOpen) {
                UIState.doMedia("next")
                event.accepted = true
            } else if (event.key === Qt.Key_P && !pickerOpen) {
                UIState.doMedia("previous")
                event.accepted = true
            } else if (event.key === Qt.Key_Left && pickerOpen && pickerTab === 0 && gifFiles.length > 1) {
                previewIndex = previewIndex > 0 ? previewIndex - 1 : gifFiles.length - 1
                event.accepted = true
            } else if (event.key === Qt.Key_Right && pickerOpen && pickerTab === 0 && gifFiles.length > 1) {
                previewIndex = previewIndex < gifFiles.length - 1 ? previewIndex + 1 : 0
                event.accepted = true
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && pickerOpen && pickerTab === 0) {
                if (previewIndex !== UIState.gifIndex) applyGif()
                event.accepted = true
            }
        }

        Item {
            anchors.fill: parent
            anchors.margins: 16

            Item {
                id: mainSection
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 178

                Item {
                    anchors { top: parent.top; bottom: parent.bottom; left: parent.left; right: mediaSide.left; rightMargin: 14 }

                    Text {
                        id: titleText
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        text: UIState.mediaTitle || "Nothing playing"
                        color: Colors.fg
                        font { pixelSize: 14; family: "JetBrainsMono Nerd Font"; bold: true }
                        elide: Text.ElideRight
                    }

                    Text {
                        id: artistText
                        anchors { top: titleText.bottom; topMargin: 3; left: parent.left; right: parent.right }
                        text: UIState.mediaArtist || ""
                        color: a(Colors.fg, 0.45)
                        font { pixelSize: 11; family: "JetBrainsMono Nerd Font" }
                        elide: Text.ElideRight
                        visible: UIState.mediaArtist !== ""
                    }

                    Item {
                        anchors { left: parent.left; right: parent.right; bottom: controlRow.top; bottomMargin: 10 }
                        height: 20
                        visible: UIState.hasMedia

                        Text {
                            id: posText
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: formatTime(UIState.mediaPos)
                            color: a(Colors.fg, 0.3)
                            font { pixelSize: 9; family: "JetBrainsMono Nerd Font" }
                        }

                        Item {
                            anchors { left: posText.right; leftMargin: 8; right: lenText.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            height: 4

                            Rectangle {
                                anchors.fill: parent
                                radius: 2
                                color: a(Colors.fg, 0.08)
                            }

                            Rectangle {
                                width: UIState.mediaLen > 0 ? parent.width * (UIState.mediaPos / UIState.mediaLen) : 0
                                height: parent.height
                                radius: 2
                                color: Colors.accent
                            }

                            Rectangle {
                                x: UIState.mediaLen > 0 ? Math.max(0, parent.width * (UIState.mediaPos / UIState.mediaLen) - 5) : -5
                                anchors.verticalCenter: parent.verticalCenter
                                width: seekMa.containsMouse ? 12 : 10
                                height: width; radius: width / 2
                                color: Colors.fg
                                visible: UIState.hasMedia
                                Behavior on width { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: seekMa
                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    if (UIState.mediaLen > 0) {
                                        var ratio = Math.max(0, Math.min(1, mouse.x / parent.width))
                                        var pos   = Math.floor(ratio * UIState.mediaLen)
                                        seekClickProc.command = ["mpc", "seek", pos.toString()]
                                        seekClickProc.running = true
                                        UIState.mediaPos = pos
                                    }
                                }
                            }
                        }

                        Text {
                            id: lenText
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: formatTime(UIState.mediaLen)
                            color: a(Colors.fg, 0.3)
                            font { pixelSize: 9; family: "JetBrainsMono Nerd Font" }
                        }
                    }

                    Row {
                        id: controlRow
                        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                        spacing: 8

                        Rectangle {
                            width: 34; height: 34; radius: 10
                            color: prevMa.containsMouse ? a(Colors.fg, 0.08) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰒮"
                                color: prevMa.containsMouse ? Colors.fg : a(Colors.fg, 0.5)
                                font { pixelSize: 16; family: "JetBrainsMono Nerd Font" }
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: prevMa
                                anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: UIState.doMedia("previous")
                            }
                        }

                        Rectangle {
                            width: 44; height: 44; radius: 22
                            anchors.verticalCenter: parent.verticalCenter
                            color: playMa.containsMouse ? Colors.accent : a(Colors.accent, 0.9)
                            scale: playMa.pressed ? 0.92 : 1

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 80 } }

                            Text {
                                anchors.centerIn: parent
                                text: UIState.mediaState === "playing" ? "󰏤" : "󰐊"
                                color: Colors.bg
                                font { pixelSize: 18; family: "JetBrainsMono Nerd Font" }
                            }

                            MouseArea {
                                id: playMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: UIState.doMedia("play-pause")
                            }
                        }

                        Rectangle {
                            width: 34; height: 34; radius: 10
                            color: nextMa.containsMouse ? a(Colors.fg, 0.08) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰒭"
                                color: nextMa.containsMouse ? Colors.fg : a(Colors.fg, 0.5)
                                font { pixelSize: 16; family: "JetBrainsMono Nerd Font" }
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: nextMa
                                anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: UIState.doMedia("next")
                            }
                        }
                    }
                }

                Item {
                    id: mediaSide
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                    width: 158

                    AnimatedImage {
                        anchors.fill: parent
                        source: displayMode === 0 && showing && gifReady ? gifSource : ""
                        fillMode: Image.PreserveAspectFit
                        playing: true
                        cache: false
                        asynchronous: true
                        visible: displayMode === 0 && gifReady
                        opacity: gifReady ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    Item {
                        anchors.centerIn: parent
                        width: Math.min(mediaSide.width, mediaSide.height)
                        height: width
                        visible: isVinylMode()

                        Item {
                            id: vinylDisc
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.width
                            rotation: vinylRotation

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: parent.width
                                radius: width / 2
                                color: "#0d0d0d"

                                layer.enabled: true
                                layer.effect: DropShadow {
                                    transparentBorder: true
                                    horizontalOffset: 0
                                    verticalOffset: 4
                                    radius: 16
                                    samples: 33
                                    color: "#bb000000"
                                }
                            }

                            Repeater {
                                model: 8
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width * (0.97 - index * 0.016)
                                    height: width
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: index % 2 === 0 ? 1 : 0.5
                                    border.color: index % 2 === 0 ? Qt.rgba(1, 1, 1, 0.055) : Qt.rgba(1, 1, 1, 0.022)
                                }
                            }

                            Item {
                                anchors.centerIn: parent
                                width: parent.width * 0.75
                                height: width

                                Image {
                                    id: artImage
                                    anchors.fill: parent
                                    source: vinylWithArt && UIState.mediaArtUrl !== "" ? UIState.mediaArtUrl : vinylAsset
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true
                                    asynchronous: true
                                    sourceSize: Qt.size(300, 300)
                                    visible: false
                                }

                                Rectangle {
                                    id: artMask
                                    anchors.fill: parent
                                    radius: width / 2
                                    visible: false
                                }

                                OpacityMask {
                                    anchors.fill: artImage
                                    source: artImage
                                    maskSource: artMask
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.07)
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 0.08
                                height: width
                                radius: width / 2
                                color: "#1e1e1e"
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.1)
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 4; height: 4; radius: 2
                                color: Colors.accent
                                opacity: 0.9
                            }
                        }

                        MouseArea {
                            id: vinylMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: vinylHeld ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                            onPressed: {
                                vinylHeld    = true
                                totalDrag    = 0
                                lastX        = mouseX
                                dragStartPos = UIState.mediaPos
                                UIState.blockMediaPosUpdate = true
                                pauseProc.command = ["mpc", "pause"]
                                pauseProc.running = true
                            }

                            onReleased: resumePlayback()
                            onCanceled: resumePlayback()

                            onPositionChanged: {
                                if (!pressed) return
                                var dx = mouseX - lastX
                                lastX  = mouseX
                                if (Math.abs(dx) > 0) {
                                    totalDrag     += dx
                                    vinylRotation += dx * 3.5
                                    if (Math.abs(totalDrag) > 4) seekDebounce.restart()
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors { top: parent.top; right: parent.right }
                        width: 22; height: 22; radius: 11
                        color: editMa.containsMouse ? a(Colors.accent, 0.2) : a(Colors.fg, 0.06)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰏫"
                            color: editMa.containsMouse ? Colors.accent : a(Colors.fg, 0.35)
                            font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: editMa
                            anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!pickerOpen) { loadGifs(); pickerOpen = true }
                                else pickerOpen = false
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors { top: mainSection.bottom; topMargin: 6; left: parent.left; right: parent.right }
                height: 1
                color: a(Colors.fg, 0.05)
                visible: pickerOpen
            }

            Item {
                anchors { top: mainSection.bottom; topMargin: 14; left: parent.left; right: parent.right; bottom: parent.bottom }
                visible: pickerOpen
                opacity: pickerOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Row {
                    id: tabRow
                    anchors { top: parent.top; left: parent.left }
                    spacing: 6

                    Rectangle {
                        width: gifTabLabel.implicitWidth + 20
                        height: 26; radius: 8
                        color: pickerTab === 0 ? a(Colors.accent, 0.15) : gifTabMa.containsMouse ? a(Colors.fg, 0.06) : a(Colors.fg, 0.03)
                        border.width: pickerTab === 0 ? 1 : 0
                        border.color: a(Colors.accent, 0.3)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            id: gifTabLabel
                            anchors.centerIn: parent
                            text: "GIF"
                            color: pickerTab === 0 ? Colors.accent : a(Colors.fg, 0.35)
                            font { pixelSize: 9; family: "JetBrainsMono Nerd Font"; bold: true; letterSpacing: 0.8 }
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: gifTabMa
                            anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                pickerTab   = 0
                                displayMode = 0
                                UIState.setMediaDisplayMode(0)
                            }
                        }
                    }

                    Rectangle {
                        width: vinylTabLabel.implicitWidth + 20
                        height: 26; radius: 8
                        color: pickerTab === 1 ? a(Colors.accent, 0.15) : vinylTabMa.containsMouse ? a(Colors.fg, 0.06) : a(Colors.fg, 0.03)
                        border.width: pickerTab === 1 ? 1 : 0
                        border.color: a(Colors.accent, 0.3)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            id: vinylTabLabel
                            anchors.centerIn: parent
                            text: "VINYL"
                            color: pickerTab === 1 ? Colors.accent : a(Colors.fg, 0.35)
                            font { pixelSize: 9; family: "JetBrainsMono Nerd Font"; bold: true; letterSpacing: 0.8 }
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: vinylTabMa
                            anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                pickerTab   = 1
                                displayMode = 1
                                UIState.setMediaDisplayMode(1)
                            }
                        }
                    }
                }

                Item {
                    anchors { top: tabRow.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: pickerBtnsArea.top; bottomMargin: 8 }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: a(Colors.surface, 0.4)
                        border.width: 1
                        border.color: a(Colors.fg, 0.04)
                        clip: true
                        visible: pickerTab === 0

                        AnimatedImage {
                            anchors.fill: parent
                            anchors.margins: 8
                            source: pickerOpen && gifsLoaded && gifFiles.length > 0 && pickerTab === 0 && previewIndex < gifFiles.length
                                ? "file://" + gifFiles[previewIndex] : ""
                            fillMode: Image.PreserveAspectFit
                            playing: pickerOpen
                            cache: false
                            asynchronous: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !gifsLoaded && pickerTab === 0
                            text: "Loading..."
                            color: a(Colors.fg, 0.15)
                            font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: gifsLoaded && gifFiles.length === 0 && pickerTab === 0
                            text: "No gifs in assets/gifs"
                            color: a(Colors.fg, 0.15)
                            font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                        }

                        Rectangle {
                            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 6 }
                            visible: gifsLoaded && gifFiles.length > 0 && pickerTab === 0
                            width: gifNameLabel.implicitWidth + 12; height: 18; radius: 9
                            color: a("#000", 0.45)

                            Text {
                                id: gifNameLabel
                                anchors.centerIn: parent
                                text: gifFiles.length > 0 ? gifName(gifFiles[previewIndex]) : ""
                                color: "#fff"
                                font { pixelSize: 8; family: "JetBrainsMono Nerd Font" }
                                opacity: 0.8
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: pickerTab === 1

                        Item {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) - 16
                            height: width

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: parent.width
                                radius: width / 2
                                color: "#0d0d0d"
                                rotation: vinylRotation

                                Repeater {
                                    model: 8
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * (0.97 - index * 0.016)
                                        height: width
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: index % 2 === 0 ? 1 : 0.5
                                        border.color: index % 2 === 0 ? Qt.rgba(1, 1, 1, 0.055) : Qt.rgba(1, 1, 1, 0.022)
                                    }
                                }

                                Item {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.75
                                    height: width

                                    Image {
                                        id: pickerArtImage
                                        anchors.fill: parent
                                        source: vinylWithArt && UIState.mediaArtUrl !== "" ? UIState.mediaArtUrl : vinylAsset
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        asynchronous: true
                                        sourceSize: Qt.size(300, 300)
                                        visible: false
                                    }

                                    Rectangle {
                                        id: pickerArtMask
                                        anchors.fill: parent
                                        radius: width / 2
                                        visible: false
                                    }

                                    OpacityMask {
                                        anchors.fill: pickerArtImage
                                        source: pickerArtImage
                                        maskSource: pickerArtMask
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.07)
                                    }
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.08
                                    height: width
                                    radius: width / 2
                                    color: "#1e1e1e"
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.1)
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 4; height: 4; radius: 2
                                    color: Colors.accent
                                }
                            }
                        }

                        Row {
                            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 10 }
                            spacing: 8

                            Rectangle {
                                width: withArtLabel.implicitWidth + 16
                                height: 24; radius: 8
                                color: vinylWithArt ? a(Colors.accent, 0.15) : withArtMa.containsMouse ? a(Colors.fg, 0.06) : a(Colors.fg, 0.03)
                                border.width: vinylWithArt ? 1 : 0
                                border.color: a(Colors.accent, 0.3)
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    id: withArtLabel
                                    anchors.centerIn: parent
                                    text: "With Art"
                                    color: vinylWithArt ? Colors.accent : a(Colors.fg, 0.35)
                                    font { pixelSize: 9; family: "JetBrainsMono Nerd Font" }
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                MouseArea {
                                    id: withArtMa
                                    anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        vinylWithArt = true
                                        UIState.setMediaVinylWithArt(true)
                                    }
                                }
                            }

                            Rectangle {
                                width: noArtLabel.implicitWidth + 16
                                height: 24; radius: 8
                                color: !vinylWithArt ? a(Colors.accent, 0.15) : noArtMa.containsMouse ? a(Colors.fg, 0.06) : a(Colors.fg, 0.03)
                                border.width: !vinylWithArt ? 1 : 0
                                border.color: a(Colors.accent, 0.3)
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    id: noArtLabel
                                    anchors.centerIn: parent
                                    text: "No Art"
                                    color: !vinylWithArt ? Colors.accent : a(Colors.fg, 0.35)
                                    font { pixelSize: 9; family: "JetBrainsMono Nerd Font" }
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                MouseArea {
                                    id: noArtMa
                                    anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        vinylWithArt = false
                                        UIState.setMediaVinylWithArt(false)
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    id: pickerBtnsArea
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 30

                    Row {
                        anchors.fill: parent
                        spacing: 6
                        visible: pickerTab === 0

                        Rectangle {
                            width: 32; height: 30; radius: 8
                            color: prevGif.containsMouse ? a(Colors.accent, 0.12) : a(Colors.fg, 0.05)
                            opacity: gifFiles.length > 1 ? 1 : 0.3
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰅁"
                                color: prevGif.containsMouse ? Colors.accent : a(Colors.fg, 0.4)
                                font { pixelSize: 13; family: "JetBrainsMono Nerd Font" }
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: prevGif
                                anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                enabled: gifFiles.length > 1
                                onClicked: previewIndex = previewIndex > 0 ? previewIndex - 1 : gifFiles.length - 1
                            }
                        }

                        Rectangle {
                            width: 32; height: 30; radius: 8
                            color: nextGif.containsMouse ? a(Colors.accent, 0.12) : a(Colors.fg, 0.05)
                            opacity: gifFiles.length > 1 ? 1 : 0.3
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰅂"
                                color: nextGif.containsMouse ? Colors.accent : a(Colors.fg, 0.4)
                                font { pixelSize: 13; family: "JetBrainsMono Nerd Font" }
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: nextGif
                                anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                enabled: gifFiles.length > 1
                                onClicked: previewIndex = previewIndex < gifFiles.length - 1 ? previewIndex + 1 : 0
                            }
                        }

                        Item { width: parent.width - 32 * 2 - 6 * 2 - applyRect.width; height: 1 }

                        Rectangle {
                            id: applyRect
                            width: applyLabel.implicitWidth + 18
                            height: 30; radius: 8
                            property bool canApply: previewIndex !== UIState.gifIndex && !applyingGif && gifFiles.length > 0
                            color: canApply ? (applyMa.containsMouse ? a(Colors.accent, 0.2) : a(Colors.accent, 0.1)) : a(Colors.fg, 0.03)
                            border.width: canApply ? 1 : 0
                            border.color: a(Colors.accent, applyMa.containsMouse ? 0.4 : 0.2)
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: applyLabel
                                anchors.centerIn: parent
                                text: applyingGif ? "..." : previewIndex === UIState.gifIndex ? "󰄬 Current" : "󰸞 Apply"
                                color: applyRect.canApply ? (applyMa.containsMouse ? Colors.accent : a(Colors.accent, 0.7)) : a(Colors.fg, 0.2)
                                font { pixelSize: 10; family: "JetBrainsMono Nerd Font"; bold: true }
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: applyMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: applyRect.canApply ? Qt.PointingHandCursor : Qt.ArrowCursor
                                enabled: applyRect.canApply
                                onClicked: applyGif()
                            }
                        }
                    }

                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        visible: pickerTab === 1

                        Rectangle {
                            width: applyVinylLabel.implicitWidth + 18
                            height: 30; radius: 8
                            color: applyVinylMa.containsMouse ? a(Colors.accent, 0.2) : a(Colors.accent, 0.1)
                            border.width: 1
                            border.color: a(Colors.accent, applyVinylMa.containsMouse ? 0.4 : 0.2)
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: applyVinylLabel
                                anchors.centerIn: parent
                                text: "󰸞 Apply"
                                color: applyVinylMa.containsMouse ? Colors.accent : a(Colors.accent, 0.7)
                                font { pixelSize: 10; family: "JetBrainsMono Nerd Font"; bold: true }
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: applyVinylMa
                                anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: pickerOpen = false
                            }
                        }
                    }
                }
            }
        }
    }
}