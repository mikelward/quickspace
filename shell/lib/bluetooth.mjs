// The bar's Bluetooth icon and popover (SPEC.md §7.4), as pure functions
// the QML binds to. Adapters and devices are Quickshell.Bluetooth's (BlueZ),
// or plain objects with the same fields in the tests.

// Quickshell's BluetoothAdapterState and BluetoothDeviceState.
const ADAPTER_ENABLED = 1;
const ADAPTER_ENABLING = 2;
const DEVICE_CONNECTED = 1;
const DEVICE_DISCONNECTING = 2;
const DEVICE_CONNECTING = 3;

// The bar icon: hidden with no adapter, then off, on, or connected (to at
// least one device).
export function bluetoothIcon(adapter, devices) {
    if (!adapter) {
        return { visible: false, icon: "" };
    }
    const on = adapter.state === ADAPTER_ENABLED || adapter.state === ADAPTER_ENABLING;
    if (!on) {
        return { visible: true, icon: "bluetooth-disabled-symbolic" };
    }
    const connected = devices.some((d) => d.state === DEVICE_CONNECTED);
    return { visible: true, icon: connected ? "bluetooth-active-symbolic" : "bluetooth-disconnected-symbolic" };
}

// What a device is called: the name you gave it, else its own, else its
// address.
export function deviceName(device) {
    return device.name || device.deviceName || device.address || "";
}

// A device's line in the popover: connecting or disconnecting, or
// connected with its battery when it reports one; "" when disconnected.
export function deviceStatus(device) {
    if (device.state === DEVICE_CONNECTING) {
        return "Connecting…";
    }
    if (device.state === DEVICE_DISCONNECTING) {
        return "Disconnecting…";
    }
    if (device.state !== DEVICE_CONNECTED) {
        return "";
    }
    if (device.batteryAvailable && Number.isFinite(device.battery)) {
        return `Connected · ${Math.round(device.battery * 100)}%`;
    }
    return "Connected";
}

// The devices the popover lists: the paired ones, connected first, then
// by name. Pairing a new one happens in blueman-manager (SPEC.md §7.4).
export function pairedDevices(devices) {
    const rank = (d) => (d.state === DEVICE_CONNECTED ? 0 : 1);
    return devices.filter((d) => d.paired || d.bonded)
        .sort((a, b) => rank(a) - rank(b) || deviceName(a).localeCompare(deviceName(b)));
}

// Whether clicking a device should connect it (true) or disconnect it.
export function shouldConnect(device) {
    return device.state !== DEVICE_CONNECTED && device.state !== DEVICE_CONNECTING;
}
