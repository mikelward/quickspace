# compositor

A place to explore a quickspace fork of [dwl](https://codeberg.org/dwl/dwl),
the dwm-style wlroots compositor, as an alternative to Hyprland. Hyprland
stays the baseline; the exploration and its next steps are in SPEC.md §21.1
and `TODO.md`.

## `dwl/`

dwl v0.9 (upstream commit 98bea2c, 2026-09-20), as released, with no changes
yet. It came from `git archive v0.9`, so later commits here show quickspace's
changes as diffs against upstream. To move to a newer release, replace the
directory with that tag's `git archive` in its own commit, then reapply
quickspace's changes on top.

dwl v0.9 builds against wlroots 0.20. Ubuntu 26.04 has 0.19, so building it
waits on a pinned wlroots build, which `setup-quickspace` will do in a later
change. Nothing builds or installs this directory yet.

## License

`dwl/` is dwl's code under dwl's licenses: GPL-3.0 or later
(`dwl/LICENSE`), with the parts derived from dwm, tinywl and sway under the
terms in `dwl/LICENSE.dwm`, `dwl/LICENSE.tinywl` and `dwl/LICENSE.sway`.
Changes made inside `dwl/` stay under those terms. The rest of quickspace is
Apache-2.0 (`LICENSE` at the top), which is compatible one way: Apache-2.0
code can be built into the GPL-3.0 compositor, and the result is GPL-3.0.
