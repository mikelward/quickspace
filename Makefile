# Re-render the design mocks (docs/mocks/*.html -> *.png).
#
# Needs Node and Playwright with Chromium. A global Playwright install is
# found through NODE_PATH; a project-local one works without it.

.PHONY: mocks
mocks:
	NODE_PATH="$$(npm root -g)" node docs/mocks/render.js
