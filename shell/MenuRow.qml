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

    SymbolicIcon {
        id: lead

        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        color: Theme.fg
    }

    // Between the icon and the check mark, cut short if it's too long.
    Text {
        anchors.left: lead.right
        anchors.leftMargin: 10
        anchors.right: check.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        // Labels can come from other programs (device names): never markup.
        textFormat: Text.PlainText
        text: root.label
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: 13
    }

    SymbolicIcon {
        id: check

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
