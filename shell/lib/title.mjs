// The window title in the middle of the bar (SPEC.md §7.1), as a pure
// function the QML binds to. Each monitor's bar shows its own workspace's
// window, as waybar's hyprland/window does with separate-outputs.

import { normalizeAddress } from "./workspaces.mjs";

// The title is at most about this many characters wide, as waybar's
// max-length had it. The QML caps its width at this many average
// characters and elides the rest, so Qt cuts only between whole
// characters in any script.
export const MAX_TITLE = 60;

// The workspace a monitor shows: its open special workspace (Hyprland's
// `specialWorkspace.id`, 0 when none), which covers the regular one, or
// else its active one. IDs, or null.
export function shownWorkspace(active, special) {
    return special ? special : active ?? null;
}

// The title for the bar on `monitor` (its name), showing `workspace` (its
// ID, from shownWorkspace):
//   - the focused window's, when it's on this monitor: on the shown
//     workspace, under an open special one, or pinned;
//   - otherwise that workspace's last focused window (`lastWindow`, the
//     address Hyprland reports for it), if it's still there;
//   - otherwise nothing: an empty workspace, or one whose last window left.
// `active` is {monitor, title}, or null when nothing has focus (see
// hasFocus); `windows` are [{address, workspace, title}].
export function barTitle({ monitor, workspace, active, lastWindow, windows }) {
    if (workspace == null) {
        return "";
    }
    if (active && monitor != null && active.monitor === monitor) {
        return oneLine(active.title);
    }
    const address = normalizeAddress(lastWindow);
    const last = address === null ? null
        : windows.find(w => normalizeAddress(w.address) === address && w.workspace === workspace);
    return last ? oneLine(last.title) : "";
}

// Whether an activewindowv2 event's data names a window. Hyprland sends an
// empty address when focus moves to an empty workspace, and Quickshell
// 0.3 ignores that event, leaving its active toplevel on the last window.
export function hasFocus(data) {
    return normalizeAddress(String(data ?? "").split(",")[0]) !== null;
}

// The title on one line, whitespace collapsed. It's not cut here: the QML
// elides it to its width.
function oneLine(title) {
    return String(title ?? "").replace(/\s+/g, " ").trim();
}
