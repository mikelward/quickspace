pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "lib/launch.mjs" as Run
import "lib/workspaces.mjs" as Ws

// The bar's attention marks (SPEC.md §14.4), one set for every monitor's
// bar, kept as events arrive (shell/lib/workspaces.mjs):
//   - The focus guard's: a window it kept from focus marks its workspace
//     until the window is focused or closes. Whenever the guard's state may
//     have been rebuilt, the shell drops these and asks it to announce what
//     still waits: when the shell starts (it may have restarted with
//     windows waiting) and after a Hyprland config reload (which runs
//     focus.lua afresh).
//   - Notifications': NotificationData reports each one that arrives or is
//     updated, and each that closes, while the shell is the notification
//     server.
Singleton {
    id: root

    property var marks: Ws.NO_MARKS

    // What a notification's mark is judged against: the windows, and the
    // workspaces on screen when it arrives.
    readonly property var windows: Hyprland.toplevels.values.map(t => ({
        address: Ws.normalizeAddress(t.address),
        workspace: t.workspace ? t.workspace.id : null,
        app: t.lastIpcObject?.class || t.wayland?.appId || "",
    }))
    readonly property var visible: Ws.visibleWorkspaces(Hyprland.monitors.values.map(m => ({
        workspace: m.activeWorkspace ? m.activeWorkspace.id : null,
        special: m.lastIpcObject?.specialWorkspace?.id ?? 0,
    })))

    // A notification arrived, or was updated in place: it marks its app's
    // windows that aren't on screen now. Each update adds to what it marked.
    // `replaces` is the ID of one it took the place of, whose marks it
    // takes over, or undefined.
    function notified(id, app, replaces) {
        if (app) {
            root.marks = Ws.updateMarks(root.marks, {
                type: "notified",
                id: id,
                replaces: replaces,
                app: app,
                windows: root.windows,
                visible: root.visible
            });
        }
    }

    // A notification closed; whether that clears its marks depends on why
    // (Notes.clearsMarks).
    function dismissed(id) {
        root.marks = Ws.updateMarks(root.marks, { type: "dismissed", id: id });
    }

    // Asks the guard to announce every waiting window again. Each ask is
    // its own process with its own bookkeeping, so one overlapping another
    // (a reload while the startup replay still runs) can't finish the
    // other's; two replays only announce the same windows twice.
    function resync() {
        replay.createObject(root).running = true;
    }

    Component.onCompleted: resync()

    Component {
        id: replay

        Process {
            id: run

            // quickspace_focus.announce_waiting() (hypr/quickspace/focus.lua)
            // re-sends quickspace-attention for each waiting window, which
            // the Connections below turn into marks like any other.
            property var state: Run.initial()
            // Its reply is on stdout, which ends apart from stderr: the run
            // counts stderr as in only once both are.
            property string reply: ""
            property bool replyRead: false
            property string errors: ""
            property bool errorsRead: false

            function streamed() {
                if (replyRead && errorsRead) {
                    handle({ type: "stderr", text: errors });
                }
            }

            function handle(event) {
                if (state.done) {
                    return;
                }
                state = Run.step(state, event, command);
                if (!state.done) {
                    return;
                }
                if (!state.started) {
                    console.warn(state.report.message);
                } else if (state.code !== 0 || reply.trim() !== "ok") {
                    // Outside a quickspace session the guard isn't loaded,
                    // and there's nothing to replay.
                    console.warn(`quickspace: couldn't replay the focus guard's waiting windows: ${(reply + state.errors).trim()}`);
                } else if (state.report?.level === "log") {
                    // It worked, but said something on the way.
                    console.log(state.report.message);
                }
                destroy();
            }

            command: ["hyprctl", "eval", "quickspace_focus.announce_waiting()"]
            stdout: StdioCollector {
                onStreamFinished: {
                    run.reply = text;
                    run.replyRead = true;
                    run.streamed();
                }
            }
            stderr: StdioCollector {
                onStreamFinished: {
                    run.errors = text;
                    run.errorsRead = true;
                    run.streamed();
                }
            }
            onStarted: handle({ type: "started" })
            onRunningChanged: {
                if (!running) {
                    handle({ type: "stopped" });
                }
            }
            onExited: (code, status) => handle({ type: "exited", code: code })
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            let mark = Ws.markEvent(event.name, event.data);
            if (mark?.type === "urgent") {
                mark = Ws.activatedEvent(mark.address, root.windows);
            }
            if (mark !== null) {
                root.marks = Ws.updateMarks(root.marks, mark);
            }
            if (mark?.type === "guardReset") {
                root.resync();
            }
        }
    }
}
