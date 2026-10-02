// The volume popover (SPEC.md §7.4): outputs, inputs and per-app levels,
// as pure functions over PipeWire nodes. A node is anything with Quickshell
// PwNode's `id`, `type`, `name`, `description`, `nickname` and
// `properties`, so the tests pass plain objects.

// Quickshell 0.3's PwNodeType values for the three kinds the popover
// lists. The QML passes Quickshell's own (PwNodeType.AudioSink and so on),
// so these only stand in for it in the tests. Quickshell maps PipeWire's
// media classes to them: "Audio/Sink", "Audio/Source", and
// "Stream/Output/Audio", an app playing sound, which it flags Audio | Sink |
// Stream (src/services/pipewire/node.cpp).
export const NODE_TYPES = Object.freeze({
    sink: 0b10001,
    source: 0b01001,
    outStream: 0b10101,
});

// What a device is called: PipeWire's description ("Built-in Audio Analog
// Stereo"), else its nickname, else its node name.
export function deviceLabel(node) {
    return node.description || node.nickname || node.name || "";
}

// What an app's stream is called: the app's name, else what it's playing,
// else the node's own label.
export function streamLabel(node) {
    const p = node.properties ?? {};
    return p["application.name"] || p["media.name"] || deviceLabel(node);
}

// The popover's three lists, each sorted by label: output devices, input
// devices, and apps playing sound, by `types` as in NODE_TYPES. Nodes of
// other kinds (video, recording apps) are left out.
export function audioLists(nodes, types = NODE_TYPES) {
    const outputs = [];
    const inputs = [];
    const apps = [];
    for (const n of nodes) {
        if (n.type === types.sink) {
            outputs.push(n);
        } else if (n.type === types.source) {
            inputs.push(n);
        } else if (n.type === types.outStream) {
            apps.push(n);
        }
    }
    const by = (label) => (a, b) => label(a).localeCompare(label(b));
    return {
        outputs: outputs.sort(by(deviceLabel)),
        inputs: inputs.sort(by(deviceLabel)),
        apps: apps.sort(by(streamLabel)),
    };
}

// A volume as the popover writes it beside a slider: "70%", or "Muted".
export function volumeText(volume, muted) {
    if (muted) {
        return "Muted";
    }
    return Number.isFinite(volume) ? `${Math.round(volume * 100)}%` : "";
}

// The volume for a slider dragged to `fraction` of its width, within 0 to
// 1, in whole percent.
export function sliderVolume(fraction) {
    if (!Number.isFinite(fraction)) {
        return 0;
    }
    return Math.round(Math.min(1, Math.max(0, fraction)) * 100) / 100;
}
