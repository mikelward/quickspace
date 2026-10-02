// Tests for appearance.mjs.
import { test } from "node:test";
import assert from "node:assert/strict";
import { schemeIsDark, heardScheme } from "./appearance.mjs";

test("gsettings get output names the scheme", () => {
    assert.equal(schemeIsDark("'prefer-dark'\n"), true);
    assert.equal(schemeIsDark("'prefer-light'"), false);
    assert.equal(schemeIsDark("'default'"), false);
});

test("gsettings monitor output names the key first", () => {
    assert.equal(schemeIsDark("color-scheme: 'prefer-dark'"), true);
    assert.equal(schemeIsDark("color-scheme: 'prefer-light'"), false);
});

test("anything else keeps the current palette", () => {
    assert.equal(schemeIsDark(""), null);
    assert.equal(schemeIsDark("gtk-theme: 'adw-gtk3-dark'"), null);
    assert.equal(schemeIsDark("No such schema “org.gnome.desktop.interface”"), null);
    assert.equal(schemeIsDark(undefined), null);
});

test("the startup read sets the scheme until the monitor reports a change", () => {
    let s = { dark: true, changed: false };
    s = heardScheme(s, "'prefer-light'", false);
    assert.deepEqual(s, { dark: false, changed: false });
    s = heardScheme(s, "color-scheme: 'prefer-dark'", true);
    assert.deepEqual(s, { dark: true, changed: true });
});

test("a startup read that finishes after a change doesn't undo it", () => {
    let s = { dark: true, changed: false };
    s = heardScheme(s, "color-scheme: 'prefer-light'", true);
    s = heardScheme(s, "'prefer-dark'", false);
    assert.deepEqual(s, { dark: false, changed: true });
});

test("a line that isn't a scheme changes nothing", () => {
    const s = { dark: true, changed: false };
    assert.equal(heardScheme(s, "", true), s);
});
