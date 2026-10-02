import QtQuick
import Quickshell
import Quickshell.Hyprland

// One bar per monitor (SPEC.md §7.1): a plain rectangle flush with the top
// edge and both sides, its exclusive zone keeping tiling below it.
PanelWindow {
    id: bar

    required property var modelData
    readonly property var monitor: Hyprland.monitorFor(bar.screen)

    screen: modelData
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: Theme.barBg

    Workspaces {
        id: workspaces

        anchors.left: parent.left
        anchors.leftMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        monitorName: bar.monitor?.name ?? ""
    }

    LayoutSymbol {
        id: layoutSymbol

        anchors.left: workspaces.right
        anchors.leftMargin: 7
        anchors.verticalCenter: parent.verticalCenter
        monitor: bar.monitor
    }

    // Centered on the bar, and no wider than the room between the left and
    // right groups allows on both sides, so it stays centered.
    WindowTitle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(implicitWidth, maxWidth, 2 * Math.min(bar.width / 2 - layoutSymbol.x - layoutSymbol.width, tray.x - bar.width / 2) - 32))
        monitor: bar.monitor
    }

    Tray {
        id: tray

        anchors.right: statusIcons.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
    }

    StatusIcons {
        id: statusIcons

        anchors.right: clocks.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
    }

    Clocks {
        id: clocks

        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
    }
}
