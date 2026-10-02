import QtQuick
import Quickshell
import Quickshell.Io
import "lib/session.mjs" as Session

// The session menu (SPEC.md §7.4): lock, log out, suspend, restart and
// shut down, hanging from the session icon. A power action that something
// inhibits asks first, naming what's in the way, and goes ahead only on
// "Anyway".
PopupWindow {
    id: root

    required property Item icon

    // The action being run, and once systemctl says it's blocked, why.
    property string action: ""
    property var blocked: []
    // A run's exit code and stderr arrive separately; act once both have.
    property int exitCode: -1
    property string errors: ""
    property bool errorsRead: false

    function toggle() {
        blocked = [];
        visible = !visible;
    }

    function run(id, force) {
        // One at a time, so a result always belongs to the action shown.
        if (runner.running) {
            return;
        }
        action = id;
        blocked = [];
        exitCode = -1;
        errorsRead = false;
        runner.command = Session.actionCommand(id, force);
        runner.running = true;
        if (!Session.isPower(id) || force) {
            visible = false;
        }
    }

    function finished() {
        if (exitCode < 0 || !errorsRead) {
            return;
        }
        if (exitCode === 0) {
            visible = false;
            return;
        }
        const found = Session.isPower(action) ? Session.blockers(errors) : [];
        if (found.length > 0) {
            blocked = found;
            return;
        }
        console.warn(`quickspace: ${runner.command.join(" ")} exited ${exitCode}: ${errors.trim()}`);
        visible = false;
    }

    anchor.item: icon
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Left
    anchor.margins.bottom: -10
    grabFocus: true
    color: "transparent"
    implicitWidth: 240
    implicitHeight: card.implicitHeight

    Process {
        id: runner

        stderr: StdioCollector {
            onStreamFinished: {
                root.errors = text;
                root.errorsRead = true;
                root.finished();
            }
        }
        onExited: (code, status) => {
            root.exitCode = code;
            root.finished();
        }
    }

    Rectangle {
        id: card

        anchors.fill: parent
        implicitHeight: list.implicitHeight + 12
        radius: 12
        color: Theme.surface
        border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.08)

        Column {
            id: list

            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            Repeater {
                model: root.blocked.length > 0 ? [] : Session.ACTIONS

                MenuRow {
                    required property var modelData

                    width: list.width
                    enabled: !runner.running
                    icon: modelData.icon
                    label: modelData.label
                    onClicked: root.run(modelData.id, false)
                }
            }

            Text {
                visible: root.blocked.length > 0
                width: list.width
                leftPadding: 10
                rightPadding: 10
                topPadding: 6
                bottomPadding: 4
                wrapMode: Text.WordWrap
                text: `${Session.ACTIONS.find(a => a.id === root.action)?.label ?? ""} is blocked by:`
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 12.5
                font.weight: Font.Bold
            }

            Repeater {
                model: root.blocked

                Text {
                    required property string modelData

                    width: list.width
                    leftPadding: 10
                    rightPadding: 10
                    wrapMode: Text.WordWrap
                    // Inhibitor names come from other programs: never markup.
                    textFormat: Text.PlainText
                    text: modelData
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }

            MenuRow {
                visible: root.blocked.length > 0
                width: list.width
                enabled: !runner.running
                icon: "dialog-warning-symbolic"
                label: "Anyway"
                onClicked: root.run(root.action, true)
            }

            MenuRow {
                visible: root.blocked.length > 0
                width: list.width
                icon: "window-close-symbolic"
                label: "Cancel"
                onClicked: root.toggle()
            }
        }
    }
}
