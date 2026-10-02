// Hyprland dispatches from the bar, spelled for whichever config Hyprland
// runs. Under a Lua config (Hyprland.usingLua) a dispatch is a Lua call,
// hl.dsp.*, as the config's own bindings and conf's hyprctl uses write
// them; the old text form is ignored there. Under hyprlang it's the text
// form.

// Go to workspace `id`.
export function focusWorkspace(id, lua) {
    if (!Number.isInteger(id)) {
        throw new Error(`not a workspace ID: ${id}`);
    }
    return lua ? `hl.dsp.focus({ workspace = ${id} })` : `workspace ${id}`;
}

// Focus the window at `address` (hex, with or without 0x).
export function focusWindow(address, lua) {
    const hex = String(address ?? "").toLowerCase().replace(/^0x/, "");
    if (!/^[0-9a-f]+$/.test(hex)) {
        throw new Error(`not a window address: ${address}`);
    }
    return lua ? `hl.dsp.focus({ window = "address:0x${hex}" })` : `focuswindow address:0x${hex}`;
}
