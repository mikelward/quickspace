// Tests for tray.mjs.
import { test } from "node:test";
import assert from "node:assert/strict";
import { shownItems, clickAction } from "./tray.mjs";

const PASSIVE = 0;
const ACTIVE = 1;
const ATTENTION = 2;

test("passive items are hidden, the rest keep their order", () => {
    const items = [{ id: "a", status: ACTIVE }, { id: "b", status: PASSIVE }, { id: "c", status: ATTENTION }];
    assert.deepEqual(shownItems(items, PASSIVE).map(i => i.id), ["a", "c"]);
    assert.deepEqual(shownItems([], PASSIVE), []);
});

test("a left or right click opens the menu, as §7.4 says", () => {
    const item = { hasMenu: true, onlyMenu: false };
    assert.equal(clickAction("left", item), "menu");
    assert.equal(clickAction("right", item), "menu");
});

test("a middle click activates the app", () => {
    assert.equal(clickAction("middle", { hasMenu: true, onlyMenu: false }), "activate");
});

test("without a menu, a left click activates and a right click is the secondary action", () => {
    const item = { hasMenu: false, onlyMenu: false };
    assert.equal(clickAction("left", item), "activate");
    assert.equal(clickAction("right", item), "secondary");
});

test("other buttons do nothing", () => {
    assert.equal(clickAction("back", { hasMenu: true, onlyMenu: false }), null);
});
