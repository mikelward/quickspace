// Tests for audio.mjs.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
    NODE_TYPES, deviceLabel, streamLabel, audioLists, volumeText, sliderVolume,
} from "./audio.mjs";

const AUDIO_SINK = NODE_TYPES.sink;
const AUDIO_SOURCE = NODE_TYPES.source;
const AUDIO_OUT_STREAM = NODE_TYPES.outStream;
// Quickshell's AudioInStream ("Stream/Input/Audio"): an app recording.
const AUDIO_IN_STREAM = 0b01101;
const node = (id, type, fields = {}) => ({ id, type, name: `node${id}`, description: "", nickname: "", properties: {}, ...fields });

test("devices are named by description, then nickname, then node name", () => {
    assert.equal(deviceLabel(node(1, AUDIO_SINK, { description: "Speakers", nickname: "spk" })), "Speakers");
    assert.equal(deviceLabel(node(1, AUDIO_SINK, { nickname: "spk" })), "spk");
    assert.equal(deviceLabel(node(1, AUDIO_SINK)), "node1");
});

test("apps are named by the app, then what it's playing", () => {
    assert.equal(streamLabel(node(5, AUDIO_OUT_STREAM, { properties: { "application.name": "Firefox", "media.name": "Video" } })), "Firefox");
    assert.equal(streamLabel(node(5, AUDIO_OUT_STREAM, { properties: { "media.name": "Video" } })), "Video");
    assert.equal(streamLabel(node(5, AUDIO_OUT_STREAM, { description: "Stream" })), "Stream");
});

test("nodes split into outputs, inputs and apps, each sorted by name", () => {
    const lists = audioLists([
        node(1, AUDIO_SINK, { description: "Speakers" }),
        node(2, AUDIO_SINK, { description: "Headphones" }),
        node(3, AUDIO_SOURCE, { description: "Microphone" }),
        node(4, AUDIO_OUT_STREAM, { properties: { "application.name": "mpv" } }),
        node(5, AUDIO_OUT_STREAM, { properties: { "application.name": "Firefox" } }),
        // A recording app and a video node are neither.
        node(6, AUDIO_IN_STREAM, { properties: { "application.name": "Recorder" } }),
        node(7, 0b10, { description: "Camera" }),
    ]);
    assert.deepEqual(lists.outputs.map(deviceLabel), ["Headphones", "Speakers"]);
    assert.deepEqual(lists.inputs.map(deviceLabel), ["Microphone"]);
    assert.deepEqual(lists.apps.map(streamLabel), ["Firefox", "mpv"]);
});

test("the level reads as a percentage, or muted", () => {
    assert.equal(volumeText(0.7, false), "70%");
    assert.equal(volumeText(1.25, false), "125%");
    assert.equal(volumeText(0.7, true), "Muted");
    assert.equal(volumeText(undefined, false), "");
});

test("a slider sets whole percents from 0 to 100", () => {
    assert.equal(sliderVolume(0.456), 0.46);
    assert.equal(sliderVolume(-0.2), 0);
    assert.equal(sliderVolume(1.4), 1);
    assert.equal(sliderVolume(NaN), 0);
});

test("the kinds come from the caller, as Quickshell numbers them", () => {
    const types = { sink: 101, source: 102, outStream: 103 };
    const lists = audioLists([node(1, 101), node(2, 102), node(3, 103), node(4, NODE_TYPES.sink)], types);
    assert.deepEqual([lists.outputs.map(n => n.id), lists.inputs.map(n => n.id), lists.apps.map(n => n.id)], [[1], [2], [3]]);
});
