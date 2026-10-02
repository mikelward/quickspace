import QtQuick
import Quickshell.Hyprland
import "lib/title.mjs" as Title
import "lib/workspaces.mjs" as Ws

// The window title in the middle of this monitor's bar (SPEC.md §7.1):
// the focused window's, or this monitor's workspace's last focused one,
// from shell/lib/title.mjs.
Text {
    id: root

    // This bar's HyprlandMonitor.
    required property var monitor

    // About Title.MAX_TITLE characters wide, as waybar's max-length had
    // it. Past that, and past the room Bar.qml gives it, the text elides,
    // which Qt does only between whole characters.
    readonly property real maxWidth: metrics.averageCharacterWidth * Title.MAX_TITLE

    FontMetrics {
        id: metrics

        font: root.font
    }

    // The workspace this monitor shows: an open special workspace covers
    // the regular one. Quickshell has no property for it, so it comes from
    // Hyprland's monitor list, which shell.qml asks for again as one opens
    // or closes.
    readonly property int specialId: monitor?.lastIpcObject?.specialWorkspace?.id ?? 0
    readonly property var workspace: {
        const id = Title.shownWorkspace(monitor?.activeWorkspace?.id ?? null, root.specialId);
        return Hyprland.workspaces.values.find(w => w.id === id) ?? null;
    }
    // Nothing has focus after focus moves to an empty workspace, which
    // Hyprland.activeToplevel doesn't show (Title.hasFocus).
    property bool focusGone: false
    readonly property var active: root.focusGone ? null : Hyprland.activeToplevel

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "activewindowv2") {
                root.focusGone = !Title.hasFocus(event.data);
            }
        }
    }

    text: Title.barTitle({
        monitor: root.monitor?.name ?? null,
        workspace: root.workspace?.id ?? null,
        active: root.active ? {
            monitor: root.active.monitor?.name ?? null,
            title: root.active.title
        } : null,
        // Hyprland's workspace list says which window was last focused on
        // each; shell.qml asks for it again as focus moves.
        lastWindow: root.workspace?.lastIpcObject?.lastwindow ?? "",
        windows: Hyprland.toplevels.values.map(t => ({
            address: Ws.normalizeAddress(t.address),
            workspace: t.workspace?.id ?? null,
            title: t.title
        }))
    })
    // Titles come from apps: never markup.
    textFormat: Text.PlainText
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
    color: Theme.fg
    font.family: Theme.font
    font.pixelSize: 13
}
