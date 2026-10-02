import QtQuick
import Quickshell
import Quickshell.Hyprland

// quickspace's shell (SPEC.md §3.2): for now, the bar, the OSD and the
// notification popups (opt-in; see NotificationData.qml) on every monitor.
ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    Variants {
        model: Quickshell.screens

        Osd {}
    }

    Variants {
        model: Quickshell.screens

        NotificationPopups {}
    }

    // A toplevel's class and fullscreen state come from Hyprland's client
    // list, which Quickshell reads on request; ask again when they change.
    Connections {
        target: Hyprland

        // Windows that were open before the shell started need it too.
        Component.onCompleted: Hyprland.refreshToplevels()

        function onRawEvent(event) {
            if (["openwindow", "closewindow", "movewindowv2", "fullscreen", "changefloatingmode"].includes(event.name)) {
                Hyprland.refreshToplevels();
            }
        }
    }
}
