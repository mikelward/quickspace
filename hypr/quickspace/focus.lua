-- quickspace focus guard for Hyprland 0.56+ (SPEC.md §14).
--
-- Nothing steals the keyboard. A catch-all `no_initial_focus` rule opens
-- every window unfocused, and the guard then focuses the ones you asked for:
--
--   * a new window from the app you're in (a dialog, a second window);
--   * the first window of an app you just launched, or that app activating
--     a window it already had, while its one-shot launch grant holds.
--
-- Anything else stays where it opened, dimmed, and is announced on the event
-- socket as `custom>>quickspace-attention>>ADDRESS` for the shell to mark.
-- If the guard itself fails, windows still open unfocused: the failure mode
-- is "never steals", not "always steals".
--
-- Usage, from hyprland.lua:
--
--   local focus = dofile(os.getenv("HOME") .. "/.config/hypr/quickspace/focus.lua")
--   focus.setup({})
--
-- setup() also publishes the module as the global `quickspace_focus`, so
-- `quickspace launch` can record a grant with
-- `hyprctl eval 'quickspace_focus.grant("APP")'`.
--
-- Known gaps, from SPEC.md §14.3: Lua sees key presses but not pointer
-- buttons, so a click inside the window you're already in doesn't cancel a
-- grant; a grant names an app by window class, not yet through desktop
-- entries; and a window that asked for fullscreen as it opened comes up
-- tiled, since Hyprland skips that request for a window it doesn't focus.

local M = {}

M.defaults = {
    -- How long a launch grant holds, in seconds.
    grant_seconds = 10,
}

-- Hyprland's focus reasons (desktop/state/FocusState.hpp). Focus that comes
-- back after a window closes isn't you moving on.
local REASON_UNMAP = (1 << 13) | (1 << 14) | (1 << 15)
local REASON_NEW_WINDOW = 1 << 16

local state = {
    opts = nil,
    grants = {}, -- { app = normalized id, at = seconds }
    active = nil, -- { class, pid } of the focused window
}

-- The clock is a field so the tests can drive it.
M.clock = os.time

-- An app id as a grant or a window class might spell it, normalized:
-- lowercase, without a `.desktop` suffix, and without a reverse-DNS prefix,
-- so `org.gnome.Nautilus`, `Nautilus` and `nautilus.desktop` all match.
local function normalize(id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    id = id:lower():gsub("%.desktop$", "")
    return id:match("([^.]+)$")
end
M.normalize = normalize

-- Field reads on Hyprland objects can fail for windows that are going away;
-- a failed read is treated as absent, as in layout.lua.
local function field(obj, key)
    local ok, v = pcall(function()
        return obj[key]
    end)
    return ok and v or nil
end

local function app_of(w)
    return normalize(field(w, "class")) or normalize(field(w, "initial_class"))
end

local function expire()
    local now = M.clock()
    local keep = {}
    for _, g in ipairs(state.grants) do
        if now - g.at <= state.opts.grant_seconds then
            table.insert(keep, g)
        end
    end
    state.grants = keep
end

-- Uses up the grant for w's app, if one holds.
local function take_grant(w)
    expire()
    local app = app_of(w)
    for i, g in ipairs(state.grants) do
        if g.app == app then
            table.remove(state.grants, i)
            return true
        end
    end
    return false
end

-- Anything you do after launching cancels every grant: a slow app mustn't
-- take focus from whatever you moved on to.
local function cancel_grants()
    state.grants = {}
end

local function same_app_as_active(w)
    local active = state.active
    if not active then
        return false
    end
    local pid = field(w, "pid")
    if pid and active.pid and pid == active.pid then
        return true
    end
    local app = app_of(w)
    return app ~= nil and app == active.app
end

local focusing = false

local function focus(w)
    focusing = true
    local ok, err = pcall(hl.dispatch, hl.dsp.focus({ window = "address:" .. field(w, "address") }))
    focusing = false
    if not ok then
        error(err, 0)
    end
end

local function announce(w)
    hl.dispatch(hl.dsp.event("quickspace-attention>>" .. tostring(field(w, "address"))))
end

-- A new window: focus it if it's yours, else leave it and mark it.
function M.on_open(w)
    if same_app_as_active(w) or take_grant(w) then
        focus(w)
    else
        announce(w)
    end
end

-- An existing window asked to be activated. Hyprland has already marked it
-- urgent (misc:focus_on_activate is off); a launch grant lets it through.
function M.on_urgent(w)
    if take_grant(w) then
        focus(w)
    end
end

function M.on_active(w, reason)
    reason = reason or 0
    if w then
        state.active = { pid = field(w, "pid"), app = app_of(w) }
    end
    -- The guard's own focusing is flagged while it dispatches; focus from
    -- anything else (the pointer, a key binding, a click, a workspace
    -- switch) is you moving on.
    if focusing or reason & (REASON_UNMAP | REASON_NEW_WINDOW) ~= 0 then
        return
    end
    cancel_grants()
end

function M.on_key(_, _, key_state)
    -- 1 is a press; releases (including the one after the launch key) don't
    -- count as moving on.
    if key_state == 1 then
        cancel_grants()
    end
end

-- Records a one-shot grant for app, from `quickspace launch` or a
-- notification click.
function M.grant(app)
    local id = normalize(app)
    if not id then
        error("quickspace_focus.grant: expected an app id, got " .. tostring(app), 2)
    end
    expire()
    table.insert(state.grants, { app = id, at = M.clock() })
end

-- For the tests and `quickspace doctor`.
function M.grants()
    expire()
    local out = {}
    for _, g in ipairs(state.grants) do
        table.insert(out, g.app)
    end
    return out
end

function M.setup(opts)
    opts = opts or {}
    local merged = {}
    for k, v in pairs(M.defaults) do
        merged[k] = v
    end
    for k, v in pairs(opts) do
        if M.defaults[k] == nil then
            error("quickspace focus.setup: " .. tostring(k) .. " is not an option", 2)
        end
        if type(v) ~= type(M.defaults[k]) or (type(v) == "number" and v <= 0) then
            error("quickspace focus.setup: " .. tostring(k) .. " must be a positive number", 2)
        end
        merged[k] = v
    end
    state.opts = merged
    state.grants = {}
    state.active = nil
    local w = hl.get_active_window()
    if w then
        state.active = { pid = field(w, "pid"), app = app_of(w) }
    end

    hl.window_rule({ name = "quickspace-focus-guard", match = { class = ".*" }, no_initial_focus = true })
    hl.on("window.open", M.on_open)
    hl.on("window.urgent", M.on_urgent)
    hl.on("window.active", M.on_active)
    hl.on("input.keyboard.key", M.on_key)
    _G.quickspace_focus = M
    return M
end

return M
