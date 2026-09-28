# quickspace
#
#   make test      run the tests
#   make install   install the Hyprland layout into ~/.config/hypr/quickspace
#   make mocks     re-render the design mocks (docs/mocks/*.html -> *.png)

# Hyprland embeds Lua 5.5; the layout also runs on 5.4, which is what most
# distributions package today.
LUA ?= $(shell command -v lua5.5 || command -v lua5.4 || command -v lua)
HYPR_DIR ?= $(HOME)/.config/hypr/quickspace

.PHONY: test install mocks
test:
	@test -n "$(LUA)" || { echo "make test: no lua5.5, lua5.4 or lua on PATH" >&2; exit 1; }
	$(LUA) hypr/quickspace/layout_test.lua

install:
	install -d "$(HYPR_DIR)"
	install -m 644 hypr/quickspace/geometry.lua hypr/quickspace/layout.lua "$(HYPR_DIR)/"

# Needs Node and Playwright with Chromium. A global Playwright install is
# found through NODE_PATH; a project-local one works without it.
mocks:
	NODE_PATH="$$(npm root -g)" node docs/mocks/render.js
