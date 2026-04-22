pragma Singleton
import QtQuick

QtObject {
    readonly property int instant: 0
    readonly property int snap: 140
    readonly property int fast: 220
    readonly property int medium: 320
    readonly property int slow: 380
    readonly property int xslow: 540

    readonly property real springPower: 1.5

    readonly property int enterDuration: 350
    readonly property int exitDuration: 220

    readonly property real enterScale: 0.96
    readonly property real hoverScale: 1.03
}