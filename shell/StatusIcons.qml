import QtQuick
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import "lib/status.mjs" as Status

// The status icons before the clocks (SPEC.md §7.4). So far: volume, which
// scrolls by 5%, and battery, red below 15%. Their popovers, and the rest of
// the icons and the tray, come later; TODO.md lists them.
Row {
    id: root

    spacing: 10

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var battery: UPower.displayDevice

    // Volume and mute are only live on a bound node.
    PwObjectTracker {
        objects: [root.sink]
    }

    SymbolicIcon {
        id: volume

        anchors.verticalCenter: parent.verticalCenter
        visible: root.sink !== null
        name: Status.volumeIcon({
            muted: root.sink?.audio?.muted ?? true,
            volume: root.sink?.audio?.volume,
        })

        property real wheel: 0

        WheelHandler {
            onWheel: event => {
                const audio = root.sink?.audio;
                if (!audio) {
                    return;
                }
                volume.wheel += event.angleDelta.y;
                const notches = Math.trunc(volume.wheel / 120);
                if (notches === 0) {
                    return;
                }
                volume.wheel -= notches * 120;
                audio.volume = Status.scrolledVolume(audio.volume, notches);
            }
        }
    }

    Row {
        id: battery

        readonly property var view: Status.batteryView({
            present: root.battery?.isPresent ?? false,
            percentage: root.battery?.percentage,
            state: root.battery?.state,
        })
        readonly property color ink: view.low ? Theme.danger : Theme.fg

        anchors.verticalCenter: parent.verticalCenter
        visible: view.visible
        spacing: 3

        SymbolicIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: battery.view.icon || "battery-missing-symbolic"
            color: battery.ink
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: battery.view.text
            color: battery.ink
            font.family: Theme.font
            font.pixelSize: 12.5
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
        }
    }
}
