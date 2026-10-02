// Tests for launch.mjs.
import { test } from "node:test";
import assert from "node:assert/strict";
import { initial, step } from "./launch.mjs";

const COMMAND = ["quickspace", "launch", "--", "blueman-manager"];

// Feeds `events` through step, returning every run along the way.
function play(events) {
    const runs = [];
    let run = initial();
    for (const event of events) {
        run = step(run, event, COMMAND);
        runs.push(run);
    }
    return runs;
}

// The reports a sequence produced, in order.
function reports(events) {
    return play(events).filter(r => r.done && r.report !== null).map(r => r.report);
}

const STARTED = { type: "started" };
const STOPPED = { type: "stopped" };
const exited = code => ({ type: "exited", code });
const stderr = text => ({ type: "stderr", text });

test("a quiet success finishes silently, once both exit and stderr are in", () => {
    const runs = play([STARTED, exited(0), STOPPED, stderr("")]);
    assert.deepEqual(runs.map(r => r.done), [false, false, false, true]);
    assert.equal(runs[3].report, null);
});

test("a nonzero exit warns with the code and the whole of stderr", () => {
    assert.deepEqual(reports([STARTED, exited(127), STOPPED, stderr("blueman-manager: not found\n")]), [
        { level: "warn", message: "quickspace: quickspace launch -- blueman-manager exited 127: blueman-manager: not found" },
    ]);
});

test("stderr from a successful run is logged, not warned", () => {
    assert.deepEqual(reports([STARTED, exited(0), stderr("quickspace: no focus grant\n")]), [
        { level: "log", message: "quickspace: quickspace launch -- blueman-manager: quickspace: no focus grant" },
    ]);
});

test("stderr ending before the exit code waits for the code", () => {
    const runs = play([STARTED, stderr("oops"), exited(1)]);
    assert.deepEqual(runs.map(r => r.done), [false, false, true]);
    assert.equal(runs[2].report.message, "quickspace: quickspace launch -- blueman-manager exited 1: oops");
});

test("an exit code alone isn't the end: stderr may still be coming", () => {
    const runs = play([STARTED, exited(1), STOPPED]);
    assert.equal(runs.at(-1).done, false);
});

test("stopping without starting is a failed start", () => {
    const runs = play([STOPPED]);
    assert.equal(runs[0].done, true);
    assert.deepEqual(runs[0].report, { level: "warn", message: "quickspace: couldn't start quickspace launch -- blueman-manager" });
});

test("a finished run reports once, whatever arrives after", () => {
    assert.equal(reports([STARTED, exited(2), stderr("x"), STOPPED, stderr("y"), exited(3)]).length, 1);
    assert.equal(reports([STOPPED, STOPPED, exited(1), stderr("z")]).length, 1);
    const runs = play([STARTED, exited(0), stderr(""), STOPPED]);
    assert.equal(runs.at(-1).done, true);
    assert.equal(runs.at(-1).report, null);
});

test("an unknown event is an error", () => {
    assert.throws(() => step(initial(), { type: "crashed" }, COMMAND), /unknown process event: crashed/);
});
