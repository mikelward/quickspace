# TODO

Deferred work, with enough notes to pick it up later.

## Transitional shell (M2)

`quickspace.service` runs `bin/quickspace-shell`, not `qs -c quickspace`,
because the Quickshell shell can't be built or tested in the sandbox and the
MVP comes first. The owners are the ones already in daily use: waybar (bar and
tray watcher) and swaync (notifications), both run by `conf`'s theme daemon,
plus the first polkit agent found.

- Replace it piece by piece as M3 (bar, launcher) and M4 (notifications)
  land: each Quickshell owner joins the shell's ready check, and its old
  owner leaves `quickspace-shell`.
- Until then the polkit agent isn't part of the ready check, and the tray
  and notifications look like today's, not the mocks.
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

## Grants for terminal commands

SPEC.md §14.3 has a preexec hook in `conf`'s zsh config write a grant for
each command, through zsh's socket module. It isn't written yet, so a GUI
started from a terminal opens unfocused unless it's the terminal's own app,
and the guard's process-ancestry fallback has no grant to use.

## Grants through desktop entries

The focus guard matches a grant against the window class alone (SPEC.md
§14.3). `quickspace launch xdg-open URL` or `gio open FILE` therefore grants
`xdg-open` or `gio`, which no window has, and the opened app starts
unfocused. Until the launcher's desktop-entry index exists (M3), such a
launch needs `--app` to name the app. Then resolve a program name through
desktop entries' `Exec` and `StartupWMClass`, and an opener through the
default handler for the file's type.

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
