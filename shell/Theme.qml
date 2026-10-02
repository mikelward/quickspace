pragma Singleton

import QtQuick
import Quickshell

// The palette and sizes from docs/mocks/common.css, dark only until the
// light/dark switch (SPEC.md §15) lands.
Singleton {
    readonly property int barHeight: 34
    readonly property int chipHeight: 26
    readonly property int chipRadius: 7

    readonly property color barBg: Qt.rgba(22 / 255, 22 / 255, 26 / 255, 0.96)
    readonly property color fg: "#ededf1"
    readonly property color fgDim: "#9a9aa6"
    readonly property color fgFaint: "#5d5d68"
    readonly property color surface: "#2a2a2f"
    readonly property color accent: "#78aeed"
    readonly property color accentBg: "#3584e4"
    readonly property color accentFg: "#ffffff"
    readonly property color urgent: "#f8e45c"
    readonly property color urgentBg: Qt.rgba(246 / 255, 211 / 255, 45 / 255, 0.20)
    readonly property color urgentRing: "#f6d32d"

    readonly property string font: "Inter"
}
