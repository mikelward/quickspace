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

-- Hyprland's focus reasons (eFocusReason, a plain enum).
local FFM, KEYBIND, DISPATCH, CLICK, WORKSPACE = 1, 2, 3, 5, 11
local UNMAP_TILING, UNMAP_FLOATING = 13, 14

local S -- what the stub recorded
local now

local function load(opts)
    S = { rules = {}, handlers = {}, dispatched = {}, notified = {}, active = nil }
    now = 1000
    _G.quickspace_focus = nil
    _G.hl = {
        window_rule = function(r) table.insert(S.rules, r) end,
        on = function(ev, fn) S.handlers[ev] = fn end,
        dispatch = function(d) table.insert(S.dispatched, d) end,
        get_active_window = function() return S.active end,
        notification = {
            create = function(n) table.insert(S.notified, n) end,
        },
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
    eq(pcall(load, { notify = "yes" }), false, "notify string")
    eq(pcall(load, { grant_seconds = 0 / 0 }), false, "grant_seconds NaN")
    eq(pcall(load, { prompt_seconds = 0 / 0 }), false, "prompt_seconds NaN")
    eq(pcall(load, { grant_seconds = math.huge }), false, "grant_seconds infinite")
    eq(pcall(load, { prompt_classes = "hyprpolkitagent" }), false, "prompt_classes string")
    eq(pcall(load, { portal_classes = { "" } }), false, "portal_classes empty class")
    eq(pcall(load, { prompt_classes = { 1 } }), false, "prompt_classes number")
    eq(pcall(load, { prompt_classes = { agent = "hyprpolkitagent" } }), false, "prompt_classes keyed")
    eq(pcall(load, { prompt_classes = { "a", nil, "c" } }), false, "prompt_classes sparse")
    local mutated = { "a", "b", "c", "d" }
    mutated[2] = nil
    mutated[6] = "e" -- four keys, and `#` may well say 4 too
    eq(pcall(load, { prompt_classes = mutated }), false, "prompt_classes mutated into gaps")
end)

test("ids normalize case and .desktop, and keep their namespace", function()
    local m = load()
    eq(m.normalize("org.gnome.Nautilus"), "org.gnome.nautilus")
    eq(m.normalize("Nautilus"), "nautilus")
    eq(m.normalize("nautilus.desktop"), "nautilus")
    eq(m.normalize(""), nil)
    eq(m.normalize(nil), nil)
end)

test("a bare name matches a qualified id; two namespaces don't", function()
    local m = load()
    eq(m.same_id("nautilus", "org.gnome.nautilus"), true, "bare to qualified")
    eq(m.same_id("org.gnome.nautilus", "nautilus"), true, "qualified to bare")
    eq(m.same_id("org.example.chat", "com.example.chat"), false, "namespaces")
    eq(m.same_id("kitty", "foot"), false, "different names")
end)

test("a grant for one namespace isn't used by another", function()
    local m = load()
    focused(window("kitty"), FFM)
    m.grant("org.example.Chat")
    local other = window("com.example.Chat")
    eq(is_attention(fire("window.open", other)[1], other), true, "announced")
    local ours = window("org.example.Chat")
    eq(is_focus(fire("window.open", ours)[1], ours), true, "focused")
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

test("a grant is used up even by the app you're in", function()
    local m = load()
    focused(window("kitty", 50), FFM)
    m.grant("kitty")
    fire("window.open", window("kitty", 50))
    eq(#m.grants(), 0, "used")
end)

test("a polkit prompt right after a key press takes focus", function()
    load()
    focused(window("kitty"), FFM)
    fire("input.keyboard.key", 28, 5000, 1) -- Enter on a pkexec line
    now = now + 1
    local prompt = window("hyprpolkitagent")
    eq(is_focus(fire("window.open", prompt)[1], prompt), true, "focused")
end)

test("a polkit prompt long after the last key press waits", function()
    load()
    focused(window("kitty"), FFM)
    fire("input.keyboard.key", 28, 5000, 1)
    now = now + 30 -- sleep 30; pkexec ...
    local prompt = window("hyprpolkitagent")
    eq(is_attention(fire("window.open", prompt)[1], prompt), true, "waits")
end)

test("a recent key press doesn't let other windows in", function()
    load()
    focused(window("kitty"), FFM)
    fire("input.keyboard.key", 28, 5000, 1)
    local popup = window("updater")
    eq(is_attention(fire("window.open", popup)[1], popup), true, "waits")
end)

-- A fake /proc: stat files naming each process's parent.
local function fake_proc(parents)
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute("mkdir -p '" .. root .. "'"))
    for pid, ppid in pairs(parents) do
        assert(os.execute("mkdir -p '" .. root .. "/" .. pid .. "'"))
        local f = assert(io.open(root .. "/" .. pid .. "/stat", "w"))
        -- A command name with a space and a ')' in it, as a real one can have.
        f:write(pid .. " (my (app) x) S " .. ppid .. " 1 1 0\n")
        f:close()
    end
    return root
end

test("a window from a command the shell ran takes that shell's grant", function()
    local m = load()
    m.proc = fake_proc({ [300] = 200, [200] = 150 })
    focused(window("kitty", 100), FFM)
    m.grant("my-script", 150) -- from the preexec hook in shell 150
    local w = window("some-gui", 300)
    eq(is_focus(fire("window.open", w)[1], w), true, "focused")
    eq(#m.grants(), 0, "the grant is used up")
end)

test("a shell's grant is used even by a window of the app you're in", function()
    local m = load()
    m.proc = fake_proc({ [300] = 150 })
    focused(window("kitty", 100), FFM)
    m.grant("my-script", 150)
    fire("window.open", window("kitty", 300)) -- same app as the focused one
    eq(#m.grants(), 0, "used up")
end)

test("ancestry needs a grant from an ancestor", function()
    local m = load()
    m.proc = fake_proc({ [300] = 100 })
    focused(window("kitty", 100), FFM)
    local w = window("some-gui", 300)
    eq(is_attention(fire("window.open", w)[1], w), true, "no grant: waits")
    m.grant("firefox") -- a launch grant names no process
    local w2 = window("some-gui", 300)
    eq(is_attention(fire("window.open", w2)[1], w2), true, "launch grant: waits")
    eq(#m.grants(), 1, "the launch grant stays")
end)

test("a window from elsewhere doesn't take a shell's grant", function()
    local m = load()
    m.proc = fake_proc({ [300] = 250, [250] = 1 })
    focused(window("kitty", 100), FFM)
    m.grant("my-script", 150)
    local w = window("some-gui", 300)
    eq(is_attention(fire("window.open", w)[1], w), true, "waits")
    eq(#m.grants(), 1, "the grant stays")
end)

test("an unreadable /proc means no ancestry", function()
    local m = load()
    m.proc = "/nonexistent-proc"
    focused(window("kitty", 100), FFM)
    m.grant("my-script", 150)
    local w = window("some-gui", 300)
    eq(is_attention(fire("window.open", w)[1], w), true, "waits")
end)

test("grant rejects a bad process id", function()
    local m = load()
    eq(pcall(m.grant, "x", "150"), false, "string")
    eq(pcall(m.grant, "x", 1), false, "init")
    eq(pcall(m.grant, "x", 1.5), false, "fraction")
end)

test("a portal file chooser takes focus from the app you're in", function()
    load()
    focused(window("google-chrome"), CLICK)
    local chooser = window("xdg-desktop-portal-gtk")
    eq(is_focus(fire("window.open", chooser)[1], chooser), true, "focused")
end)

test("a portal dialog with nothing focused waits", function()
    load()
    local chooser = window("xdg-desktop-portal-gtk")
    eq(is_attention(fire("window.open", chooser)[1], chooser), true, "waits")
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

test("a wildcard grant is used by the next app's window, once", function()
    local m = load()
    focused(window("kitty"), FFM)
    m.grant("*")
    local chrome = window("google-chrome")
    eq(is_focus(fire("window.open", chrome)[1], chrome), true, "focused")
    local second = window("updater")
    eq(is_attention(fire("window.open", second)[1], second), true, "used up")
end)

test("a wildcard grant covers an activation too", function()
    local m = load()
    focused(window("kitty"), FFM)
    m.grant("*")
    local chrome = window("google-chrome")
    eq(is_focus(fire("window.urgent", chrome)[1], chrome), true, "focused")
end)

test("a named grant is used before a wildcard", function()
    local m = load()
    focused(window("kitty"), FFM)
    m.grant("*")
    m.grant("firefox")
    fire("window.open", window("firefox"))
    eq(#m.grants(), 1, "one left")
    eq(m.grants()[1], "*", "the wildcard")
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

test("closing a window moves on, whichever window focus passes to", function()
    for _, reason in ipairs({ UNMAP_TILING, UNMAP_FLOATING }) do
        local m = load()
        focused(window("kitty"), FFM)
        m.grant("firefox")
        focused(window("code"), reason)
        eq(#m.grants(), 0, "reason " .. reason)
    end
end)

test("focus coming back to the window you were in doesn't cancel", function()
    local m = load()
    local kitty = window("kitty")
    focused(kitty, FFM)
    m.grant("firefox")
    -- The launcher closing: Hyprland refocuses the last window.
    focused(kitty, FFM)
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
            S.handlers["window.active"](nil, DISPATCH)
        end
    end
    fire("window.open", window("firefox"))
    eq(#m.grants(), 1, "chromium's grant survives")
end)

test("focusing a window no grant asked for cancels the grants", function()
    for _, class in ipairs({ "kitty", "xdg-desktop-portal-gtk", "hyprpolkitagent" }) do
        local m = load()
        focused(window("kitty", 50), FFM)
        fire("input.keyboard.key", 28, 5000, 1) -- lets the polkit prompt in
        m.grant("firefox") -- a slow app launched after that key press
        local w = window(class)
        eq(is_focus(fire("window.open", w)[1], w), true, class .. " focused")
        eq(#m.grants(), 0, class .. " cancels firefox's grant")
    end
end)

test("Super+U cancels the grants", function()
    local m = load()
    focused(window("kitty"), FFM)
    fire("window.open", window("updater"))
    m.grant("firefox")
    eq(m.focus_attention(), true, "focused")
    eq(#m.grants(), 0, "canceled")
end)

test("focus on nothing forgets the app you were in", function()
    load()
    focused(window("kitty", 80), FFM)
    focused(nil, WORKSPACE)
    local later = window("kitty", 81)
    eq(is_attention(fire("window.open", later)[1], later), true, "announced")
end)

test("a focus dispatch that throws still clears the guard's own-focus flag", function()
    local m = load()
    focused(window("kitty"), FFM)
    m.grant("firefox")
    m.grant("chromium")
    hl.dsp.focus = function() error("window gone") end
    eq(pcall(fire, "window.open", window("firefox")), false, "the error propagates")
    -- A later focus change is the user moving on, so it cancels grants.
    focused(window("code"), FFM)
    eq(#m.grants(), 0, "grants canceled")
end)

test("a window with no address is neither focused nor announced", function()
    local m = load()
    focused(window("kitty"), FFM)
    local gone = window("kitty")
    gone.address = nil
    eq(#fire("window.open", gone), 0, "same app, gone")
    m.grant("firefox")
    local gone2 = window("firefox")
    gone2.address = nil
    eq(#fire("window.open", gone2), 0, "granted, gone")
    eq(#fire("window.open", (function() local w = window("other"); w.address = nil; return w end)()), 0, "other, gone")
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

test("Super+U goes to the latest waiting window, then falls back", function()
    local m = load()
    focused(window("kitty"), FFM)
    local a, b = window("updater"), window("chat")
    fire("window.open", a)
    fire("window.open", b)
    S.dispatched = {}
    eq(m.focus_attention(), true, "first")
    eq(is_focus(S.dispatched[1], b), true, "latest first")
    S.dispatched = {}
    eq(m.focus_attention(), true, "second")
    eq(is_focus(S.dispatched[1], a), true, "then the older one")
    eq(m.focus_attention(), false, "none left")
end)

test("an activation without a grant waits with the rest", function()
    local m = load()
    focused(window("kitty"), FFM)
    local popup, chat = window("updater"), window("chromium")
    fire("window.open", popup)
    fire("window.urgent", chat)
    S.dispatched = {}
    m.focus_attention()
    eq(is_focus(S.dispatched[1], chat), true, "the activation is the latest")
end)

test("a waiting window you reach another way, or that closes, stops waiting", function()
    local m = load()
    focused(window("kitty"), FFM)
    local a, b = window("updater"), window("chat")
    fire("window.open", a)
    fire("window.open", b)
    focused(b, CLICK)
    fire("window.close", a)
    eq(m.focus_attention(), false, "nothing waiting")
end)

test("a waiting window shows a notification unless notify is off", function()
    load()
    focused(window("kitty"), FFM)
    fire("window.open", window("updater"))
    eq(#S.notified, 1, "notified")
    eq(S.notified[1].text:find("updater", 1, true) ~= nil, true, "names the app")
    load({ notify = false })
    focused(window("kitty"), FFM)
    fire("window.open", window("updater"))
    eq(#S.notified, 0, "silent")
end)

io.write(string.format("focus_test.lua: %d passed, %d failed\n", passed, failures))
os.exit(failures == 0 and 0 or 1)
