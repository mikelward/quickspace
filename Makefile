# quickspace
#
#   make test             run the tests
#   make build            build quickspace-grant and quickspace-tz (needs Go)
#                         into build/
#   make install          build, then install the per-user parts: the
#                         Hyprland layout and focus guard, the Quickshell
#                         config (run it with `qs -c quickspace`),
#                         the session's systemd user units and the portal
#                         config, under ~/.config
#   make install-session  install the session entry, its compositor wrapper
#                         and the quickspace commands under $(PREFIX) (root;
#                         see README.md; run `make build` as yourself first)
#   make mocks            re-render the design mocks (docs/mocks/*.html -> *.png)

# Hyprland embeds Lua 5.5; the layout also runs on 5.4, which is what most
# distributions package today.
LUA ?= $(shell command -v lua5.5 || command -v lua5.4 || command -v lua)
HYPR_DIR ?= $(HOME)/.config/hypr/quickspace
SYSTEMD_USER_DIR ?= $(HOME)/.config/systemd/user
PORTAL_DIR ?= $(HOME)/.config/xdg-desktop-portal
SHELL_DIR ?= $(HOME)/.config/quickshell/quickspace
PREFIX ?= /usr/local
# The per-agent drop-ins earlier versions installed, which the allowlist
# replaces, are found by how their first line starts, so ones installed
# under a custom POLKIT_AUTOSTART go too. Left behind, they would keep
# skipping their agent even if it were allowlisted, since systemd runs every
# ExecCondition.
OLD_AUTOSTART_DROPIN_MARK = \# A drop-in for another desktop's autostarted polkit agent
GO ?= go
# The shell's pure logic (shell/lib) is tested with node --test (SPEC.md §20).
NODE ?= node
# Build with the Go that's installed, never one downloaded to match go.mod.
export GOTOOLCHAIN := local

.PHONY: test build install install-session mocks
test:
	@test -n "$(LUA)" || { echo "make test: no lua5.5, lua5.4 or lua on PATH" >&2; exit 1; }
	$(LUA) hypr/quickspace/layout_test.lua
	$(LUA) hypr/quickspace/focus_test.lua
	sh session/session_test.sh
	sh bin/quickspace_test.sh
	sh bin/quickspace-shell_test.sh
	sh bin/quickspace-doctor_test.sh
	$(NODE) --test shell/lib/clocks_test.mjs shell/lib/workspaces_test.mjs shell/lib/tzdata_test.mjs shell/lib/layouts_test.mjs shell/lib/appearance_test.mjs shell/lib/status_test.mjs shell/lib/dst_test.mjs shell/lib/popover_test.mjs shell/lib/session_test.mjs shell/lib/audio_test.mjs shell/lib/bluetooth_test.mjs shell/lib/launch_test.mjs shell/lib/network_test.mjs
	$(GO) vet ./...
	$(GO) test ./...

build: build/quickspace-grant build/quickspace-tz

build/quickspace-grant: go.mod go.sum $(wildcard cmd/quickspace-grant/*.go)
	$(GO) build -o $@ ./cmd/quickspace-grant

build/quickspace-tz: go.mod $(wildcard cmd/quickspace-tz/*.go)
	$(GO) build -o $@ ./cmd/quickspace-tz

# Copies only. Enabling quickspace.service, which hangs it off the quickspace
# session's target, is `setup --quickspace`'s job (scripts repo).
install: build
	install -d "$(HYPR_DIR)"
	install -m 644 hypr/quickspace/geometry.lua hypr/quickspace/layout.lua hypr/quickspace/focus.lua "$(HYPR_DIR)/"
	install -d "$(SYSTEMD_USER_DIR)/hypridle.service.d" "$(SYSTEMD_USER_DIR)/app-.service.d"
	install -m 644 systemd/user/quickspace.service "$(SYSTEMD_USER_DIR)/"
	install -m 644 systemd/user/hypridle.service.d/quickspace.conf "$(SYSTEMD_USER_DIR)/hypridle.service.d/"
	install -m 644 systemd/user/app-.service.d/quickspace-autostart.conf "$(SYSTEMD_USER_DIR)/app-.service.d/"
	@# rmdir only removes a directory this emptied.
	for f in "$(SYSTEMD_USER_DIR)"/app-*@autostart.service.d/quickspace.conf; do \
		test -f "$$f" || continue; \
		case "$$(head -n 1 "$$f")" in "$(OLD_AUTOSTART_DROPIN_MARK)"*) ;; *) continue ;; esac; \
		rm -f "$$f" || exit 1; \
		d=$${f%/*}; \
		if test -z "$$(ls -A "$$d")"; then rmdir "$$d" || exit 1; fi; \
	done
	install -d "$(PORTAL_DIR)"
	install -m 644 xdg-desktop-portal/quickspace-portals.conf "$(PORTAL_DIR)/"
	install -d "$(SHELL_DIR)/lib"
	install -m 644 shell/*.qml "$(SHELL_DIR)/"
	install -m 644 $(filter-out %_test.mjs,$(wildcard shell/lib/*.mjs)) "$(SHELL_DIR)/lib/"

# Display managers list sessions from wayland-sessions under the system data
# dirs. Not every one searches /usr/local/share; if the session doesn't show
# up at the greeter, install with PREFIX=/usr.
# Root has no Go module cache to build with, so install-session only copies
# the Go commands that `make build` (or `make install`) left in build/.
install-session:
	@for cmd in quickspace-grant quickspace-tz; do \
		test -x build/$$cmd || { echo "make install-session: no build/$$cmd; run make build first, as yourself" >&2; exit 1; }; \
	done
	install -d "$(DESTDIR)$(PREFIX)/bin" "$(DESTDIR)$(PREFIX)/share/wayland-sessions"
	install -m 755 bin/quickspace bin/quickspace-doctor bin/quickspace-hyprland bin/quickspace-shell build/quickspace-grant build/quickspace-tz "$(DESTDIR)$(PREFIX)/bin/"
	install -m 644 session/quickspace.desktop "$(DESTDIR)$(PREFIX)/share/wayland-sessions/"

# Needs Node and Playwright with Chromium. A global Playwright install is
# found through NODE_PATH; a project-local one works without it.
mocks:
	NODE_PATH="$$(npm root -g)" node docs/mocks/render.js
