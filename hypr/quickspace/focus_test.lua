-- Tests for focus.lua (SPEC.md §14.1). Plain Lua (5.4 or 5.5):
-- `lua hypr/quickspace/focus_test.lua` from the repo root. focus.lua runs
-- against a stub of the Hyprland `hl` API that records its rules, handlers
-- and dispatches, with a clock the tests drive.

local dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"

local failures, passed = 0, 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failures = failures + 1
        io.stderr:write("FAIL " .. name .. "\n  " .. tostring(err) .. "\n")
    end
end

local function eq(got, want, what)
    if got ~= want then
        error(string.format("%s: got %s, want %s", what or "value", tostring(got), tostring(want)), 2)
    end
end

-- Hyprland's focus reasons, as focus.lua reads them.
local FFM, KEYBIND, CLICK, WORKSPACE = 1 << 0, 1 << 1, (1 << 4) | (1 << 5), 1 << 11
local UNMAP_TILING = 1 << 13

local S -- what the stub recorded
local now

local function load(opts)
    S = { rules = {}, handlers = {}, dispatched = {}, active = nil }
    now = 1000
    _G.quickspace_focus = nil
    _G.hl = {
        window_rule = function(r) table.insert(S.rules, r) end,
        on = function(ev, fn) S.handlers[ev] = fn end,
        dispatch = function(d) table.insert(S.dispatched, d) end,
        get_active_window = function() return S.active end,
        dsp = {
            focus = function(a) return { dsp = "focus", args = a } end,
            event = function(e) return { dsp = "event", args = e } end,
        },
    }
    local m = dofile(dir .. "focus.lua")
    m.clock = function() return now end
    m.setup(opts)
    return m
end

local next_address = 0
local function window(class, pid)
    next_address = next_address + 1
    return { class = class, initial_class = class, pid = pid or next_address, address = string.format("0x%x", next_address) }
end

local function fire(ev, ...)
    S.dispatched = {}
    S.handlers[ev](...)
    return S.dispatched
end

-- Focus lands on w: the guard's dispatch, then Hyprland's window.active.
local function focused(w, reason)
    fire("window.active", w, reason)
end

local function is_focus(d, w)
    return d and d.dsp == "focus" and d.args.window == "address:" .. w.address
end

local function is_attention(d, w)
    return d and d.dsp == "event" and d.args == "quickspace-attention>>" .. w.address
end

test("every window opens unfocused, so a failing guard never steals", function()
    load()
    eq(#S.rules, 1, "rules")
    eq(S.rules[1].no_initial_focus, true, "no_initial_focus")
    eq(S.rules[1].match.class, ".*", "matches every window")
end)

test("setup publishes the module for quickspace launch", function()
    local m = load()
    eq(_G.quickspace_focus, m, "quickspace_focus")
end)

test("setup rejects an unknown or bad option", function()
    eq(pcall(load, { grant_secs = 5 }), false, "typo")
    eq(pcall(load, { grant_seconds = 0 }), false, "zero")
    eq(pcall(load, { grant_seconds = "10" }), false, "string")
end)

test("ids normalize: case, .desktop and reverse-DNS prefixes", function()
    local m = load()
    eq(m.normalize("org.gnome.Nautilus"), "nautilus")
    eq(m.normalize("Nautilus"), "nautilus")
    eq(m.normalize("nautilus.desktop"), "nautilus")
    eq(m.normalize("kitty"), "kitty")
    eq(m.normalize(""), nil)
    eq(m.normalize(nil), nil)
end)

test("a new window from the app you're in takes focus", function()
    load()
    local kitty = window("kitty", 50)
    focused(kitty, FFM)
    local dialog = window("kitty", 50)
    local d = fire("window.open", dialog)
    eq(#d, 1, "dispatches")
    eq(is_focus(d[1], dialog), true, "focused")
end)

test("the same app by class counts even from another process", function()
    load()
    focused(window("org.gnome.Nautilus", 60), CLICK)
    local second = window("org.gnome.Nautilus", 61)
    eq(is_focus(fire("window.open", second)[1], second), true, "focused")
end)

test("a window from another app is left unfocused and announced", function()
    load()
    focused(window("kitty"), FFM)
    local popup = window("updater")
    local d = fire("window.open", popup)
    eq(#d, 1, "dispatches")
    eq(is_attention(d[1], popup), true, "announced")
end)

test("the first window of a launched app takes focus", function()
    local m = load()
    focused(window("kitty"), FFM)
    m.grant("firefox")
    local ff = window("firefox")
    eq(is_focus(fire("window.open", ff)[1], ff), true, "focused")
end)

test("a grant is used once", function()
    local m = load()
    focused(window("kitty"), FFM)
    m.grant("firefox")
    fire("window.open", window("firefox"))
    local second = window("firefox", 999)
    -- The grant went to the first window. Until focus actually lands there
    -- (window.active), kitty is still the app you're in, so a second firefox
    -- window is another app's.
    eq(is_attention(fire("window.open", second)[1], second), true, "second window announced")
end)

test("a grant expires after grant_seconds", function()
    local m = load()
    focused(window("kitty"), FFM)
    m.grant("firefox")
    now = now + 11
    local ff = window("firefox")
    eq(is_attention(fire("window.open", ff)[1], ff), true, "late window announced")
    m.grant("chromium")
    now = now + 10
    local cr = window("chromium")
    eq(is_focus(fire("window.open", cr)[1], cr), true, "at exactly 10 s it still holds")
end)

test("grant_seconds is an option", function()
    local m = load({ grant_seconds = 3 })
    focused(window("kitty"), FFM)
    m.grant("firefox")
    now = now + 4
    local ff = window("firefox")
    eq(is_attention(fire("window.open", ff)[1], ff), true, "announced")
end)

test("a key press cancels the grant; a release doesn't", function()
    local m = load()
    focused(window("kitty"), FFM)
    m.grant("firefox")
    fire("input.keyboard.key", 36, 5000, 0)
    eq(#m.grants(), 1, "release keeps it")
    fire("input.keyboard.key", 36, 5001, 1)
    eq(#m.grants(), 0, "press cancels it")
    local ff = window("firefox")
    eq(is_attention(fire("window.open", ff)[1], ff), true, "announced")
end)

test("moving focus cancels the grant, whatever moved it", function()
    for _, reason in ipairs({ FFM, KEYBIND, CLICK, WORKSPACE }) do
        local m = load()
        focused(window("kitty"), FFM)
        m.grant("firefox")
        focused(window("code"), reason)
        eq(#m.grants(), 0, "reason " .. reason)
    end
end)

test("focus returning after a window closes doesn't cancel", function()
    local m = load()
    focused(window("kitty"), FFM)
    m.grant("firefox")
    focused(window("code"), UNMAP_TILING)
    eq(#m.grants(), 1, "grants")
end)

test("the guard's own focusing doesn't cancel other grants", function()
    local m = load()
    focused(window("kitty"), FFM)
    m.grant("firefox")
    m.grant("chromium")
    -- Hyprland fires window.active synchronously from the focus dispatch.
    hl.dispatch = function(d)
        table.insert(S.dispatched, d)
        if d.dsp == "focus" then
            S.handlers["window.active"](nil, 1 << 2)
        end
    end
    fire("window.open", window("firefox"))
    eq(#m.grants(), 1, "chromium's grant survives")
end)

test("a launched app activating a window it already had takes focus", function()
    local m = load()
    focused(window("kitty"), FFM)
    local nautilus = window("org.gnome.Nautilus")
    m.grant("nautilus")
    eq(is_focus(fire("window.urgent", nautilus)[1], nautilus), true, "focused")
end)

test("any other activation stays marked (Hyprland marks it urgent)", function()
    load()
    focused(window("kitty"), FFM)
    eq(#fire("window.urgent", window("chromium")), 0, "no focus")
end)

test("grant rejects an empty id", function()
    local m = load()
    eq(pcall(m.grant, ""), false, "empty")
    eq(pcall(m.grant, nil), false, "nil")
end)

test("with nothing focused yet, only granted windows take focus", function()
    local m = load()
    local first = window("kitty")
    eq(is_attention(fire("window.open", first)[1], first), true, "announced")
    m.grant("kitty")
    local second = window("kitty")
    eq(is_focus(fire("window.open", second)[1], second), true, "focused")
end)

test("the window focused at load counts as the app you're in", function()
    S = nil
    local kitty = window("kitty", 70)
    _G.hl = nil
    load() -- sets up the stub, then:
    S.active = kitty
    local m = dofile(dir .. "focus.lua")
    m.clock = function() return now end
    m.setup({})
    local dialog = window("kitty", 70)
    eq(is_focus(fire("window.open", dialog)[1], dialog), true, "focused")
end)

io.write(string.format("focus_test.lua: %d passed, %d failed\n", passed, failures))
os.exit(failures == 0 and 0 or 1)
