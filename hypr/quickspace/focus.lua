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
-- Lua can't set Hyprland's urgent flag, so the guard also keeps these
-- windows itself: `quickspace_focus.focus_attention()` (Super+U) goes to the
-- latest, and until the shell marks them (TODO.md), each shows a Hyprland
-- notification (`notify`).
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
-- tiled, since Hyprland skips that request for a window it doesn't focus
-- and Lua can't see the request to re-apply it (TODO.md).

local M = {}

M.defaults = {
    -- How long a launch grant holds, in seconds.
    grant_seconds = 10,
    -- Show a Hyprland notification for each window left waiting, while no
    -- shell consumes quickspace-attention.
    notify = true,
    -- Window classes of polkit agents. Their password prompt takes focus
    -- when you pressed a key in the last prompt_seconds, since that's you
    -- running `pkexec` or pressing a button that asks (SPEC.md §14.1);
    -- otherwise it waits like any other window. The Quickshell agent (M3)
    -- replaces this.
    prompt_classes = {
        "hyprpolkitagent",
        "polkit-gnome-authentication-agent-1",
        "org.kde.polkit-kde-authentication-agent-1",
    },
    prompt_seconds = 2,
    -- Window classes of xdg-desktop-portal backends. Their dialogs (the file
    -- chooser) are for the app you're in (SPEC.md §14.1), but they run in the
    -- backend's process, and Lua can't see the dialog's parent window. So one
    -- takes focus whenever a window is focused.
    portal_classes = {
        "xdg-desktop-portal-gtk",
        "xdg-desktop-portal-kde",
        "xdg-desktop-portal-gnome",
    },
}

-- Hyprland's focus reason for a window focused as it opens
-- (eFocusReason in desktop/state/FocusState.hpp: a plain enum, not flags).
local REASON_NEW_WINDOW = 16

local state = {
    opts = nil,
    grants = {}, -- { app = normalized id, at = seconds, pid = requester or nil }
    active = nil, -- { address, pid, app } of the focused window
    waiting = {}, -- addresses of windows left unfocused, oldest first
}

-- The clock is a field so the tests can drive it.
M.clock = os.time
-- Where process parents are read from; a field so the tests can fake it.
M.proc = "/proc"

-- An app id as a grant or a window class might spell it, normalized:
-- lowercase and without a `.desktop` suffix.
local function normalize(id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    id = id:lower():gsub("%.desktop$", "")
    return id ~= "" and id or nil
end
M.normalize = normalize

-- Whether two normalized ids name the same app. Qualified ids must match in
-- full, so `org.example.chat` and `com.example.chat` stay apart; a bare name
-- matches the last part of a qualified one, so `nautilus` (a command's
-- basename) matches `org.gnome.nautilus`.
local function same_id(a, b)
    if a == nil or b == nil then
        return false
    end
    if a == b then
        return true
    end
    local a_bare, b_bare = not a:find(".", 1, true), not b:find(".", 1, true)
    if a_bare == b_bare then
        return false
    end
    local bare, qualified = a, b
    if b_bare then
        bare, qualified = b, a
    end
    return qualified:match("([^.]+)$") == bare
end
M.same_id = same_id

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

local function active_record(w)
    return { address = field(w, "address"), pid = field(w, "pid"), app = app_of(w) }
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
        if same_id(g.app, app) then
            table.remove(state.grants, i)
            return true
        end
    end
    return false
end

-- A process's parent, from /proc/PID/stat, or nil if it can't be read (the
-- process is gone, or /proc isn't there). The command name in the second
-- field may hold spaces and parentheses, so the parent pid is read after
-- the last ')'.
local function parent_of(pid)
    local f = io.open(M.proc .. "/" .. pid .. "/stat", "r")
    if not f then
        return nil -- a process that has exited has no parent to walk
    end
    local stat = f:read("l")
    f:close()
    local ppid = stat and stat:match("^.*%)%s+%S+%s+(%d+)")
    return ppid and tonumber(ppid)
end

-- Whether pid descends from ancestor, walking at most 64 parents.
local function descends(pid, ancestor)
    for _ = 1, 64 do
        pid = parent_of(pid)
        if not pid or pid <= 1 then
            return false
        end
        if pid == ancestor then
            return true
        end
    end
    return false
end

-- The process-ancestry fallback (SPEC.md §14.3), for a command whose name
-- matches no window class, like a script that opens a window. Only a grant
-- that names the process that asked for it (the shell a terminal command
-- ran in) qualifies, and only for a window whose process descends from
-- that one; a launch grant names no process, so it can't be used this way.
local function take_grant_by_ancestry(w)
    expire()
    local pid = field(w, "pid")
    if not pid then
        return false
    end
    for i, g in ipairs(state.grants) do
        if g.pid and descends(pid, g.pid) then
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
    return same_id(app, active.app)
end

local focusing = false

local function focus_address(address)
    -- The flag must drop even if building or sending the dispatch throws, or
    -- every later focus change would look like the guard's own.
    focusing = true
    local ok, err = pcall(function()
        hl.dispatch(hl.dsp.focus({ window = "address:" .. address }))
    end)
    focusing = false
    if not ok then
        error(err, 0)
    end
end

local function focus(w)
    local address = field(w, "address")
    if not address then
        return -- a window that is going away has no address, and needs no focus
    end
    focus_address(address)
end

local function forget(address)
    for i = #state.waiting, 1, -1 do
        if state.waiting[i] == address then
            table.remove(state.waiting, i)
        end
    end
end

local function wait(w)
    local address = field(w, "address")
    if not address then
        return nil -- a window that is going away has nothing to mark
    end
    forget(address)
    table.insert(state.waiting, address)
    return address
end

local function announce(w)
    local address = wait(w)
    if not address then
        return
    end
    hl.dispatch(hl.dsp.event("quickspace-attention>>" .. address))
    if state.opts.notify then
        hl.notification.create({
            text = (field(w, "class") or "A window") .. " is waiting: Super+U to go there",
            duration = 5000,
            icon = "info",
        })
    end
end

local function class_in(w, classes)
    local app = app_of(w)
    for _, class in ipairs(classes) do
        if same_id(normalize(class), app) then
            return true
        end
    end
    return false
end

-- A polkit agent's prompt right after a key press (§14.1). Lua sees key
-- presses but not clicks, and not which process asked, so this is the
-- keyboard half of the rule: a prompt after a click waits for Super+U.
local function prompt_you_asked_for(w)
    if not state.last_key or M.clock() - state.last_key > state.opts.prompt_seconds then
        return false
    end
    return class_in(w, state.opts.prompt_classes)
end

-- A portal's file chooser opens for the app you're using. Lua can't see a
-- dialog's parent, so any portal dialog counts as the active app's.
local function portal_dialog_for_active(w)
    return state.active ~= nil and class_in(w, state.opts.portal_classes)
end

-- A new window: focus it if it's yours, else leave it and mark it.
function M.on_open(w)
    -- Grants first, so one is used up even when the window is from the app
    -- you are in (a second terminal from a terminal, or a script's window).
    if take_grant(w) or take_grant_by_ancestry(w) then
        focus(w)
    elseif same_app_as_active(w) or portal_dialog_for_active(w) or prompt_you_asked_for(w) then
        -- Focus moving to a window no grant asked for is moving on, even
        -- though the guard dispatches it: a dialog that follows a click
        -- Lua can't see is the click's only trace.
        cancel_grants()
        focus(w)
    else
        announce(w)
    end
end

-- An existing window asked to be activated. Hyprland has already marked it
-- urgent (misc:focus_on_activate is off); a launch grant lets it through,
-- and otherwise it waits with the rest, so Super+U takes the latest of both.
function M.on_urgent(w)
    if take_grant(w) then
        focus(w)
    else
        wait(w)
    end
end

function M.on_close(w)
    local address = field(w, "address")
    if address then
        forget(address)
    end
end

-- Focuses the window that most recently started waiting, and returns true;
-- false when none is waiting, so the key can fall back to the last window.
function M.focus_attention()
    local address = table.remove(state.waiting)
    if not address then
        return false
    end
    cancel_grants() -- you chose another window
    focus_address(address)
    return true
end

function M.on_active(w, reason)
    reason = reason or 0
    -- Focus on nothing (an empty workspace, the last window closed) means no
    -- app is "the one you're in" until something is focused again.
    local before = state.active
    state.active = w and active_record(w) or nil
    local address = state.active and state.active.address
    if address then
        forget(address) -- however you got there, it isn't waiting now
    end
    -- Focus coming back to the window you were already in (the launcher
    -- closing) isn't moving on, and the guard's own focusing is flagged
    -- while it dispatches. Anything else is: the pointer, a key binding, a
    -- click, a workspace switch, and focus passing on after a window closes.
    local returned = address ~= nil and before ~= nil and before.address == address
    if focusing or returned or reason == REASON_NEW_WINDOW then
        return
    end
    cancel_grants()
end

function M.on_key(_, _, key_state)
    -- 1 is a press; releases (including the one after the launch key) don't
    -- count as moving on.
    if key_state == 1 then
        cancel_grants()
        state.last_key = M.clock()
    end
end

-- Records a one-shot grant for app, from `quickspace launch` or a
-- notification click.
-- pid, if given, is the process that asked (the zsh preexec hook passes its
-- shell's), which lets a window from one of its descendants use the grant.
function M.grant(app, pid)
    local id = normalize(app)
    if not id then
        error("quickspace_focus.grant: expected an app id, got " .. tostring(app), 2)
    end
    if pid ~= nil and (math.type(pid) ~= "integer" or pid <= 1) then
        error("quickspace_focus.grant: expected a process id, got " .. tostring(pid), 2)
    end
    expire()
    table.insert(state.grants, { app = id, at = M.clock(), pid = pid })
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
        -- NaN fails `v > 0`, and infinity would never expire.
        if type(v) ~= type(M.defaults[k]) or (type(v) == "number" and not (v > 0 and v < math.huge)) then
            local want = type(M.defaults[k]) == "number" and "a positive number" or "a " .. type(M.defaults[k])
            error("quickspace focus.setup: " .. tostring(k) .. " must be " .. want, 2)
        end
        if type(v) == "table" then
            -- n keys, each of 1..n present, means exactly 1..n; `#` alone
            -- can't say that, since a table with gaps has no defined length.
            local count = 0
            for _ in pairs(v) do
                count = count + 1
            end
            for i = 1, count do
                if v[i] == nil then
                    error("quickspace focus.setup: " .. tostring(k) .. " must be a list, with no keys or gaps", 2)
                end
            end
            for i = 1, count do
                local item = v[i]
                if type(item) ~= "string" or item == "" then
                    error("quickspace focus.setup: " .. tostring(k) .. " must list window classes", 2)
                end
            end
        end
        merged[k] = v
    end
    state.opts = merged
    state.last_key = nil
    state.grants = {}
    state.active = nil
    state.waiting = {}
    local w = hl.get_active_window()
    if w then
        state.active = active_record(w)
    end

    hl.window_rule({ name = "quickspace-focus-guard", match = { class = ".*" }, no_initial_focus = true })
    hl.on("window.open", M.on_open)
    hl.on("window.urgent", M.on_urgent)
    hl.on("window.active", M.on_active)
    hl.on("window.close", M.on_close)
    hl.on("input.keyboard.key", M.on_key)
    _G.quickspace_focus = M
    return M
end

return M
