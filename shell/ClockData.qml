pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "lib/clocks.mjs" as Clocks
import "lib/tzdata.mjs" as Tz

// The bar's clocks (SPEC.md §7.3). It reads clocks.json and
// clocks.local.json (§16.1) and runs quickspace-tz for their zones' offsets
// and abbreviations: at startup, when either file changes, and when a
// period ends. A minute's tick only redraws from what it already has.
Singleton {
    id: root

    // What the bar shows, from shell/lib/clocks.mjs's barClocks.
    property var items: []

    // The last list whose zones all loaded, and the one being tried.
    property var good: Clocks.DEFAULT_CLOCKS
    property var trying: Clocks.DEFAULT_CLOCKS
    property var table: null

    readonly property string dir: (Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`) + "/quickspace"

    function textOf(file) {
        // A missing file is the defaults' cue, not an error.
        return file.loaded ? file.text() : null;
    }

    // A file that exists but can't be read: say so, and keep the last good
    // list rather than taking it for missing.
    function unreadable(file, error) {
        console.warn(`quickspace: ${file.path}: ${FileViewError.toString(error)}`);
        file.broken = true;
        root.load();
    }

    function load() {
        if (shared.broken || local.broken) {
            // With nothing shown yet, the defaults beat an empty bar.
            if (!root.table) {
                root.lookUp(root.good);
            }
            return;
        }
        const result = Clocks.loadClocks(textOf(shared), textOf(local), root.good);
        // TODO: a bad file should be a notification naming it (SPEC.md §16.1)
        // once the shell owns notifications (M4).
        for (const error of result.errors) {
            console.warn(`quickspace: ${error}`);
        }
        root.lookUp(result.clocks);
    }

    function lookUp(clocks) {
        root.trying = clocks;
        tz.running = false;
        tz.command = ["quickspace-tz"].concat(clocks.map(c => c.zone));
        tz.running = true;
    }

    function looked(text) {
        let table;
        try {
            table = Tz.zoneTable(JSON.parse(text));
        } catch (e) {
            console.warn(`quickspace: quickspace-tz: ${e}`);
            root.retry();
            return;
        }
        if (table.localError) {
            // Local's clock may show twice (SPEC.md §7.3), but the bar works.
            console.warn(`quickspace: clocks: local zone: ${table.localError}`);
        }
        for (const e of table.errors) {
            console.warn(`quickspace: clocks: ${e.error}`);
        }
        if (table.errors.length > 0 && root.trying !== root.good) {
            // A zone that doesn't load is an error at load: keep the last
            // good list (SPEC.md §7.3).
            root.lookUp(root.good);
            return;
        }
        if (table.errors.length > 0 && root.table) {
            // The good list stopped loading, say while tzdata is being
            // upgraded.
            root.retry();
            return;
        }
        root.good = root.trying;
        root.table = table;
        root.update();
        refresh.interval = Math.max(1000, Tz.refreshAt(table, Date.now()) - Date.now());
        refresh.restart();
    }

    // Any failed run keeps the last table and tries again shortly, so a
    // missed refresh can't leave a stale offset up until the next restart.
    function retry() {
        refresh.interval = 60 * 1000;
        refresh.restart();
    }

    function update() {
        if (!root.table) {
            return;
        }
        const table = root.table;
        root.items = Clocks.barClocks({
            // Skip any zone that didn't load, so one bad entry in an
            // otherwise unchanged list can't blank the clocks.
            clocks: root.good.filter(c => table.periods.has(c.zone)),
            localZone: table.localZone,
            instant: Date.now(),
            offsetOf: Tz.offsetOf(table),
            abbrOf: Tz.abbrOf(table),
        });
    }

    FileView {
        id: shared

        property bool broken: false

        path: `${root.dir}/clocks.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            broken = false;
            root.load();
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                broken = false;
                root.load();
            } else {
                root.unreadable(this, error);
            }
        }
    }

    FileView {
        id: local

        property bool broken: false

        path: `${root.dir}/clocks.local.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            broken = false;
            root.load();
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                broken = false;
                root.load();
            } else {
                root.unreadable(this, error);
            }
        }
    }

    Process {
        id: tz

        stdout: StdioCollector {
            onStreamFinished: root.looked(text)
        }
        onExited: (code, status) => {
            if (code !== 0) {
                console.warn(`quickspace: quickspace-tz exited ${code}`);
                root.retry();
            }
        }
    }

    // At the next change of offset in any zone, and at least daily.
    Timer {
        id: refresh

        onTriggered: root.lookUp(root.good)
    }

    SystemClock {
        precision: SystemClock.Minutes
        onDateChanged: root.update()
    }
}
