# quickspace

A small Wayland desktop built for dwm/Krohnkite-style tiling:

- **Hyprland** tiles the windows.
- **Quickshell** draws the bar, launcher, notifications, lock and login
  screens, OSDs and screen-share picker.
- **greetd** logs you in.
- **uwsm** runs the session, with one owner per job, so nothing starts twice.

**Status: milestone 2, session skeleton.** Start with the [spec](SPEC.md).
The mocks are in [`docs/mocks/`](docs/mocks/).

![desktop mock](docs/mocks/desktop.png)

## Installing

`setup --quickspace` in the scripts repo will do all of this; until it lands,
this is the way to install by hand:

    make install                       # builds quickspace-grant and quickspace-tz (needs Go 1.22+); layout, user units, portal config under ~/.config
    sudo make install-session          # session entry, compositor wrapper, `quickspace`, quickspace-grant and quickspace-tz under /usr/local
    systemctl --user daemon-reload
    systemctl --user enable quickspace.service

By hand, also install what the session runs: Hyprland 0.56 or later,
hypridle, uwsm, waybar, swaync, a polkit agent, swww or swaybg, and jq,
which `quickspace doctor` reads Hyprland's JSON with. `setup-quickspace`
installs them all. jq is a free distro package that runs locally, with no
network calls; without it, the doctor reports its bar check as skipped.

Then pick **quickspace** at the display manager. It runs Hyprland through
uwsm as `quickspace-hyprland`, which gives the session its own systemd
target, so quickspace's units never start in a plain Hyprland or Plasma
login (SPEC.md §5.3). If the display manager doesn't list the session,
install it with `sudo make install-session PREFIX=/usr`.

Key bindings and the launcher start apps with `quickspace launch [--app ID]
COMMAND...`: it waits (at most 15 s) for the shell, gives the app a one-shot
focus grant, and runs it with `uwsm app` so it outlives a shell restart.
Terminal commands get their grants from `quickspace-grant`, which each shell
runs before a command (SPEC.md §14.3).

Until the Quickshell shell exists, `quickspace.service` runs
`quickspace-shell`, a transitional shell: conf's theme daemon (which runs
waybar and swaync), a polkit agent, and swww (or swaybg where swww isn't packaged) for the wallpaper. It also runs
conf's input setup once. It reports ready once swaync owns the notification
name and waybar's tray owns the watcher (see `TODO.md`).

`quickspace doctor` checks the running session and prints one line per
problem, with its fix: units that aren't running, D-Bus names owned by the
wrong process, daemons running twice or rivals to an owner, the portal
config, Hyprland's config errors, and autostart entries that run in
quickspace without being on its allowlist. It exits 1 if it found a problem.

XDG autostart is an allowlist in quickspace. `make install` adds one systemd
drop-in, `app-.service.d/quickspace-autostart.conf`, that reaches every
autostart unit; in the quickspace session it skips each entry that
`quickspace autostart-allowed` doesn't name, so other desktops' daemons and
tray icons stay out, while Plasma runs them all as before. The list is
`nm-applet` and `blueman` for now; add desktop IDs, one per line, to
`~/.config/quickspace/autostart` to allow more.

## Mocks

The mocks are plain HTML/CSS. To re-render the PNGs after editing one:

    make mocks

This needs Node and Playwright with Chromium.

## License

Apache-2.0; see `LICENSE`. The dwl fork explored in SPEC.md §21.1 lives in
its own repository, [mikelward/dwl](https://github.com/mikelward/dwl), under
dwl's GPL-3.0-or-later license.
