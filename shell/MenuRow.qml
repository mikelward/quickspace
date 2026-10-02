import QtQuick

// One row of a bar menu: a symbolic icon and a label, highlighted on hover.
Item {
    id: root

    property string icon
    property string label
    signal clicked

    implicitHeight: 32
    // A disabled row takes no clicks (its handlers follow `enabled`).
    opacity: enabled ? 1 : 0.5

    Rectangle {
        anchors.fill: parent
        radius: 7
        color: Theme.surface2
        visible: hover.hovered
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        SymbolicIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            color: Theme.fg
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 13
        }
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        onTapped: root.clicked()
    }
}
