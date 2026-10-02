import QtQuick
import "lib/audio.mjs" as Audio

// A PipeWire node's mute button, level slider and percentage, for the
// volume popover. The node must be bound (PwObjectTracker) for its audio
// to be live.
Item {
    id: root

    property var node: null
    readonly property var audio: node?.audio ?? null
    readonly property bool muted: audio?.muted ?? true
    readonly property real volume: audio?.volume ?? 0

    implicitHeight: 28

    SymbolicIcon {
        id: mute

        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        name: root.muted || root.volume <= 0 ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"
        color: root.muted ? Theme.fgDim : Theme.fg

        TapHandler {
            onTapped: {
                if (root.audio) {
                    root.audio.muted = !root.audio.muted;
                }
            }
        }
    }

    Rectangle {
        id: track

        anchors.left: mute.right
        anchors.leftMargin: 10
        anchors.right: level.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        radius: 3
        color: Theme.surface2

        Rectangle {
            width: track.width * Math.min(1, root.volume)
            height: parent.height
            radius: 3
            color: root.muted ? Theme.fgFaint : Theme.accent
        }

        // Taller than the track, so it's easy to grab.
        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -8
            anchors.bottomMargin: -8
            enabled: root.audio !== null

            function set(x) {
                root.audio.volume = Audio.sliderVolume(x / track.width);
            }

            onPressed: mouse => set(mouse.x)
            onPositionChanged: mouse => set(mouse.x)
        }
    }

    Text {
        id: level

        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        horizontalAlignment: Text.AlignRight
        text: Audio.volumeText(root.volume, root.muted)
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: 12
        font.features: ({ "tnum": 1 })
    }
}
