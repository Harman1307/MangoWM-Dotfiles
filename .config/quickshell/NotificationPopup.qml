import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: popup

    anchors { top: true; right: true }
    margins { top: 46; right: 12 }
    implicitWidth: 300
    implicitHeight: toastCol.height + 16
    color: "transparent"
    visible: toastModel.count > 0 && UIState.activeDropdown !== "dashboard"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "notifications"

    function a(c, o) { return Qt.rgba(c.r, c.g, c.b, o) }

    ListModel { id: toastModel }

    function addToast(id, app, title, body) {
        if (UIState.dndEnabled) return
        if (UIState.activeDropdown === "dashboard") return
        while (toastModel.count >= 3)
            toastModel.remove(0)
        var dur = Math.max(5000, Math.min(30000, body.length * 80))
        toastModel.append({ nid: id, app: app, title: title, body: body, duration: dur })
    }

    function removeToast(id) {
        for (var i = 0; i < toastModel.count; i++) {
            if (toastModel.get(i).nid === id) {
                toastModel.remove(i)
                return
            }
        }
    }

    Connections {
        target: UIState
        function onNotificationReceived(nid, app, title, body) {
            addToast(nid, app, title, body)
        }
    }

    Column {
        id: toastCol
        anchors { top: parent.top; left: parent.left; right: parent.right }
        anchors.topMargin: 4
        spacing: 10

        move: Transition {
            NumberAnimation { properties: "y"; duration: 300; easing.type: Easing.OutExpo }
        }

        Repeater {
            model: toastModel

            Item {
                id: wrapper
                width: toastCol.width
                height: card.height + 4
                opacity: 0
                transformOrigin: Item.TopRight
                property bool dying: false
                property real cardX: 0
                property real cardRotation: 0
                property real cardScale: 0.8
                property real progress: 1.0
                property bool hovered: cardMa.containsMouse || dismissMa.containsMouse

                onHoveredChanged: {
                    if (dying) return
                    if (hovered) {
                        autoTimer.stop()
                        progressTimer.stop()
                    } else {
                        autoTimer.restart()
                        progressTimer.restart()
                    }
                }

                Component.onCompleted: enterAnim.start()

                ParallelAnimation {
                    id: enterAnim
                    NumberAnimation { target: wrapper; property: "opacity"; to: 1; duration: 300; easing.type: Easing.OutCubic }
                    NumberAnimation { target: wrapper; property: "cardScale"; to: 1; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    NumberAnimation { target: wrapper; property: "cardX"; from: 30; to: 0; duration: 400; easing.type: Easing.OutExpo }
                    NumberAnimation { target: wrapper; property: "cardRotation"; from: 3; to: 0; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 3 }
                }

                function dismiss() {
                    if (dying) return
                    dying = true
                    autoTimer.stop()
                    progressTimer.stop()
                    exitAnim.start()
                }

                ParallelAnimation {
                    id: exitAnim
                    NumberAnimation { target: wrapper; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
                    NumberAnimation { target: wrapper; property: "cardScale"; to: 0.9; duration: 180; easing.type: Easing.InCubic }
                    NumberAnimation { target: wrapper; property: "cardX"; to: 60; duration: 200; easing.type: Easing.InQuad }
                    onFinished: popup.removeToast(model.nid)
                }

                Timer {
                    id: autoTimer
                    interval: model.duration
                    running: true
                    onTriggered: wrapper.dismiss()
                }

                Timer {
                    id: progressTimer
                    interval: 50
                    running: true
                    repeat: true
                    onTriggered: progress = Math.max(0, progress - (50 / model.duration))
                }

                Rectangle {
                    id: card
                    x: wrapper.cardX
                    rotation: wrapper.cardRotation
                    scale: wrapper.cardScale
                    transformOrigin: Item.TopRight
                    width: parent.width
                    height: content.height + 46
                    radius: 14
                    color: a(Colors.bg, UIState.transparencyEnabled ? (wrapper.hovered ? 0.95 : 0.88) : 1)
                    border.width: wrapper.hovered ? 1.5 : 1
                    border.color: a(Colors.accent, wrapper.hovered ? 0.45 : 0.12)

                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    Behavior on border.width { NumberAnimation { duration: 150 } }

                    Column {
                        id: content
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors { leftMargin: 16; rightMargin: 16; topMargin: 14 }
                        spacing: 6

                        Row {
                            spacing: 6

                            Rectangle {
                                width: 6; height: 6; radius: 3
                                color: Colors.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: model.app.toUpperCase()
                                color: a(Colors.accent, 0.6)
                                font { pixelSize: 8; family: "JetBrainsMono Nerd Font"; bold: true; letterSpacing: 1.2 }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Text {
                            text: model.title
                            color: Colors.fg
                            font { pixelSize: 11; family: "JetBrainsMono Nerd Font"; bold: true }
                            width: parent.width
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: model.body !== ""
                            text: model.body
                            color: a(Colors.fg, 0.45)
                            font { pixelSize: 10; family: "JetBrainsMono Nerd Font" }
                            width: parent.width
                            wrapMode: Text.WordWrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            lineHeight: 1.3
                        }
                    }

                    MouseArea {
                        id: cardMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: wrapper.dismiss()
                    }

                    Text {
                        anchors { right: parent.right; top: parent.top; rightMargin: 12; topMargin: 12 }
                        text: "󰅖"
                        color: dismissMa.containsMouse ? Colors.red : a(Colors.fg, 0.25)
                        font { pixelSize: 11; family: "JetBrainsMono Nerd Font" }
                        opacity: wrapper.hovered ? 1 : 0

                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        MouseArea {
                            id: dismissMa
                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wrapper.dismiss()
                        }
                    }

                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        anchors { leftMargin: 14; rightMargin: 14; bottomMargin: 10 }
                        height: 2
                        radius: 1
                        color: a(Colors.fg, 0.06)

                        Rectangle {
                            width: parent.width * wrapper.progress
                            height: parent.height
                            radius: 1
                            color: a(Colors.accent, wrapper.hovered ? 0.7 : 0.5)

                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }
                }
            }
        }
    }
}