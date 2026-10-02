// Tests for dst.mjs, against 2026's US and EU changes written out as
// quickspace-tz would give them.
import { test } from "node:test";
import assert from "node:assert/strict";
import { offsetChanges, nextDstChange, dstMessage, formatDay, clockName } from "./dst.mjs";

const at = (iso) => Date.parse(iso);

const periods = {
    "Europe/London": [
        { start: at("2026-10-02T00:00:00Z"), offset: 60, abbr: "BST" },
        { start: at("2026-10-25T01:00:00Z"), offset: 0, abbr: "GMT" },
        { start: at("2027-03-28T01:00:00Z"), offset: 60, abbr: "BST" },
    ],
    "America/Los_Angeles": [
        { start: at("2026-10-02T00:00:00Z"), offset: -420, abbr: "PDT" },
        { start: at("2026-11-01T09:00:00Z"), offset: -480, abbr: "PST" },
        { start: at("2027-03-14T10:00:00Z"), offset: -420, abbr: "PDT" },
    ],
    "America/New_York": [
        { start: at("2026-10-02T00:00:00Z"), offset: -240, abbr: "EDT" },
        { start: at("2026-11-01T06:00:00Z"), offset: -300, abbr: "EST" },
        { start: at("2027-03-14T07:00:00Z"), offset: -240, abbr: "EDT" },
    ],
    // Casablanca drops an hour for Ramadan in 2027, Feb 7 to Mar 14.
    "Africa/Casablanca": [
        { start: at("2027-01-10T00:00:00Z"), offset: 60, abbr: "+01" },
        { start: at("2027-02-07T02:00:00Z"), offset: 0, abbr: "+00" },
        { start: at("2027-03-14T02:00:00Z"), offset: 60, abbr: "+01" },
    ],
    // El Aaiun follows Casablanca's Ramadan change.
    "Africa/El_Aaiun": [
        { start: at("2027-01-10T00:00:00Z"), offset: 60, abbr: "+01" },
        { start: at("2027-02-07T02:00:00Z"), offset: 0, abbr: "+00" },
        { start: at("2027-03-14T02:00:00Z"), offset: 60, abbr: "+01" },
    ],
    // Nuuk changes at the EU's instant, which is still Saturday there.
    "America/Nuuk": [
        { start: at("2027-01-10T00:00:00Z"), offset: -120, abbr: "-02" },
        { start: at("2027-03-28T01:00:00Z"), offset: -60, abbr: "-01" },
    ],
    // Gaza changes a day and an hour before Nuuk, on Saturday there too.
    "Asia/Gaza": [
        { start: at("2027-01-10T00:00:00Z"), offset: 120, abbr: "EET" },
        { start: at("2027-03-27T00:00:00Z"), offset: 180, abbr: "EEST" },
    ],
    "Australia/Sydney": [
        { start: at("2026-09-01T00:00:00Z"), offset: 600, abbr: "AEST" },
        { start: at("2026-10-03T16:00:00Z"), offset: 660, abbr: "AEDT" },
    ],
    "Asia/Kolkata": [
        { start: at("2026-10-02T00:00:00Z"), offset: 330, abbr: "IST" },
    ],
};
const periodsOf = (zone) => periods[zone];

const clocks = [
    { zone: "America/Los_Angeles", label: "SF" },
    { zone: "America/New_York", label: "NYC" },
    { zone: "Europe/London", label: "LON" },
];

test("offset changes skip a period that only renames the zone", () => {
    const renamed = [
        { start: 0, offset: 60, abbr: "A" },
        { start: 10, offset: 60, abbr: "B" },
        { start: 20, offset: 0, abbr: "C" },
    ];
    assert.deepEqual(offsetChanges(renamed, 0), [{ at: 20, from: 60, to: 0, abbr: "C", fromAbbr: "B" }]);
    assert.deepEqual(offsetChanges(renamed, 20), []);
});

test("London's autumn change comes a week before the US's", () => {
    const change = nextDstChange({ clocks, periodsOf, now: at("2026-10-02T12:00:00Z") });
    assert.deepEqual(change.first.labels, ["LON"]);
    assert.equal(change.first.at, at("2026-10-25T01:00:00Z"));
    assert.deepEqual(change.then.labels, ["SF", "NYC"]);
    assert.deepEqual(change.then.abbrs, ["PST", "EST"]);
    assert.equal(change.then.at, at("2026-11-01T06:00:00Z"));
    assert.equal(dstMessage(change),
        "LON moves to GMT on Sun Oct 25, a week before SF and NYC move to PST/EST on Sun Nov 1. " +
        "For that week, LON is 7 h ahead of SF instead of 8.");
});

test("in spring the US goes first, and the gap is short by an hour for two weeks", () => {
    const change = nextDstChange({ clocks, periodsOf, now: at("2027-01-10T00:00:00Z") });
    assert.equal(dstMessage(change),
        "SF and NYC move to PDT/EDT on Sun Mar 14, two weeks before LON moves to BST on Sun Mar 28. " +
        "For those weeks, SF is 7 h behind LON instead of 8.");
});

test("a change with nothing after it in the window stands alone", () => {
    const us = clocks.slice(0, 2);
    const change = nextDstChange({ clocks: us, periodsOf, now: at("2026-11-02T00:00:00Z") });
    assert.equal(change.then, null);
    assert.equal(dstMessage(change), "SF and NYC move to PDT/EDT on Sun Mar 14.");
});

test("a group's day is its first-listed zone's, even when another listed zone changes first", () => {
    // New York changes three hours before Los Angeles, at 23:00 Saturday in
    // Los Angeles; both change on Sunday where they are.
    const change = nextDstChange({ clocks, periodsOf, now: at("2026-10-26T00:00:00Z") });
    assert.equal(dstMessage(change).startsWith("SF and NYC move to PST/EST on Sun Nov 1"), true);
});

test("zones without DST and zones without periods are left out", () => {
    const some = [{ zone: "Asia/Kolkata", label: "BLR" }, { zone: "Mars/Olympus", label: "MARS" }];
    assert.equal(nextDstChange({ clocks: some, periodsOf, now: at("2026-10-02T12:00:00Z") }), null);
    assert.equal(dstMessage(null), "");
});

test("a clock labeled abbr or not at all gets a name in the sentence", () => {
    assert.equal(clockName({ zone: "Europe/London", label: "abbr" }, "BST"), "BST");
    assert.equal(clockName({ zone: "America/Los_Angeles", label: "" }, "PDT"), "Los Angeles");
    assert.equal(clockName({ zone: "America/New_York", label: "NYC" }, "EDT"), "NYC");
    const change = nextDstChange({
        clocks: [{ zone: "Europe/London", label: "abbr" }, { zone: "America/Los_Angeles", label: "" }],
        periodsOf,
        now: at("2026-10-02T12:00:00Z"),
    });
    assert.equal(dstMessage(change),
        "BST moves to GMT on Sun Oct 25, a week before Los Angeles moves to PST on Sun Nov 1. " +
        "For that week, BST is 7 h ahead of Los Angeles instead of 8.");
});

test("a zone that changes twice in the window keeps its second change", () => {
    const pair = [{ zone: "America/New_York", label: "NYC" }, { zone: "Africa/Casablanca", label: "CAS" }];
    const change = nextDstChange({ clocks: pair, periodsOf, now: at("2027-01-20T00:00:00Z") });
    assert.deepEqual(change.first.labels, ["CAS"]);
    assert.deepEqual(change.then.labels, ["NYC", "CAS"]);
    assert.equal(dstMessage(change),
        // 6 h before, 5 h during and 5 h after (New York's own change):
        // not a gap that's off for a while, so no sentence about it.
        "CAS moves to +00 on Sun Feb 7, five weeks before NYC and CAS move to EDT/+01 on Sun Mar 14.");
});

test("one zone changing twice alone has no gap to describe", () => {
    const change = nextDstChange({
        clocks: [{ zone: "Africa/Casablanca", label: "CAS" }],
        periodsOf,
        now: at("2027-01-20T00:00:00Z"),
    });
    assert.equal(dstMessage(change), "CAS moves to +00 on Sun Feb 7, five weeks before CAS moves to +01 on Sun Mar 14.");
});

test("zones moving together are never the compared pair", () => {
    const three = [
        { zone: "Africa/Casablanca", label: "CAS" },
        { zone: "Africa/El_Aaiun", label: "EH" },
        { zone: "America/New_York", label: "NYC" },
    ];
    const change = nextDstChange({ clocks: three, periodsOf, now: at("2027-01-20T00:00:00Z") });
    assert.equal(dstMessage(change),
        "CAS and EH move to +00 on Sun Feb 7, five weeks before CAS, EH and NYC move to +01/EDT on Sun Mar 14.");
});

test("zones changing at one instant on different days are dated apart", () => {
    const pair = [{ zone: "Europe/London", label: "LON" }, { zone: "America/Nuuk", label: "NUK" }];
    const change = nextDstChange({ clocks: pair, periodsOf, now: at("2027-03-20T00:00:00Z") });
    assert.equal(dstMessage(change), "LON moves to BST on Sun Mar 28 and NUK moves to -01 on Sat Mar 27.");
});

test("the interval comes from the instants, not either zone's calendar", () => {
    const pair = [{ zone: "Asia/Gaza", label: "GZA" }, { zone: "America/Nuuk", label: "NUK" }];
    const change = nextDstChange({ clocks: pair, periodsOf, now: at("2027-03-20T00:00:00Z") });
    assert.equal(dstMessage(change),
        "GZA moves to EEST on Sat Mar 27, a day before NUK moves to -01 on Sat Mar 27. " +
        "Until then, GZA is 5 h ahead of NUK instead of 4.");
});

test("zones usually level say so in full", () => {
    // Two zones at +02 where one moves to +03 a week before the other.
    const level = {
        A: [
            { start: at("2027-03-01T00:00:00Z"), offset: 120, abbr: "A1" },
            { start: at("2027-03-07T00:00:00Z"), offset: 180, abbr: "A2" },
        ],
        B: [
            { start: at("2027-03-01T00:00:00Z"), offset: 120, abbr: "B1" },
            { start: at("2027-03-14T00:00:00Z"), offset: 180, abbr: "B2" },
        ],
    };
    const change = nextDstChange({
        clocks: [{ zone: "A", label: "HEL" }, { zone: "B", label: "CAI" }],
        periodsOf: (zone) => level[zone],
        now: at("2027-03-02T00:00:00Z"),
    });
    assert.equal(dstMessage(change),
        "HEL moves to A2 on Sun Mar 7, a week before CAI moves to B2 on Sun Mar 14. " +
        "For that week, HEL is 1 h ahead of CAI instead of level with CAI.");
});

test("a second change that doesn't restore the gap gets no gap sentence", () => {
    // Sydney moves forward a month before New York moves back, so the gap
    // grows twice instead of returning.
    const pair = [{ zone: "Australia/Sydney", label: "SYD" }, { zone: "America/New_York", label: "NYC" }];
    const change = nextDstChange({ clocks: pair, periodsOf, now: at("2026-09-28T00:00:00Z") });
    assert.equal(dstMessage(change),
        "SYD moves to AEDT on Sun Oct 4, 29 days before NYC moves to EST on Sun Nov 1.");
});

test("days are named in the changing zone's own time", () => {
    // 01:00 UTC on Oct 25 is still Saturday in Los Angeles, but it's Sunday
    // in London, where the clocks change.
    assert.equal(formatDay(at("2026-10-25T01:00:00Z"), 60), "Sun Oct 25");
    assert.equal(formatDay(at("2026-10-25T01:00:00Z"), -420), "Sat Oct 24");
});
