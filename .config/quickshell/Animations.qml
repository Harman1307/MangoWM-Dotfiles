pragma Singleton
import QtQuick

QtObject {
    readonly property int instant: 0
    readonly property int snap: 110
    readonly property int fast: 200
    readonly property int medium: 320
    readonly property int slow: 420
    readonly property int xslow: 600

    readonly property real springPower: 1.8

    readonly property int enterDuration: 340
    readonly property int exitDuration: 200

    readonly property real enterScale: 0.93
    readonly property real hoverScale: 1.04
}
