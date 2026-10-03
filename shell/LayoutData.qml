pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "lib/layouts.mjs" as Layouts

// Each workspace's layout mode as hypr/tide/layout.lua announces it
// (SPEC.md §6.1). A workspace not heard from yet isn't in `modes`; the bar
// shows the layout's default for it.
Singleton {
    id: root

    // Workspace ID to mode.
    property var modes: ({})

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                // Assumes a reload runs layout.lua afresh, starting every
                // workspace again in its default mode; TODO.md has the
                // live check.
                root.modes = {};
                return;
            }
            if (event.name !== "custom") {
                return;
            }
            const heard = Layouts.parseAnnouncement(event.data);
            if (heard) {
                root.modes = Object.assign({}, root.modes, { [heard.workspace]: heard.mode });
            }
        }
    }
}
