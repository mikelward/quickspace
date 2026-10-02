// Light or dark for the shell's palette (SPEC.md §15). Until the shell owns
// the schedule, it follows `org.gnome.desktop.interface color-scheme`, which
// conf's theme daemon flips on its own schedule.

// Whether a line of `gsettings get` output (`'prefer-dark'`) or of
// `gsettings monitor` output (`color-scheme: 'prefer-dark'`) means dark.
// `default` is GNOME's "no preference", which apps show light. null means
// the line isn't a color scheme, so the caller keeps what it has.
export function schemeIsDark(line) {
    if (typeof line !== "string") {
        return null;
    }
    const m = /^(?:color-scheme:\s*)?'(default|prefer-dark|prefer-light)'\s*$/.exec(line.trim());
    if (!m) {
        return null;
    }
    return m[1] === "prefer-dark";
}

// The scheme state after one line of gsettings output: `{dark, changed}`,
// where `changed` says the monitor has reported a change. The startup read
// (`fromMonitor` false) can finish after the monitor's first change, and
// then it's older news, so it's ignored.
export function heardScheme(state, line, fromMonitor) {
    const dark = schemeIsDark(line);
    if (dark === null || (!fromMonitor && state.changed)) {
        return state;
    }
    return { dark, changed: state.changed || fromMonitor };
}
