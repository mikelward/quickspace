pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "lib/appearance.mjs" as Appearance

// The palette and sizes from docs/mocks/common.css, light and dark (SPEC.md
// §15). Until the shell owns the light/dark schedule, it follows the
// desktop's color scheme, which conf's theme daemon flips; the palette
// changes in place.
Singleton {
    id: root

    // Dark until the color scheme is read, as the shell was before this.
    property bool dark: true

    readonly property int barHeight: 34
    readonly property int chipHeight: 26
    readonly property int chipRadius: 7

    readonly property color barBg: dark ? Qt.rgba(22 / 255, 22 / 255, 26 / 255, 0.96) : Qt.rgba(250 / 255, 250 / 255, 251 / 255, 0.97)
    readonly property color fg: dark ? "#ededf1" : "#1f1f24"
    readonly property color fgDim: dark ? "#9a9aa6" : "#62626e"
    readonly property color fgFaint: dark ? "#5d5d68" : "#a8a8b3"
    readonly property color surface: dark ? "#2a2a2f" : "#ffffff"
    readonly property color surface2: dark ? "#38383e" : "#ececf0"
    readonly property color accent: dark ? "#78aeed" : "#1c71d8"
    readonly property color accentBg: "#3584e4"
    readonly property color accentFg: "#ffffff"
    readonly property color urgent: dark ? "#f8e45c" : "#8a5d00"
    readonly property color urgentBg: dark ? Qt.rgba(246 / 255, 211 / 255, 45 / 255, 0.20) : Qt.rgba(229 / 255, 165 / 255, 10 / 255, 0.26)
    readonly property color urgentRing: dark ? "#f6d32d" : "#e5a50a"
    readonly property color danger: dark ? "#ff7b63" : "#c01c28"
    // The Sharing pill's fill, with white on it (docs/mocks/common.css).
    readonly property color dangerBg: dark ? "#c01c28" : "#e01b24"
    readonly property color warn: dark ? "#ffa348" : "#c64600"
    // The clocks popover's day strip: night, day, and working hours.
    readonly property color stripNight: dark ? "#1a1d2e" : "#dfe3ee"
    readonly property color stripDay: dark ? "#3a4870" : "#b4c4e8"

    readonly property string font: "Inter"
    readonly property string monoFont: "Ubuntu Mono"

    // Whether the monitor has reported a change, which is newer than
    // anything the startup read can say.
    property bool changed: false

    function heard(line, fromMonitor) {
        const next = Appearance.heardScheme({ dark: root.dark, changed: root.changed }, line, fromMonitor);
        root.dark = next.dark;
        root.changed = next.changed;
    }

    // The monitor starts first, and heardScheme keeps the startup read from
    // undoing a change it reports. gsettings monitor has no "ready" signal,
    // though, so a flip in the instant before it subscribes is missed until
    // the next one; TODO.md has the decision.
    Process {
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"]
        running: true
        stdout: SplitParser {
            onRead: data => root.heard(data, true)
        }
        onExited: (code, status) => {
            console.warn(`tide: gsettings monitor exited ${code}; the bar no longer follows light and dark`);
        }
    }

    Process {
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.heard(text, false)
        }
        onExited: (code, status) => {
            if (code !== 0) {
                console.warn(`tide: gsettings get color-scheme exited ${code}; the bar stays ${root.dark ? "dark" : "light"}`);
            }
        }
    }
}
