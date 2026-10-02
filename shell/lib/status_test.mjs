// Tests for status.mjs.
import { test } from "node:test";
import assert from "node:assert/strict";
import { batteryView, volumeIcon, scrolledVolume } from "./status.mjs";

test("the battery shows its percentage and level icon", () => {
    assert.deepEqual(batteryView({ present: true, percentage: 0.82, state: 2 }),
        { visible: true, text: "82%", icon: "battery-level-80-symbolic", low: false });
    assert.equal(batteryView({ present: true, percentage: 0.86, state: 2 }).icon, "battery-level-90-symbolic");
    assert.equal(batteryView({ present: true, percentage: 0.04, state: 2 }).icon, "battery-level-0-symbolic");
});

test("a charging battery says so", () => {
    assert.equal(batteryView({ present: true, percentage: 0.5, state: 1 }).icon, "battery-level-50-charging-symbolic");
    assert.equal(batteryView({ present: true, percentage: 0.5, state: 5 }).icon, "battery-level-50-charging-symbolic");
    assert.equal(batteryView({ present: true, percentage: 1, state: 4 }).icon, "battery-level-100-charged-symbolic");
});

test("the battery is red below 15% unless it's charging", () => {
    assert.equal(batteryView({ present: true, percentage: 0.14, state: 2 }).low, true);
    assert.equal(batteryView({ present: true, percentage: 0.15, state: 2 }).low, false);
    assert.equal(batteryView({ present: true, percentage: 0.09, state: 1 }).low, false);
});

test("no battery shows nothing", () => {
    assert.equal(batteryView({ present: false, percentage: 0.5, state: 2 }).visible, false);
    assert.equal(batteryView({ present: true, percentage: NaN, state: 0 }).visible, false);
});

test("the volume icon follows mute and level", () => {
    assert.equal(volumeIcon({ muted: true, volume: 0.8 }), "audio-volume-muted-symbolic");
    assert.equal(volumeIcon({ muted: false, volume: 0 }), "audio-volume-muted-symbolic");
    assert.equal(volumeIcon({ muted: false, volume: 0.2 }), "audio-volume-low-symbolic");
    assert.equal(volumeIcon({ muted: false, volume: 0.5 }), "audio-volume-medium-symbolic");
    assert.equal(volumeIcon({ muted: false, volume: 0.9 }), "audio-volume-high-symbolic");
    assert.equal(volumeIcon({ muted: false, volume: undefined }), "audio-volume-muted-symbolic");
});

test("scrolling changes the volume by 5% a notch, from 0 to 100%", () => {
    assert.equal(scrolledVolume(0.5, 1), 0.55);
    assert.equal(scrolledVolume(0.5, -2), 0.4);
    assert.equal(scrolledVolume(0.98, 1), 1);
    assert.equal(scrolledVolume(0.02, -1), 0);
    assert.equal(scrolledVolume(0.42, 1), 0.47);
    assert.equal(scrolledVolume(0.42, -1), 0.37);
    assert.equal(scrolledVolume(0.1, 2), 0.2);
    assert.equal(scrolledVolume(undefined, 1), 0.05);
});

test("scrolling up leaves a volume above 100% alone, and down brings it back", () => {
    assert.equal(scrolledVolume(1.3, 1), 1.3);
    assert.equal(scrolledVolume(1.3, -1), 1);
});
