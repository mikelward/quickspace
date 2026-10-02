import QtQuick

// One row of a bar menu: a symbolic icon and a label, highlighted on hover.
Item {
    id: root

    property string icon
    property string label
    // A chosen option among rows, such as the current power profile.
    property bool selected: false
    signal clicked

    implicitHeight: 32
    // A disabled row takes no clicks (its handlers follow `enabled`).
    opacity: enabled ? 1 : 0.5

    Rectangle {
        anchors.fill: parent
        radius: 7
        color: Theme.surface2
        visible: hover.hovered || root.selected
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

    SymbolicIcon {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: root.selected
        name: "object-select-symbolic"
        color: Theme.accent
    }

    HoverHandler {
        id: hover
    }

    TapHandler {
        onTapped: root.clicked()
    }
}
