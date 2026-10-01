# TODO

Deferred work, with enough notes to pick it up later.

## Decisions needing review

Calls made on autopilot, each chosen for being cheap to undo. Delete an entry
once you have agreed with it or reversed it.

- [ ] **The autostart allowlist starts as `nm-applet` and `blueman`.** The
      spec says it starts empty, but the bar's network and Bluetooth icons
      come from those applets' autostart entries until the shell draws them
      (M3). Emptying it is a one-line change to `autostart_default` in
      `bin/quickspace`.

## Transitional shell (M2)

`quickspace.service` runs `bin/quickspace-shell`, not `qs -c quickspace`,
because the Quickshell shell can't be built or tested in the sandbox and the
MVP comes first. The owners are the ones already in daily use: waybar (bar and
tray watcher) and swaync (notifications), both run by `conf`'s theme daemon,
plus the first polkit agent found and swww for the wallpaper. It also runs
`conf`'s `apply-input.sh` once, since Hyprland's config starts nothing but
`uwsm finalize` in this session.

- Replace it piece by piece as M3 (bar, launcher) and M4 (notifications)
  land: each Quickshell owner joins the shell's ready check, and its old
  owner leaves `quickspace-shell`.
- Until then the polkit agent isn't part of the ready check, and the tray
  and notifications look like today's, not the mocks.
- The polkit agent is restarted on its own, with backoff, rather than
  failing the unit (SPEC.md §5.2's M2 note). The Quickshell agent has to
  keep that: another desktop's agent can hold the session first, and the
  bar mustn't restart over it.
- Ready is checked once, at start. After that the shell watches only the
  theme daemon, which restarts waybar and swaync at each light/dark
  boundary. For that moment the notification and tray names are unowned,
  and an app launched then doesn't wait for them. Failing the unit on
  their loss would restart the whole shell at every theme change instead.
  It goes away with the Quickshell owners, which change theme without a
  restart (SPEC.md §5.4).
- A polkit prompt takes focus only after a key press (the keyboard half of
  SPEC.md §14.1); after a click it waits for `Super+U`, and there's no
  **Authenticate** notification yet. Both come with the Quickshell agent.
- Nothing consumes `quickspace-attention` yet, so the focus guard shows a
  Hyprland notification for each window it leaves waiting. Turn that off
  (`notify = false`) once the bar marks those windows.

## The rest of `quickspace doctor`

M2's `quickspace doctor` (`bin/quickspace-doctor`) checks units, D-Bus
owners, duplicate and rival daemons, the portal config, Hyprland's config
errors, and autostart entries. SPEC.md §5.4 also wants:

- **Activatable services that could steal a name.** In M2 swaync's own
  activation file names `org.freedesktop.Notifications`, so flagging every
  activatable one would flag the owner. Check it once the shell owns the
  name, naming the service file and the package that ships it.
- **More than one top-anchored layer surface per monitor.** It needs
  `hyprctl layers -j` parsed per monitor, which wants a JSON reader the
  session doesn't have yet (jq, or the shell itself in M3).

## Grants for terminal commands

Every shell in `conf` runs `quickspace-grant` (SPEC.md §14.3) before a
command except mesh, which waits until `conf` tests it (tracked in `conf`'s
TODO.md). Nothing has run it in a live session yet.

## Grants through desktop entries

The focus guard matches a grant against the window class alone (SPEC.md
§14.3). `quickspace launch xdg-open URL` or `gio open FILE` would grant
`xdg-open` or `gio`, which no window has, leaving the opened app unfocused.
Until the launcher's desktop-entry index exists (M3), such a launch grants
`*` (the first window of any app) unless `--app` names the app. Then resolve
a program name through desktop entries' `Exec` and `StartupWMClass`, and an
opener through the default handler for the file's type.

## Fullscreen on open, under the focus guard

Deferred: it needs a Hyprland patch, and the MVP comes first.

- The guard's catch-all `no_initial_focus` rule makes Hyprland 0.56 skip a
  fullscreen request made as a window opens (`Window.cpp`: the initial
  fullscreen is applied only when `!m_noInitialFocus`).
- The guard can't re-apply it: Lua's window object has no field for
  `m_wantsInitialFullscreen`, and `fullscreen_client` stays 0 because the
  request was never applied.
- Until then, a window that opens fullscreen (a game, a video player
  started with `--fullscreen`) comes up tiled; `Super+Shift+Up` makes it
  fullscreen.
- Plan: expose the request as a window field (a few lines in
  `LuaWindow.cpp`), next to the pointer-button event (§14.3); the guard
  then re-applies it when it focuses the window.

## Drag to resize a tiled window

Deferred: it needs a Hyprland patch, and the MVP comes first.

- Floating windows already resize with `Super`+right-drag or by dragging an
  edge. Under the master fallback, dragging a tiled window changes `mfact`.
- Under `lua:quickspace` a drag does nothing. Hyprland 0.56 drops it before it
  reaches a Lua layout: `CLuaTiledAlgorithm::resizeTarget`
  (`src/config/lua/layout/LuaLayoutProvider.cpp`) ignores the delta and only
  recalculates.
- Plan: a small upstream patch that passes the delta and corner to an optional
  Lua `resize` callback. `layout.lua` then maps a drag across the
  master/stack boundary to `mfact`, per workspace and mode like
  `Super+\` / `Super+/`. Pick it up on the Hyprland upgrade PR that brings the
  patch in.
- Rejected: polling the cursor with `hl.timer` while the button is held. It
  works today, but it's a polling loop on a hot path and fights Hyprland's
  own drag.
- Until then, the keys resize the master.

## Double-click the bar to maximize

Lands with the bar (M3).

- `Super`+middle-click toggles maximize (SPEC.md §6.6), and a second click
  puts the window back in its tile. Its binding is in `conf`'s
  `hyprland.lua`.
- The bar adds a mouse-only way: double-click its empty middle to toggle
  maximize on that monitor's focused window, like a title bar. The bar shows
  no window title (SPEC.md §7.1), so the middle is free.
- Rejected: title bars from the `hyprbars` plugin. A plugin is rebuilt against
  every Hyprland upgrade (SPEC.md §3.1).

## Compositor: explore a dwl fork (SPEC.md §21.1)

Hyprland stays the baseline, but building it on Debian and Ubuntu is heavy,
so §21.1 records a quickspace fork of dwl on a pinned wlroots as the
alternative. The fork's code goes in
[mikelward/dwl](https://github.com/mikelward/dwl), which holds upstream's
history; quickspace's changes go on top of v0.9 there. Before rewriting §3.1 around it, work through §21.1's next steps:

- Screen sharing through `quickspace-share-picker` on xdg-desktop-portal-wlr,
  with an adapter, including a way to share the 16:9 slice.
- `grim -T` on a dwl build that exposes the toplevel-capture protocols.
- Re-check Debian 13's toolchain.
- Inventory everything the spec needs from the compositor, with the fork's
  replacement and a check for each.

If the fork is adopted, machines build a pinned release tag, never a branch:

- **Tags.** `quickspace-<upstream base>-<n>`, cut from the fork's `main`
  once it is in a state to run (`quickspace-0.9-1` is dwl 0.9 plus our
  changes, release 1). Upstream's own `v*` tags stay as they are, so a tag
  says at a glance whether it carries our code and which base it sits on.
  Moving to a new upstream release rebases our changes onto it and starts
  the count again (`quickspace-0.10-1`).
- **`setup-quickspace` pins one.** A line in the same shape as the Hyprland
  pins, `dwl https://github.com/mikelward/dwl.git quickspace-0.9-1 make`,
  so every machine builds the same reviewed code, and moving them all is a
  one-line scripts pull request that CI checks first. Not `main`, which
  moves under a later run; not `v0.9`, which is upstream's code without
  ours.
- **Protection.** `main` gets the fleet ruleset from `repo setup`, like
  every other repository. A tag ruleset makes `quickspace-*` and `v*`
  immutable, since a moved tag would silently change what machines build.
  The repository is public, so nothing secret ever goes in it, on any
  branch: per-machine settings stay in an untracked local file.
