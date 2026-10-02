import QtQuick
import Quickshell
import Quickshell.Hyprland

// One bar per monitor (SPEC.md §7.1): a plain rectangle flush with the top
// edge and both sides, its exclusive zone keeping tiling below it.
PanelWindow {
    id: bar

    required property var modelData

    screen: modelData
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: Theme.barBg

    Workspaces {
        anchors.left: parent.left
        anchors.leftMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        monitorName: Hyprland.monitorFor(bar.screen)?.name ?? ""
    }

    Clocks {
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
    }
}
