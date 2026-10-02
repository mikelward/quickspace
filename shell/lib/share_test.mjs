// Tests for share.mjs.
import { test } from "node:test";
import assert from "node:assert/strict";
import { isShareNode, shareLinks, liveShares, holdsPopups } from "./share.mjs";

const ACTIVE = 4;
const PAUSED = 3;

test("xdph's screencast nodes are shares, and nothing else is", () => {
    assert.equal(isShareNode({ name: "xdph-streaming-0" }), true);
    assert.equal(isShareNode({ name: "alsa_output.pci-0000_00_1f.3.analog-stereo" }), false);
    assert.equal(isShareNode({ name: "" }), false);
    assert.equal(isShareNode({}), false);
    assert.equal(isShareNode(null), false);
});

test("a share is live while something actively consumes it", () => {
    const share = { id: 40, name: "xdph-streaming-0" };
    const idle = { id: 41, name: "xdph-streaming-1" };
    const mic = { id: 50, name: "alsa_input.usb" };
    const chrome = { id: 60, name: "chrome" };
    const links = [
        { source: share, target: chrome, state: ACTIVE },
        { source: idle, target: chrome, state: PAUSED },
        { source: mic, target: chrome, state: ACTIVE },
        { source: null, target: chrome, state: ACTIVE },
    ];
    assert.deepEqual(liveShares([share, idle, mic, chrome], links, ACTIVE), [share]);
    assert.deepEqual(liveShares([share], [], ACTIVE), []);
});

test("any live share holds popups until the picker says what it is", () => {
    assert.equal(holdsPopups([]), false);
    assert.equal(holdsPopups([{ id: 40, name: "xdph-streaming-0" }]), true);
});

test("only the links out of share nodes are bound", () => {
    const share = { id: 40, name: "xdph-streaming-0" };
    const mic = { id: 50, name: "alsa_input.usb" };
    const chrome = { id: 60, name: "chrome" };
    const out = { source: share, target: chrome };
    assert.deepEqual(shareLinks([out, { source: mic, target: chrome }, { source: null, target: chrome }]), [out]);
});
