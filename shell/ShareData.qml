pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "lib/share.mjs" as Share

// Whether a screen share is live (SPEC.md §12): an xdph screencast stream
// with something consuming it, from PipeWire rather than Hyprland's
// screencast>> event, which fires for any screencopy. While one is, popups
// are held (§9), and the notification center counts them.
Singleton {
    id: root

    // A link group's state is only valid while it's bound, so the links out
    // of share nodes are.
    readonly property var links: Share.shareLinks(Pipewire.linkGroups.values)

    PwObjectTracker {
        objects: root.links
    }

    readonly property var shares: Share.liveShares(Pipewire.nodes.values, root.links, PwLinkState.Active)
    readonly property bool holdingPopups: Share.holdsPopups(root.shares)
    // Popups held during the current or last share, for the center's
    // banner. A new share starts the count again, and so does seeing the
    // banner after the share has ended.
    property int held: 0

    onHoldingPopupsChanged: {
        if (root.holdingPopups) {
            root.held = 0;
        }
    }

    function counted(n) {
        root.held += n;
    }

    function seen() {
        if (!root.holdingPopups) {
            root.held = 0;
        }
    }
}
