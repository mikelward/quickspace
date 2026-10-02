pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking
import "lib/network.mjs" as Net

// What the network popovers share. There's one popover per monitor, but
// Wi-Fi scanning is one switch per device, so it's held here, on while any
// popover is open.
Singleton {
    id: root

    // The network popovers that are open, across monitors (Net.trackOpen).
    property var open: []

    Instantiator {
        model: Networking.devices.values.filter(d => d.type === DeviceType.Wifi)

        delegate: Binding {
            required property var modelData

            target: modelData
            property: "scannerEnabled"
            value: Net.shouldScan(root.open)
        }
    }
}
