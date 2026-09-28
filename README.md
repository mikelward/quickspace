# quickspace

A small Wayland desktop built for dwm/Krohnkite-style tiling:

- **Hyprland** tiles the windows.
- **Quickshell** draws the bar, launcher, notifications, lock and login
  screens, OSDs and screen-share picker.
- **greetd** logs you in.
- **uwsm** runs the session, with one owner per job, so nothing starts twice.

**Status: milestone 1, design.** Start with the [spec](SPEC.md). The mocks
are in [`docs/mocks/`](docs/mocks/).

![desktop mock](docs/mocks/desktop.png)

## Mocks

The mocks are plain HTML/CSS. To re-render the PNGs after editing one:

    make mocks

This needs Node and Playwright with Chromium.
