# quickspace
#
#   make test             run the tests
#   make install          install the per-user parts: the Hyprland layout,
#                         the session's systemd user units and the portal
#                         config, under ~/.config
#   make install-session  install the session entry, its compositor wrapper
#                         and the quickspace command under $(PREFIX) (root;
#                         see README.md)
#   make mocks            re-render the design mocks (docs/mocks/*.html -> *.png)

# Hyprland embeds Lua 5.5; the layout also runs on 5.4, which is what most
# distributions package today.
LUA ?= $(shell command -v lua5.5 || command -v lua5.4 || command -v lua)
HYPR_DIR ?= $(HOME)/.config/hypr/quickspace
SYSTEMD_USER_DIR ?= $(HOME)/.config/systemd/user
PORTAL_DIR ?= $(HOME)/.config/xdg-desktop-portal
PREFIX ?= /usr/local

.PHONY: test install install-session mocks
test:
	@test -n "$(LUA)" || { echo "make test: no lua5.5, lua5.4 or lua on PATH" >&2; exit 1; }
	$(LUA) hypr/quickspace/layout_test.lua
	sh session/session_test.sh
	sh bin/quickspace_test.sh

# Copies only. Enabling quickspace.service, which hangs it off the quickspace
# session's target, is `setup --quickspace`'s job (scripts repo).
install:
	install -d "$(HYPR_DIR)"
	install -m 644 hypr/quickspace/geometry.lua hypr/quickspace/layout.lua "$(HYPR_DIR)/"
	install -d "$(SYSTEMD_USER_DIR)/hypridle.service.d"
	install -m 644 systemd/user/quickspace.service "$(SYSTEMD_USER_DIR)/"
	install -m 644 systemd/user/hypridle.service.d/quickspace.conf "$(SYSTEMD_USER_DIR)/hypridle.service.d/"
	install -d "$(PORTAL_DIR)"
	install -m 644 xdg-desktop-portal/quickspace-portals.conf "$(PORTAL_DIR)/"

# Display managers list sessions from wayland-sessions under the system data
# dirs. Not every one searches /usr/local/share; if the session doesn't show
# up at the greeter, install with PREFIX=/usr.
install-session:
	install -d "$(DESTDIR)$(PREFIX)/bin" "$(DESTDIR)$(PREFIX)/share/wayland-sessions"
	install -m 755 bin/quickspace bin/quickspace-hyprland "$(DESTDIR)$(PREFIX)/bin/"
	install -m 644 session/quickspace.desktop "$(DESTDIR)$(PREFIX)/share/wayland-sessions/"

# Needs Node and Playwright with Chromium. A global Playwright install is
# found through NODE_PATH; a project-local one works without it.
mocks:
	NODE_PATH="$$(npm root -g)" node docs/mocks/render.js
