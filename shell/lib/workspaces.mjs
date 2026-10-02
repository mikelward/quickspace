// The bar's workspaces (SPEC.md §6.5, §7.2, §14.4), as pure functions the
// QML binds to. The QML turns Quickshell.Hyprland's monitors and toplevels
// into the plain objects these take, and maps app IDs to icons.

export const FIRST = 1;
export const LAST = 9;
// Icons shown per workspace before the rest collapse into "+n".
export const MAX_ICONS = 5;

// Attention marks (§14.4), kept as events arrive. A snapshot can't say
// which came first or what was on screen when a notification arrived, so
// the QML feeds Hyprland's and the notification daemon's events through
// updateMarks and hands the result to barWorkspaces. The state is
//
//   {guard: [address], notes: {id: {app, wide: [address], direct: [address]}}}
//
// where `guard` holds the windows the focus guard kept from focus, and
// `notes` each notification's marks by its ID, so dismissing one clears
// exactly what it marked. A note's `wide` windows came from marking its
// whole app and `direct` ones from naming the window; only the app's own
// activation tells them apart. Hyprland's own urgent flag lives on the window.
export const NO_MARKS = Object.freeze({ guard: Object.freeze([]), notes: Object.freeze({}) });

// The marks after one event, without changing `marks`. Events:
//
//   {type: "notified", id, app, windows, visible}  an app-wide mark: the
//       app's windows on workspaces not on screen right now (`visible` is a
//       Set of workspace IDs), and only those, until it clears. A
//       replacement (the same ID again) keeps what it marked before.
//   {type: "notified", id, app, address, windows, visible}  a notification
//       naming its window: marked only if that window's workspace isn't on
//       screen, like an app-wide mark.
//   {type: "guarded", address}   the focus guard kept a new window from focus.
//   {type: "activated", app}     urgent>>ADDRESS: the app's own activation
//       replaces its app-wide marks.
//   {type: "focused", address}   the window was attended to: the guard's
//       mark on it clears, and so does every notification's that covered it.
//   {type: "dismissed", id}      the notification was dismissed.
//   {type: "closed", address}    the window is gone.
export function updateMarks(marks, event) {
    let guard = marks.guard;
    const notes = {};
    const put = (id, note) => {
        if (note.wide.length + note.direct.length > 0) {
            notes[id] = note;
        }
    };
    const covers = (note, address) => note.wide.includes(address) || note.direct.includes(address);
    const without = (list, address) => list.filter((a) => a !== address);
    switch (event.type) {
    case "notified": {
        Object.assign(notes, marks.notes);
        const note = notes[event.id] ?? { app: event.app, wide: [], direct: [] };
        delete notes[event.id];
        if (event.address !== undefined) {
            const named = event.windows.find((w) => w.address === event.address);
            const hidden = named !== undefined && !event.visible.has(named.workspace);
            put(event.id, { ...note, direct: hidden ? [...new Set([...note.direct, event.address])] : note.direct });
        } else {
            const hidden = event.windows
                .filter((w) => w.app === event.app && !event.visible.has(w.workspace))
                .map((w) => w.address);
            put(event.id, { ...note, wide: [...new Set([...note.wide, ...hidden])] });
        }
        break;
    }
    case "guarded":
        Object.assign(notes, marks.notes);
        guard = guard.includes(event.address) ? guard : [...guard, event.address];
        break;
    case "activated":
        for (const [id, note] of Object.entries(marks.notes)) {
            put(id, note.app === event.app ? { ...note, wide: [] } : note);
        }
        break;
    case "focused":
        guard = without(guard, event.address);
        for (const [id, note] of Object.entries(marks.notes)) {
            if (!covers(note, event.address)) {
                notes[id] = note;
            }
        }
        break;
    case "dismissed":
        Object.assign(notes, marks.notes);
        delete notes[event.id];
        break;
    case "closed":
        guard = without(guard, event.address);
        for (const [id, note] of Object.entries(marks.notes)) {
            put(id, { ...note, wide: without(note.wide, event.address), direct: without(note.direct, event.address) });
        }
        break;
    default:
        throw new Error(`unknown mark event ${event.type}`);
    }
    return { guard, notes };
}

// Which windows are marked: Hyprland's urgent flag, plus `marks`.
export function markedWindows({ windows, marks = NO_MARKS }) {
    const marked = new Set([...marks.guard, ...Object.values(marks.notes).flatMap((n) => [...n.wide, ...n.direct])]);
    for (const w of windows) {
        if (w.urgent === true) {
            marked.add(w.address);
        }
    }
    // A mark for a window that has since closed isn't on the bar.
    const open = new Set(windows.map((w) => w.address));
    return new Set([...marked].filter((a) => open.has(a)));
}

// The icons one workspace shows, in window order: at most MAX_ICONS, with
// marked windows kept in view ahead of unmarked ones, so a ringed icon is
// never folded into "+n".
function icons(windows, marked) {
    const keep = new Set();
    for (const w of windows) {
        if (keep.size < MAX_ICONS && marked.has(w.address)) {
            keep.add(w.address);
        }
    }
    for (const w of windows) {
        if (keep.size < MAX_ICONS) {
            keep.add(w.address);
        }
    }
    const shown = windows.filter((w) => keep.has(w.address))
        .map((w) => ({ address: w.address, app: w.app, marked: marked.has(w.address) }));
    return { icons: shown, more: windows.length - shown.length };
}

// What one monitor's bar shows: workspaces FIRST to LAST, always all nine
// (§7.1), each as
//
//   {id, state, urgent, big, icons: [{address, app, marked}], more}
//
// where state is "current" (this monitor's workspace), "elsewhere" (shown
// on another monitor), "occupied" or "empty"; urgent is any marked window
// on it; and big is a maximized or fullscreen window on it (§6.3).
//
// `monitors` is [{name, workspace}], each monitor's active workspace ID.
// `windows` is [{address, workspace, app, urgent, fullscreen}] in the order
// their icons should appear, fullscreen being the client's `fullscreen`
// state from `hyprctl clients` (0 none, 1 maximized, 2 fullscreen, 3 both),
// not the 0/1 argument the `fullscreen` dispatcher takes (SPEC.md §6.3). Special workspaces (negative IDs) and
// any outside FIRST..LAST aren't on the bar. `marks` comes from updateMarks.
export function barWorkspaces({ monitor, monitors, windows, marks = NO_MARKS }) {
    const current = monitors.find((m) => m.name === monitor)?.workspace;
    const elsewhere = new Set(monitors.filter((m) => m.name !== monitor).map((m) => m.workspace));
    const marked = markedWindows({ windows, marks });
    const list = [];
    for (let id = FIRST; id <= LAST; id++) {
        const here = windows.filter((w) => w.workspace === id);
        let state = here.length > 0 ? "occupied" : "empty";
        if (id === current) {
            state = "current";
        } else if (elsewhere.has(id)) {
            state = "elsewhere";
        }
        list.push({
            id,
            state,
            urgent: here.some((w) => marked.has(w.address)),
            big: here.some((w) => w.fullscreen > 0),
            ...icons(here, marked),
        });
    }
    return list;
}

// The workspace `notches` of scrolling over the bar go to from `current`:
// one step per notch, toward the next workspace for a positive count and
// the previous for a negative one, stopping at FIRST and LAST as
// Super+Left/Right do. null means stay: no whole notch, already at the end,
// or on a special workspace, which has no neighbors.
export function scrollTarget(current, notches) {
    const steps = Math.trunc(notches);
    if (!Number.isInteger(current) || current < FIRST || current > LAST || !steps) {
        return null;
    }
    const target = Math.min(LAST, Math.max(FIRST, current + steps));
    return target === current ? null : target;
}
