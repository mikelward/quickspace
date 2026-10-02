import QtQuick
import Quickshell.Hyprland
import "lib/dispatch.mjs" as Dispatch
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
                if (Title.focusReached(root.maximizing, event.data)) {
                    root.maximizing = null;
                    giveUp.stop();
                    Hyprland.dispatch(Dispatch.toggleMaximize(Hyprland.usingLua));
                }
            }
        }
    }

    // The window the title stands for, {address, title}, or null.
    readonly property var window: Title.barWindow({
        monitor: root.monitor?.name ?? null,
        workspace: root.workspace?.id ?? null,
        active: root.active ? {
            monitor: root.active.monitor?.name ?? null,
            address: root.active.address,
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

    text: root.window?.title ?? ""

    // Double-clicking it toggles maximize on that window, like a title
    // bar (SPEC.md §7.1). The focused window is maximized at once. Another
    // is focused first, and maximized only when Hyprland says it has focus
    // (Title.focusReached): each dispatch goes on its own socket, so their
    // order isn't kept. If focus doesn't get there in a second (the window
    // went, or the focus guard held it), nothing is maximized.
    property var maximizing: null

    Timer {
        id: giveUp

        interval: 1000
        onTriggered: root.maximizing = null
    }

    TapHandler {
        onDoubleTapped: {
            const address = root.window?.address;
            if (!address) {
                return;
            }
            if (Title.focusReached(address, root.active?.address)) {
                Hyprland.dispatch(Dispatch.toggleMaximize(Hyprland.usingLua));
                return;
            }
            root.maximizing = address;
            giveUp.restart();
            Hyprland.dispatch(Dispatch.focusWindow(address, Hyprland.usingLua));
        }
    }
    // Titles come from apps: never markup.
    textFormat: Text.PlainText
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
    color: Theme.fg
    font.family: Theme.font
    font.pixelSize: 13
}
