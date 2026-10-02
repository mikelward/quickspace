pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "lib/launch.mjs" as Run
import "lib/workspaces.mjs" as Ws

// The bar's attention marks (SPEC.md §14.4), one set for every monitor's
// bar, kept as Hyprland's events arrive (shell/lib/workspaces.mjs). So far
// from the focus guard: a window it kept from focus marks its workspace
// until the window is focused or closes. Whenever the guard's state may
// have been rebuilt, the shell drops its marks and asks it to announce
// what still waits: when the shell starts (it may have restarted with
// windows waiting) and after a Hyprland config reload (which runs
// focus.lua afresh). Notifications' marks come with the shell's
// notification server.
Singleton {
    id: root

    property var marks: Ws.NO_MARKS

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
            const mark = Ws.markEvent(event.name, event.data);
            if (mark !== null) {
                root.marks = Ws.updateMarks(root.marks, mark);
            }
            if (mark?.type === "guardReset") {
                root.resync();
            }
        }
    }
}
