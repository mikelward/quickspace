// Tests for osd.mjs.
import { test } from "node:test";
import assert from "node:assert/strict";
import { SHOWN_MS, snapshot, changed, muteChanged, volumePill, micPill, brightnessPill } from "./osd.mjs";

const speakers = { name: "speakers", ready: true };
const headset = { name: "headset", ready: true };

test("the OSD shows for 1.2 s", () => {
    assert.equal(SHOWN_MS, 1200);
});

test("a node without audio, or not yet ready, has no snapshot", () => {
    assert.equal(snapshot(null, { volume: 1, muted: false }), null);
    assert.equal(snapshot({ name: "binding", ready: false }, { volume: 0, muted: false }), null);
    assert.equal(snapshot(speakers, null), null);
    assert.deepEqual(snapshot(speakers, { volume: 0.5, muted: false }), { node: speakers, volume: 0.5, muted: false });
});

test("a volume or mute change on the same node shows", () => {
    const before = snapshot(speakers, { volume: 0.5, muted: false });
    assert.equal(changed(before, snapshot(speakers, { volume: 0.55, muted: false })), true);
    assert.equal(changed(before, snapshot(speakers, { volume: 0.5, muted: true })), true);
});

test("startup, a new default device, or float noise doesn't", () => {
    const before = snapshot(speakers, { volume: 0.5, muted: false });
    assert.equal(changed(null, before), false);
    assert.equal(changed(before, snapshot(headset, { volume: 0.2, muted: false })), false);
    assert.equal(changed(before, snapshot(speakers, { volume: 0.501, muted: false })), false);
    assert.equal(changed(before, null), false);
});

test("the volume pill shows the level, capped for the bar but not the label", () => {
    assert.deepEqual(volumePill({ volume: 0.62, muted: false }), { icon: "audio-volume-medium-symbolic", level: 0.62, label: "62%" });
    assert.deepEqual(volumePill({ volume: 1.5, muted: false }), { icon: "audio-volume-high-symbolic", level: 1, label: "150%" });
    assert.deepEqual(volumePill({ volume: 0.62, muted: true }), { icon: "audio-volume-muted-symbolic", level: 0, label: "Muted" });
    assert.deepEqual(volumePill({ volume: NaN, muted: false }), { icon: "audio-volume-muted-symbolic", level: 0, label: "0%" });
});

test("the mic pill says on or off, with no level", () => {
    assert.deepEqual(micPill({ muted: true }), { icon: "microphone-sensitivity-muted-symbolic", level: null, label: "Mic off" });
    assert.deepEqual(micPill({ muted: false }), { icon: "audio-input-microphone-symbolic", level: null, label: "Mic on" });
});

test("the mic shows a mute change, not a level change", () => {
    const mic = { name: "mic", ready: true };
    const before = snapshot(mic, { volume: 0.5, muted: false });
    assert.equal(muteChanged(before, snapshot(mic, { volume: 0.5, muted: true })), true);
    assert.equal(muteChanged(before, snapshot(mic, { volume: 0.8, muted: false })), false);
    assert.equal(muteChanged(null, before), false);
});

test("the brightness pill shows the backlight's level", () => {
    assert.deepEqual({ ...brightnessPill(50) }, { icon: "display-brightness-symbolic", level: 0.5, label: "50%" });
    assert.equal(brightnessPill(140).label, "100%", "clamped");
    assert.equal(brightnessPill(-3).level, 0, "clamped");
    assert.equal(brightnessPill(NaN).label, "0%", "a bad level reads as 0");
});
