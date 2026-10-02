pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "lib/launch.mjs" as Run

// Starts apps from the bar's menus the way keys and the launcher do,
// through `quickspace launch` (SPEC.md §5.4), and says so in the log when
// one fails rather than leaving a click that seemed to do nothing.
Singleton {
    id: root

    function launch(command) {
        const run = runner.createObject(root, { command: ["quickspace", "launch", "--"].concat(command) });
        run.running = true;
    }

    Component {
        id: runner

        Process {
            id: run

            // Its signals, through shell/lib/launch.mjs, which decides when
            // the run is done and what it has to say.
            property var state: Run.initial()

            function handle(event) {
                if (state.done) {
                    return;
                }
                state = Run.step(state, event, command);
                if (state.report?.level === "warn") {
                    console.warn(state.report.message);
                } else if (state.report?.level === "log") {
                    console.log(state.report.message);
                }
                if (state.done) {
                    destroy();
                }
            }

            stderr: StdioCollector {
                onStreamFinished: run.handle({ type: "stderr", text: text })
            }
            onStarted: handle({ type: "started" })
            onRunningChanged: {
                if (!running) {
                    handle({ type: "stopped" });
                }
            }
            onExited: (exitCode, status) => handle({ type: "exited", code: exitCode })
        }
    }
}
