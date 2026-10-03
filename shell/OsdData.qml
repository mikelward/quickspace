pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "lib/osd.mjs" as Osd

// What the OSD shows (SPEC.md §9): the default output's volume and mute,
// and the default input's mute, each as it changes, from whatever changed
// it (keys, the bar, another app). One for every monitor's OSD. The
// backlight's level shows only when `tide brightness` reports it,
// so hypridle dimming the screen doesn't flash it.
Singleton {
    id: root

    // The pill to draw (shell/lib/osd.mjs), and whether it's up.
    property var pill: null
    property bool showing: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    // The last look at each, to tell a change from a first look.
    property var lastSink: null
    property var lastSource: null

    function look() {
        const sink = Osd.snapshot(root.sink, root.sink?.audio);
        if (Osd.changed(root.lastSink, sink)) {
            show(Osd.volumePill(sink));
        }
        root.lastSink = sink;
        const source = Osd.snapshot(root.source, root.source?.audio);
        if (Osd.muteChanged(root.lastSource, source)) {
            show(Osd.micPill(source));
        }
        root.lastSource = source;
    }

    function show(pill) {
        root.pill = pill;
        root.showing = true;
        hide.restart();
    }

    // `qs -c tide ipc call osd brightness PERCENT`, from `tide
    // brightness` after it changed the backlight.
    IpcHandler {
        target: "osd"

        function brightness(percent: int): void {
            root.show(Osd.brightnessPill(percent));
        }
    }

    // Levels and mute are only live on a bound node.
    PwObjectTracker {
        objects: [root.sink, root.source].filter(n => n)
    }

    Timer {
        id: hide

        interval: Osd.SHOWN_MS
        onTriggered: root.showing = false
    }

    // A switch of default device, or a node becoming ready, is a new first
    // look, not a change.
    onSinkChanged: look()
    onSourceChanged: look()

    Connections {
        target: root.sink

        function onReadyChanged() {
            root.look();
        }
    }

    Connections {
        target: root.source

        function onReadyChanged() {
            root.look();
        }
    }

    Connections {
        target: root.sink?.audio ?? null

        function onVolumesChanged() {
            root.look();
        }
        function onMutedChanged() {
            root.look();
        }
    }

    Connections {
        target: root.source?.audio ?? null

        function onMutedChanged() {
            root.look();
        }
    }
}
