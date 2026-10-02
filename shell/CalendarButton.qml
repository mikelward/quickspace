import QtQuick

// A chevron that steps the clocks popover's calendar a month.
Item {
    id: root

    property string icon
    signal clicked

    implicitWidth: 22
    implicitHeight: 22

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Theme.surface2
        visible: hover.hovered
    }

    SymbolicIcon {
        anchors.centerIn: parent
        name: root.icon
        color: Theme.fgDim
        width: 16
        height: 16
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        onTapped: root.clicked()
    }
}
