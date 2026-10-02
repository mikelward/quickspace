import QtQuick

// The clocks at the bar's right end (SPEC.md §7.3): each listed zone as
// "LABEL HH:MM", then local as "MMM d HH:MM", with a small −1 / +1 on a zone
// whose date differs from local's. A click opens the popover.
Row {
    id: root

    spacing: 2

    TapHandler {
        onTapped: popover.toggle()
    }

    ClocksPopover {
        id: popover

        clocks: root
    }

    Repeater {
        model: ClockData.items

        Item {
            id: clock

            required property var modelData
            // barClocks's text is "LABEL HH:MM", the time last.
            readonly property int cut: modelData.text.lastIndexOf(" ")
            readonly property string label: cut < 0 ? "" : modelData.text.slice(0, cut)
            readonly property string time: modelData.text.slice(cut + 1)

            height: Theme.chipHeight
            implicitWidth: row.implicitWidth + 14

            Row {
                id: row

                anchors.centerIn: parent
                spacing: 5

                Text {
                    visible: clock.label !== ""
                    anchors.baseline: time.baseline
                    // Labels are any text (SPEC.md §7.3), never markup.
                    textFormat: Text.PlainText
                    text: clock.label
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: clock.modelData.local ? 12 : 10.5
                    font.weight: clock.modelData.local ? Font.Medium : Font.DemiBold
                    font.letterSpacing: clock.modelData.local ? 0 : 0.4
                }

                Text {
                    id: time

                    text: clock.time
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: clock.modelData.local ? Font.Bold : Font.Medium
                    font.features: ({ "tnum": 1 })
                }

                Text {
                    visible: clock.modelData.dayOffset !== 0
                    anchors.top: time.top
                    text: clock.modelData.dayOffset > 0 ? `+${clock.modelData.dayOffset}` : `−${-clock.modelData.dayOffset}`
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 9.5
                    font.weight: Font.Bold
                }
            }
        }
    }
}
