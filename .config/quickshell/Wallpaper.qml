import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt5Compat.GraphicalEffects

PanelWindow {
    id: wallpaper

    property bool showing: UIState.activeDropdown === "wallpaper"
    property bool ready: false
    property var walls: []
    property var filtered: []
    property var wallColors: ({})
    property string query: ""
    property int selected: 0
    property int colorFilter: -1
    property var _wallsBuild: []
    property var _pendingColors: ({})
    property string currentWall: ""
    property int thumbVersion: 0
    property bool _skipInitialAnim: true

    property string cachePath: Quickshell.env("HOME") + "/.cache/wallpaper-thumbs"
    property string wallDir: Quickshell.env("HOME") + "/wallpapers"

    property int sliceWidth: 58
    property int expandedWidth: screen ? Math.min(screen.width * 0.52, 680) : 580

    visible: showing
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "wallpaper"
    WlrLayershell.keyboardFocus: showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function a(c, o) { return Qt.rgba(c.r, c.g, c.b, o) }

    property var colorDots: [
        { hue: 0,   label: "Red",     color: "#ef4444" },
        { hue: 30,  label: "Orange",  color: "#f97316" },
        { hue: 55,  label: "Yellow",  color: "#eab308" },
        { hue: 120, label: "Green",   color: "#22c55e" },
        { hue: 180, label: "Cyan",    color: "#06b6d4" },
        { hue: 220, label: "Blue",    color: "#3b82f6" },
        { hue: 270, label: "Purple",  color: "#a855f7" },
        { hue: 330, label: "Pink",    color: "#ec4899" },
        { hue: -1,  label: "Neutral", color: "#777777" }
    ]

    Component.onCompleted: cacheLoadProc.running = true

    onShowingChanged: {
        if (showing) {
            query = ""
            selected = 0
            colorFilter = -1
            searchInput.text = ""
            _pendingColors = {}
            _skipInitialAnim = true
            ready = false
            currentWallProc.running = true
        } else {
            ready = false
        }
    }

    Timer {
        id: listReadyDelay
        interval: 50
        onTriggered: {
            ready = true
            enableAnimDelay.start()
            focusDelay.start()
        }
    }

    Timer {
        id: focusDelay
        interval: 80
        onTriggered: searchInput.forceActiveFocus()
    }

    Timer {
        id: enableAnimDelay
        interval: 100
        onTriggered: _skipInitialAnim = false
    }

    Timer {
        id: colorFlush
        interval: 400
        repeat: true
        running: colorExtractProc.running
        onTriggered: {
            var keys = Object.keys(_pendingColors)
            if (keys.length === 0) return
            for (var i = 0; i < keys.length; i++)
                wallColors[keys[i]] = _pendingColors[keys[i]]
            wallColors = Object.assign({}, wallColors)
            _pendingColors = {}
        }
    }

    function hexToHsl(hex) {
        hex = hex.replace("#", "")
        if (hex.length > 6) hex = hex.substring(0, 6)
        var r = parseInt(hex.substring(0, 2), 16) / 255
        var g = parseInt(hex.substring(2, 4), 16) / 255
        var b = parseInt(hex.substring(4, 6), 16) / 255
        var max = Math.max(r, g, b), min = Math.min(r, g, b)
        var h, s, l = (max + min) / 2
        if (max === min) {
            h = s = 0
        } else {
            var d = max - min
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
            if (max === r)      h = ((g - b) / d + (g < b ? 6 : 0)) / 6
            else if (max === g) h = ((b - r) / d + 2) / 6
            else                h = ((r - g) / d + 4) / 6
        }
        return { h: h * 360, s: s, l: l }
    }

    function getDominantHue(colorString) {
        if (!colorString || colorString.length === 0) return -2
        var hexList = colorString.split(",")
        if (hexList.length === 0) return -2

        var total = hexList.length
        var weightedH = 0
        var totalSat = 0
        var neutralCount = 0

        for (var i = 0; i < hexList.length; i++) {
            var hex = hexList[i].trim()
            if (hex.length < 6) continue
            var hsl = hexToHsl(hex)
            var vibrancy = hsl.s * (1 - Math.abs(2 * hsl.l - 1))
            var weight = vibrancy

            if (hsl.s < 0.08 || hsl.l < 0.04 || hsl.l > 0.96) {
                neutralCount++
                continue
            }

            weightedH += hsl.h * weight
            totalSat += weight
        }

        if (neutralCount === total) return -1
        if (totalSat < 0.05) return -1

        return weightedH / totalSat
    }

    function matchesColor(wallName) {
        if (colorFilter < 0) return true
        var dot = colorDots[colorFilter]
        var colorString = wallColors[wallName]
        if (!colorString) return false

        var dominantHue = getDominantHue(colorString)

        if (dot.hue < 0) return dominantHue === -1

        if (dominantHue === -1 || dominantHue === -2) return false

        var diff = Math.abs(dominantHue - dot.hue)
        if (diff > 180) diff = 360 - diff
        return diff < 50
    }

    function getRepresentativeColor(colorString) {
        if (!colorString || colorString.length === 0) return ""
        var hexList = colorString.split(",")
        var bestHex = ""
        var bestScore = -1

        for (var i = 0; i < hexList.length; i++) {
            var hex = hexList[i].trim()
            if (hex.length < 6) continue
            var hsl = hexToHsl(hex)
            var vibrancy = hsl.s * (1 - Math.abs(2 * hsl.l - 1))
            if (hsl.s < 0.08 || hsl.l < 0.04 || hsl.l > 0.96) continue
            if (vibrancy > bestScore) {
                bestScore = vibrancy
                bestHex = hex
            }
        }

        if (bestHex === "") {
            var parts = colorString.split(",")
            if (parts.length > 0) bestHex = parts[0].trim()
        }

        return bestHex
    }

    function filterWalls(preserve) {
        var prevName = preserve && selected < filtered.length ? filtered[selected].name : ""

        var result = walls.slice()

        if (query !== "") {
            var q = query.toLowerCase()
            result = result.filter(w => w.name.toLowerCase().includes(q))
            result.sort((a, b) => {
                var ai = a.name.toLowerCase().indexOf(q)
                var bi = b.name.toLowerCase().indexOf(q)
                if (ai !== bi) return ai - bi
                return a.name.length - b.name.length
            })
        }

        if (colorFilter >= 0)
            result = result.filter(w => matchesColor(w.name))

        filtered = result

        if (prevName) {
            for (var i = 0; i < result.length; i++) {
                if (result[i].name === prevName) { selected = i; return }
            }
        }
        selected = 0
    }

    function selectCurrentWall() {
        for (var i = 0; i < filtered.length; i++) {
            if (filtered[i].name === currentWall) { selected = i; return }
        }
    }

    function applyWallpaper(wall) {
        if (!wall) return
        var path = wallDir + "/" + wall.name
        applyProc.command = ["bash", "-c",
            "ln -sf '" + path + "' '" + wallDir + "/current' && " +
            "awww img '" + path + "' " +
            "--transition-type wipe " +
            "--transition-angle 30 " +
            "--transition-duration 1.5 " +
            "--transition-fps 60"]
        applyProc.running = true
        currentWall = wall.name
    }

    function prettyName(name) {
        var dot = name.lastIndexOf(".")
        var n = dot > 0 ? name.substring(0, dot) : name
        return n.replace(/[-_]/g, " ")
    }

    function pickRandom() {
        if (filtered.length < 2) return
        var idx = selected
        while (idx === selected)
            idx = Math.floor(Math.random() * filtered.length)
        selected = idx
    }

    function writeCache() {
        var arr = []
        for (var i = 0; i < walls.length; i++)
            arr.push({ name: walls[i].name, color: wallColors[walls[i].name] || "" })
        var json = JSON.stringify(arr)
        writeCacheProc.command = ["bash", "-c",
            "mkdir -p '" + cachePath + "' && cat > '" + cachePath + "/walls.json' << 'WCEOF'\n" + json + "\nWCEOF"]
        writeCacheProc.running = true
    }

    Process {
        id: cacheLoadProc
        command: ["cat", cachePath + "/walls.json"]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                try {
                    var arr = JSON.parse(data.trim())
                    var result = []
                    for (var i = 0; i < arr.length; i++) {
                        result.push({ name: arr[i].name })
                        if (arr[i].color) wallColors[arr[i].name] = arr[i].color
                    }
                    walls = result
                    wallColors = Object.assign({}, wallColors)
                    filtered = walls.slice()
                    thumbVersion = 1
                } catch(e) {}
            }
        }
    }

    Process {
        id: currentWallProc
        command: ["bash", "-c", "basename $(readlink -f $HOME/wallpapers/current) 2>/dev/null"]
        stdout: SplitParser { onRead: data => currentWall = data.trim() }
        onExited: {
            if (walls.length > 0) {
                filterWalls()
                selectCurrentWall()
                listReadyDelay.start()
            }
            _wallsBuild = []
            wallListProc.running = true
        }
    }

    Process {
        id: wallListProc
        command: ["bash", "-c", [
            "shopt -s nullglob",
            "CACHE=\"$HOME/.cache/wallpaper-thumbs\"",
            "mkdir -p \"$CACHE\"",
            "touch \"$CACHE/colors.tsv\"",
            "for f in \"$HOME\"/wallpapers/*.{jpg,jpeg,png,gif,webp}; do",
            "  [ -L \"$f\" ] && continue",
            "  name=$(basename \"$f\")",
            "  color=$(grep -F \"$name\" \"$CACHE/colors.tsv\" 2>/dev/null | head -1 | cut -f2)",
            "  echo \"${name}\t${color}\"",
            "done"
        ].join("\n")]
        stdout: SplitParser {
            onRead: data => {
                var line = data.trim()
                if (line.length === 0) return
                var p = line.split("\t")
                if (p[0]) {
                    _wallsBuild.push({ name: p[0] })
                    if (p[1] && p[1].length > 2) wallColors[p[0]] = p[1]
                }
            }
        }
        onExited: {
            var seen = {}
            var result = []
            for (var i = 0; i < _wallsBuild.length; i++) {
                if (!seen[_wallsBuild[i].name]) {
                    seen[_wallsBuild[i].name] = true
                    result.push(_wallsBuild[i])
                }
            }
            walls = result
            wallColors = Object.assign({}, wallColors)
            _wallsBuild = []

            if (ready) {
                filterWalls(true)
            } else {
                filterWalls()
                selectCurrentWall()
                listReadyDelay.start()
            }

            writeCache()
            colorExtractProc.running = true
        }
    }

    Process {
        id: colorExtractProc
        command: ["bash", "-c", [
            "shopt -s nullglob",
            "CACHE=\"$HOME/.cache/wallpaper-thumbs\"",
            "mkdir -p \"$CACHE\"",
            "touch \"$CACHE/colors.tsv\"",
            "",
            "for f in \"$HOME\"/wallpapers/*.{jpg,jpeg,png,gif,webp}; do",
            "  [ -L \"$f\" ] && continue",
            "  name=$(basename \"$f\")",
            "  thumb=\"$CACHE/${name}.thumb.jpg\"",
            "  [ -f \"$thumb\" ] && continue",
            "  magick \"${f}[0]\" -resize 600x -quality 85 \"$thumb\" 2>/dev/null",
            "done",
            "echo 'THUMBS_READY'",
            "",
            "for f in \"$HOME\"/wallpapers/*.{jpg,jpeg,png,gif,webp}; do",
            "  [ -L \"$f\" ] && continue",
            "  name=$(basename \"$f\")",
            "  grep -qF \"$name\" \"$CACHE/colors.tsv\" 2>/dev/null && continue",
            "  colors=''",
            "  while IFS= read -r line; do",
            "    count=$(echo \"$line\" | grep -oP '^\\s*\\K[0-9]+')",
            "    hex=$(echo \"$line\" | grep -oP '#[0-9A-Fa-f]{6}' | head -1)",
            "    [ -z \"$hex\" ] || [ -z \"$count\" ] && continue",
            "    h=\"${hex#\\#}\"",
            "    r=$((16#${h:0:2})) g=$((16#${h:2:2})) b=$((16#${h:4:2}))",
            "    mx=$r; [ $g -gt $mx ] && mx=$g; [ $b -gt $mx ] && mx=$b",
            "    mn=$r; [ $g -lt $mn ] && mn=$g; [ $b -lt $mn ] && mn=$b",
            "    lum=$(( (mx + mn) * 100 / 510 ))",
            "    [ $lum -lt 3 ] && continue",
            "    [ $lum -gt 97 ] && continue",
            "    [ -z \"$colors\" ] && colors=\"$hex\" || colors=\"$colors,$hex\"",
            "  done < <(magick \"${f}[0]\" -resize 200x200! -colors 12 -depth 8 -format '%c' histogram:info: 2>/dev/null | sort -rn)",
            "  [ -z \"$colors\" ] && continue",
            "  printf '%s\\t%s\\n' \"$name\" \"$colors\" >> \"$CACHE/colors.tsv\"",
            "  echo \"${name}\t${colors}\"",
            "done"
        ].join("\n")]
        stdout: SplitParser {
            onRead: data => {
                var line = data.trim()
                if (line.length === 0) return
                if (line === "THUMBS_READY") { thumbVersion++; return }
                var p = line.split("\t")
                if (p.length >= 2 && p[1])
                    _pendingColors[p[0]] = p[1]
            }
        }
        onExited: {
            var keys = Object.keys(_pendingColors)
            for (var i = 0; i < keys.length; i++)
                wallColors[keys[i]] = _pendingColors[keys[i]]
            if (keys.length > 0)
                wallColors = Object.assign({}, wallColors)
            _pendingColors = {}
            filterWalls(true)
            writeCache()
        }
    }

    Process { id: applyProc }
    Process { id: writeCacheProc }

    MouseArea {
        anchors.fill: parent
        onClicked: UIState.closeDropdowns()
    }

    Rectangle {
        id: card
        width: ready ? Math.min(parent.width - 40, 1200) : 300
        height: ready ? Math.min(parent.height - 70, 580) : 60
        anchors.centerIn: parent
        radius: 22
        color: a(Colors.bg, UIState.transparencyEnabled ? 0.92 : 1)
        border.width: 1
        border.color: a(Colors.fg, 0.08)
        opacity: ready ? 1 : 0

        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
        Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 300 } }

        Item {
            anchors.fill: parent
            anchors.margins: 22
            opacity: ready ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

            Item {
                id: topRow
                width: parent.width
                height: 40

                Rectangle {
                    width: Math.min(parent.width * 0.25, 220)
                    height: 36
                    radius: 18
                    color: a(Colors.surface, 0.6)
                    border.width: searchInput.activeFocus ? 1.5 : 0
                    border.color: a(Colors.accent, 0.5)
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }

                    Behavior on border.width { NumberAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: searchInput.activeFocus ? Colors.accent : a(Colors.fg, 0.3)
                            font { pixelSize: 12; family: "JetBrainsMono Nerd Font" }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        TextInput {
                            id: searchInput
                            width: parent.width - 44
                            anchors.verticalCenter: parent.verticalCenter
                            color: Colors.fg
                            font { pixelSize: 11; family: "JetBrainsMono Nerd Font" }
                            selectByMouse: true
                            clip: true

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search..."
                                color: a(Colors.fg, 0.2)
                                font: parent.font
                                visible: !parent.text && !parent.activeFocus
                            }

                            onTextChanged: {
                                query = text.toLowerCase()
                                filterWalls()
                            }

                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Left) {
                                    if (selected > 0) selected--
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Right) {
                                    if (selected < filtered.length - 1) selected++
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Home) {
                                    selected = 0
                                    event.accepted = true
                                } else if (event.key === Qt.Key_End) {
                                    selected = Math.max(0, filtered.length - 1)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_PageUp) {
                                    selected = Math.max(0, selected - 10)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_PageDown) {
                                    selected = Math.min(filtered.length - 1, selected + 10)
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    if (filtered.length > 0) applyWallpaper(filtered[selected])
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Escape) {
                                    UIState.closeDropdowns()
                                    event.accepted = true
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰅖"
                            color: clrMa.containsMouse ? Colors.fg : a(Colors.fg, 0.3)
                            font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                            visible: searchInput.text.length > 0
                            Behavior on color { ColorAnimation { duration: 150 } }
                            MouseArea {
                                id: clrMa
                                anchors.fill: parent; anchors.margins: -6
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { searchInput.text = ""; searchInput.forceActiveFocus() }
                            }
                        }
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: colorDots

                        Item {
                            required property int index
                            required property var modelData
                            width: 22; height: 22

                            Rectangle {
                                anchors.centerIn: parent
                                width: colorFilter === parent.index ? 18 : cdMa.containsMouse ? 14 : 10
                                height: width; radius: width / 2
                                color: parent.modelData.color
                                opacity: colorFilter === parent.index ? 1 : cdMa.containsMouse ? 0.85 : 0.5
                                border.width: colorFilter === parent.index ? 2 : 0
                                border.color: Colors.fg

                                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: cdMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    colorFilter = colorFilter === parent.index ? -1 : parent.index
                                    filterWalls()
                                }
                            }
                        }
                    }
                }

                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 6

                    Text {
                        text: filtered.length + ""
                        color: a(Colors.fg, 0.35)
                        font { pixelSize: 11; family: "JetBrainsMono Nerd Font"; bold: true }
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        visible: filtered.length !== walls.length
                        text: "/ " + walls.length
                        color: a(Colors.fg, 0.2)
                        font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: 28; height: 28; radius: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: shuffleMa.containsMouse ? a(Colors.accent, 0.15) : "transparent"
                        visible: filtered.length > 1

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰒝"
                            color: shuffleMa.containsMouse ? Colors.accent : a(Colors.fg, 0.3)
                            font { pixelSize: 13; family: "JetBrainsMono Nerd Font" }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: shuffleMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pickRandom()
                        }
                    }
                }
            }

            Item {
                id: galleryArea
                anchors { top: topRow.bottom; topMargin: 14; left: parent.left; right: parent.right; bottom: parent.bottom }

                ListView {
                    id: sliceList
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    model: filtered
                    spacing: 6
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    currentIndex: selected
                    highlightMoveDuration: _skipInitialAnim ? 0 : 350
                    highlightMoveVelocity: -1
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: (width - expandedWidth) / 2
                    preferredHighlightEnd: (width + expandedWidth) / 2
                    highlight: Item {}
                    cacheBuffer: 1500

                    header: Item { width: Math.max(0, (sliceList.width - expandedWidth) / 2 - 3); height: 1 }
                    footer: Item { width: Math.max(0, (sliceList.width - expandedWidth) / 2 - 3); height: 1 }

                    MouseArea {
                        anchors.fill: parent
                        propagateComposedEvents: true
                        onWheel: function(wheel) {
                            if (wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0) {
                                if (selected > 0) selected--
                            } else {
                                if (selected < filtered.length - 1) selected++
                            }
                        }
                        onPressed: function(mouse) { mouse.accepted = false }
                        onReleased: function(mouse) { mouse.accepted = false }
                        onClicked: function(mouse) { mouse.accepted = false }
                    }

                    delegate: Item {
                        id: sliceItem
                        required property int index
                        required property var modelData
                        property bool isCurrent: index === selected
                        property bool isActive: modelData.name === currentWall
                        property bool isHovered: sliceMa.containsMouse
                        property bool isGif: modelData.name.toLowerCase().endsWith(".gif")
                        property real cardRadius: isCurrent ? 18 : 12

                        property bool fullLoaded: fullLoader.item ? fullLoader.item.status === Image.Ready : false
                        property bool gifLoaded: gifLoader.item ? gifLoader.item.status === Image.Ready : false

                        width: isCurrent ? expandedWidth : sliceWidth
                        height: sliceList.height

                        Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

                        Item {
                            id: sliceCard
                            anchors.fill: parent
                            anchors.topMargin: sliceItem.isCurrent ? 0 : 10
                            anchors.bottomMargin: sliceItem.isCurrent ? 0 : 10

                            Behavior on anchors.topMargin { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on anchors.bottomMargin { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                            Item {
                                id: wallContent
                                anchors.fill: parent
                                visible: false

                                Image {
                                    id: thumbImg
                                    anchors.fill: parent
                                    source: thumbVersion > 0
                                        ? "file://" + cachePath + "/" + sliceItem.modelData.name + ".thumb.jpg"
                                        : "file://" + wallDir + "/" + sliceItem.modelData.name
                                    onStatusChanged: {
                                        if (status === Image.Error)
                                            source = "file://" + wallDir + "/" + sliceItem.modelData.name
                                    }
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize.width: 400
                                    asynchronous: true
                                    cache: true
                                    visible: !sliceItem.fullLoaded && !sliceItem.gifLoaded
                                }

                                Loader {
                                    id: fullLoader
                                    anchors.fill: parent
                                    active: sliceItem.isCurrent && !sliceItem.isGif
                                    sourceComponent: Image {
                                        anchors.fill: parent
                                        source: "file://" + wallDir + "/" + sliceItem.modelData.name
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize.width: 1920
                                        asynchronous: true
                                        cache: true
                                    }
                                }

                                Loader {
                                    id: gifLoader
                                    anchors.fill: parent
                                    active: sliceItem.isCurrent && sliceItem.isGif
                                    sourceComponent: AnimatedImage {
                                        anchors.fill: parent
                                        source: "file://" + wallDir + "/" + sliceItem.modelData.name
                                        fillMode: Image.PreserveAspectCrop
                                        playing: sliceItem.isCurrent
                                        asynchronous: true
                                    }
                                }
                            }

                            Rectangle {
                                id: wallMask
                                anchors.fill: parent
                                radius: sliceItem.cardRadius
                                visible: false
                            }

                            OpacityMask {
                                anchors.fill: parent
                                source: wallContent
                                maskSource: wallMask
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: sliceItem.cardRadius
                                color: sliceItem.isCurrent ? "transparent"
                                     : sliceItem.isHovered ? a("#000", 0.15)
                                     : a("#000", 0.55)
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            Rectangle {
                                visible: sliceItem.isActive && !sliceItem.isCurrent
                                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 8 }
                                width: 18; height: 18; radius: 9
                                color: Colors.green
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰄬"; color: "#000"
                                    font { pixelSize: 9; family: "JetBrainsMono Nerd Font" }
                                }
                            }

                            Loader {
                                active: sliceItem.isCurrent
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 90

                                sourceComponent: Item {
                                    anchors.fill: parent

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: sliceItem.cardRadius
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 0.3; color: a("#000", 0.25) }
                                            GradientStop { position: 1.0; color: a("#000", 0.88) }
                                        }
                                    }

                                    Item {
                                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                        anchors { leftMargin: 20; rightMargin: 20; bottomMargin: 16 }
                                        height: 40

                                        Row {
                                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                            spacing: 10

                                            Rectangle {
                                                width: 12; height: 12; radius: 6
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: {
                                                    var cs = wallColors[sliceItem.modelData.name]
                                                    var rep = getRepresentativeColor(cs)
                                                    return rep.length > 3 ? rep : a("#fff", 0.3)
                                                }
                                                border.width: 1.5
                                                border.color: a("#fff", 0.3)
                                            }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 2

                                                Text {
                                                    text: prettyName(sliceItem.modelData.name)
                                                    color: "#fff"
                                                    font { pixelSize: 13; family: "JetBrainsMono Nerd Font"; bold: true }
                                                    width: Math.min(implicitWidth, expandedWidth - 220)
                                                    elide: Text.ElideRight
                                                }

                                                Row {
                                                    spacing: 8
                                                    Text {
                                                        text: {
                                                            var n = sliceItem.modelData.name
                                                            var dot = n.lastIndexOf(".")
                                                            return dot > 0 ? n.substring(dot + 1).toUpperCase() : ""
                                                        }
                                                        color: a("#fff", 0.35)
                                                        font { pixelSize: 9; family: "JetBrainsMono Nerd Font" }
                                                    }
                                                    Text {
                                                        visible: sliceItem.isGif
                                                        text: "GIF"
                                                        color: Colors.accent
                                                        font { pixelSize: 9; family: "JetBrainsMono Nerd Font"; bold: true }
                                                    }
                                                    Text {
                                                        visible: sliceItem.isActive
                                                        text: "current"
                                                        color: Colors.green
                                                        font { pixelSize: 9; family: "JetBrainsMono Nerd Font"; bold: true }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                            width: applyContent.width + 24
                                            height: 30; radius: 15
                                            color: sliceItem.isActive ? a(Colors.green, 0.15)
                                                 : applyBtnMa.containsMouse ? a(Colors.accent, 0.25) : a("#fff", 0.08)
                                            border.width: 1
                                            border.color: sliceItem.isActive ? a(Colors.green, 0.35)
                                                         : applyBtnMa.containsMouse ? a(Colors.accent, 0.35) : a("#fff", 0.08)

                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Behavior on border.color { ColorAnimation { duration: 150 } }

                                            Row {
                                                id: applyContent
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Text {
                                                    text: sliceItem.isActive ? "󰄬" : "󰸉"
                                                    color: sliceItem.isActive ? Colors.green : applyBtnMa.containsMouse ? Colors.accent : a("#fff", 0.6)
                                                    font { pixelSize: 13; family: "JetBrainsMono Nerd Font" }
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }

                                                Text {
                                                    text: sliceItem.isActive ? "Active" : "Apply"
                                                    color: sliceItem.isActive ? Colors.green : applyBtnMa.containsMouse ? Colors.accent : a("#fff", 0.6)
                                                    font { pixelSize: 10; family: "JetBrainsMono Nerd Font"; bold: true }
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                            }

                                            MouseArea {
                                                id: applyBtnMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (!sliceItem.isActive) applyWallpaper(sliceItem.modelData)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: sliceItem.cardRadius
                                color: "transparent"
                                border.width: sliceItem.isCurrent ? 2 : sliceItem.isActive ? 1.5 : sliceItem.isHovered ? 1 : 0
                                border.color: sliceItem.isCurrent ? Colors.accent
                                             : sliceItem.isActive ? Colors.green
                                             : a("#fff", 0.3)
                                Behavior on border.width { NumberAnimation { duration: 200 } }
                                Behavior on border.color { ColorAnimation { duration: 200 } }
                            }
                        }

                        MouseArea {
                            id: sliceMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (sliceItem.isCurrent) applyWallpaper(sliceItem.modelData)
                                else selected = sliceItem.index
                            }
                        }
                    }
                }

                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: 50
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: a(Colors.bg, UIState.transparencyEnabled ? 0.92 : 1) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Rectangle {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 50
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: a(Colors.bg, UIState.transparencyEnabled ? 0.92 : 1) }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    visible: filtered.length === 0

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: walls.length === 0 ? "󰔟" : "󰈭"
                        color: a(Colors.fg, 0.12)
                        font { pixelSize: 40; family: "JetBrainsMono Nerd Font" }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: walls.length === 0 ? "Scanning wallpapers..." : "No wallpapers match"
                        color: a(Colors.fg, 0.2)
                        font { pixelSize: 12; family: "JetBrainsMono Nerd Font" }
                    }

                    Text {
                        visible: colorFilter >= 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Clear filter"
                        color: cfMa.containsMouse ? Colors.accent : a(Colors.accent, 0.5)
                        font { pixelSize: 11; family: "JetBrainsMono Nerd Font" }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        MouseArea {
                            id: cfMa
                            anchors.fill: parent; anchors.margins: -8
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { colorFilter = -1; filterWalls() }
                        }
                    }
                }
            }
        }
    }
}