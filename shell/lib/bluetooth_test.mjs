// Tests for bluetooth.mjs.
import { test } from "node:test";
import assert from "node:assert/strict";
import { bluetoothIcon, deviceName, deviceStatus, pairedDevices, shouldConnect } from "./bluetooth.mjs";

const dev = (fields) => ({ name: "", deviceName: "", address: "00:11:22:33:44:55", state: 0, paired: true, bonded: false, batteryAvailable: false, battery: 0, ...fields });

test("the icon is hidden with no adapter, then off, on or connected", () => {
    assert.equal(bluetoothIcon(null, []).visible, false);
    assert.equal(bluetoothIcon({ state: 0 }, []).icon, "bluetooth-disabled-symbolic");
    assert.equal(bluetoothIcon({ state: 4 }, []).icon, "bluetooth-disabled-symbolic");
    assert.equal(bluetoothIcon({ state: 1 }, [dev({ state: 0 })]).icon, "bluetooth-disconnected-symbolic");
    assert.equal(bluetoothIcon({ state: 1 }, [dev({ state: 1 })]).icon, "bluetooth-active-symbolic");
    assert.equal(bluetoothIcon({ state: 2 }, []).icon, "bluetooth-disconnected-symbolic");
});

test("devices are named by alias, then their own name, then address", () => {
    assert.equal(deviceName(dev({ name: "My buds", deviceName: "WF-1000" })), "My buds");
    assert.equal(deviceName(dev({ deviceName: "WF-1000" })), "WF-1000");
    assert.equal(deviceName(dev({})), "00:11:22:33:44:55");
});

test("a device's status says what it's doing, with battery when connected", () => {
    assert.equal(deviceStatus(dev({ state: 0 })), "");
    assert.equal(deviceStatus(dev({ state: 3 })), "Connecting…");
    assert.equal(deviceStatus(dev({ state: 2 })), "Disconnecting…");
    assert.equal(deviceStatus(dev({ state: 1 })), "Connected");
    assert.equal(deviceStatus(dev({ state: 1, batteryAvailable: true, battery: 0.8 })), "Connected · 80%");
});

test("the list is the paired devices, connected first, then by name", () => {
    const list = pairedDevices([
        dev({ name: "Zed", state: 0 }),
        dev({ name: "Mouse", state: 1 }),
        dev({ name: "Stranger", paired: false }),
        dev({ name: "Bonded", paired: false, bonded: true }),
        dev({ name: "Alpha", state: 0 }),
    ]);
    assert.deepEqual(list.map(deviceName), ["Mouse", "Alpha", "Bonded", "Zed"]);
});

test("clicking connects a disconnected device and disconnects a connected one", () => {
    assert.equal(shouldConnect(dev({ state: 0 })), true);
    assert.equal(shouldConnect(dev({ state: 2 })), true);
    assert.equal(shouldConnect(dev({ state: 1 })), false);
    assert.equal(shouldConnect(dev({ state: 3 })), false);
});
