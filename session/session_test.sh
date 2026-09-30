#!/bin/sh
#
# Tests for the quickspace session: the wayland-sessions entry, its
# compositor wrapper, the systemd user units and the portal config
# (SPEC.md §5.2-§5.4). No compositor runs here, so these check the files'
# contracts, verify the units with systemd-analyze where it can run, and
# check what `make install` puts where.

cd "$(dirname "$0")/.." || exit 1

passes=0
failures=0

pass() { passes=$((passes + 1)); }
fail() {
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$1" >&2
}
# check NAME COMMAND...: passes when COMMAND succeeds.
check() {
    _name=$1
    shift
    if "$@"; then pass; else fail "$_name"; fi
}
has_line() { grep -qxF -- "$2" "$1"; }
lacks_line_matching() { ! grep -qE -- "$2" "$1"; }

unit=systemd/user/quickspace.service
dropin=systemd/user/hypridle.service.d/quickspace.conf
entry=session/quickspace.desktop
wrapper=bin/quickspace-hyprland
portals=xdg-desktop-portal/quickspace-portals.conf
not_here=systemd/user/not-in-quickspace.conf

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# --- The session entry and its wrapper ----------------------------------------
# uwsm names the session after the compositor command, so the wrapper's name
# is the session's target; the unit must hang off that same target.
session_id=$(basename "$wrapper")
check "the entry starts the wrapper through uwsm with quickspace:Hyprland" \
    has_line "$entry" "Exec=uwsm start -e -D quickspace:Hyprland -N quickspace -- $session_id"
check "the entry lists quickspace first in DesktopNames" \
    has_line "$entry" "DesktopNames=quickspace;Hyprland"
check "the wrapper execs Hyprland" grep -qx 'exec Hyprland "\$@"' "$wrapper"
check "the wrapper is executable" test -x "$wrapper"
check "the wrapper parses as sh" sh -n "$wrapper"
if command -v shellcheck >/dev/null 2>&1; then
    check "shellcheck passes on the wrapper and this test" \
        shellcheck -s sh "$wrapper" session/session_test.sh
fi

# --- quickspace.service ---------------------------------------------------------
target="wayland-session@$session_id.target"
check "the unit is wanted by the quickspace session's target" \
    has_line "$unit" "WantedBy=$target"
# Plasma reaches graphical-session.target too; that's how swaync leaked in.
check "the unit is never WantedBy= graphical-session.target" \
    lacks_line_matching "$unit" '^WantedBy=.*graphical-session\.target'
check "the unit is WantedBy= nothing else" \
    test "$(grep -c '^WantedBy=' "$unit")" -eq 1
check "the unit is ordered after its session target" \
    grep -qE "^After=.*$target" "$unit"
check "the unit stops with the graphical session" \
    has_line "$unit" "PartOf=graphical-session.target"
check "ready means the shell said so" has_line "$unit" "Type=notify"
check "the shell's helpers may report ready" has_line "$unit" "NotifyAccess=all"
check "a shell that never gets ready fails in 15 s" \
    has_line "$unit" "TimeoutStartSec=15"
check "a bad setting isn't restarted" has_line "$unit" "RestartPreventExitStatus=78"
check "hypridle is wanted, not required" has_line "$unit" "Wants=hypridle.service"
check "hypridle is not required" lacks_line_matching "$unit" '^Requires=.*hypridle'
check "the shell starts after hypridle" has_line "$unit" "After=hypridle.service"
check "the shell is up before autostarted apps" \
    has_line "$unit" "Before=xdg-desktop-autostart.target"

# --- The hypridle drop-in -------------------------------------------------------
check "hypridle is started once it owns org.freedesktop.ScreenSaver" \
    has_line "$dropin" "Type=dbus"
check "the drop-in names the ScreenSaver bus name" \
    has_line "$dropin" "BusName=org.freedesktop.ScreenSaver"
check "a hypridle that never claims the name fails in 10 s" \
    has_line "$dropin" "TimeoutStartSec=10"
check "the drop-in adds no [Install], so hypridle isn't enabled globally" \
    lacks_line_matching "$dropin" '^\[Install\]'
# The drop-in's condition, as systemd would run it ($$ is a literal $).
idle_condition=$(sed -n 's/^ExecCondition=\/bin\/sh -c //p' "$dropin" | sed "s/^'//; s/'\$//; s/\\$\\$/\\$/g")
idle_runs_in() { XDG_CURRENT_DESKTOP=$1 sh -c "$idle_condition"; }
idle_skips_in() { ! idle_runs_in "$1"; }
check "hypridle's condition is a sh -c script" test -n "$idle_condition"
check "hypridle runs in the quickspace session" idle_runs_in "quickspace:Hyprland"
check "hypridle is skipped under Plasma, even when a package enabled it" idle_skips_in "KDE"
check "hypridle's unit is skipped in a plain Hyprland login, which runs its own" idle_skips_in "Hyprland"
check "hypridle is skipped where no desktop is set" idle_skips_in ""

# --- Other desktops' polkit agents -----------------------------------------------
# The drop-in's condition, as systemd would run it ($$ is a literal $).
condition=$(sed -n 's/^ExecCondition=\/bin\/sh -c //p' "$not_here" | sed "s/^'//; s/'\$//; s/\\$\\$/\\$/g")
runs_in() { XDG_CURRENT_DESKTOP=$1 sh -c "$condition"; }
skips_in() { ! runs_in "$1"; }
check "another agent's condition is a sh -c script" test -n "$condition"
check "another agent is skipped in the quickspace session" skips_in "quickspace:Hyprland"
check "another agent still runs under Plasma" runs_in "KDE"
check "another agent still runs under MATE" runs_in "MATE"
check "another agent still runs in a plain Hyprland login" runs_in "Hyprland"
check "another agent still runs where no desktop is set" runs_in ""

# Suppressing the legacy agents must not leave the session with none: the
# shell falls back to KDE's, always installed beside Plasma (SPEC.md §5.5).
agents=$(sed -n '/^default_agents="/,/^"/p' bin/quickspace-shell)
searches_for() { printf '%s\n' "$agents" | grep -q "/$1\$"; }
check "the shell falls back to KDE's polkit agent" \
    searches_for polkit-kde-authentication-agent-1
# Doctor finds the running agent by its process name, the first 15
# characters of the file name, so it must know every one the shell can start.
doctor_names=$(sed -n '/^agent_names="/,/"$/p' bin/quickspace-doctor | tr -d '"' | sed 's/^agent_names=//')
doctor_knows() { printf '%s\n' "$doctor_names" | grep -qxF -- "$(printf '%.15s' "$1")"; }
for path in $(printf '%s\n' "$agents" | grep '^ */'); do
    check "doctor recognizes the shell's agent $path" doctor_knows "${path##*/}"
done

# --- systemd-analyze verify ---------------------------------------------------
# Resolves the units as systemd would. quickspace-shell and hypridle aren't
# installed here, so the copies point ExecStart at a stub; everything else is
# as shipped.
if command -v systemd-analyze >/dev/null 2>&1; then
    mkdir -p "$tmp/run" "$tmp/units/hypridle.service.d"
    chmod 700 "$tmp/run"
    printf '#!/bin/sh\n' > "$tmp/stub"
    chmod +x "$tmp/stub"
    sed "s|^ExecStart=quickspace-shell\$|ExecStart=$tmp/stub|" "$unit" > "$tmp/units/quickspace.service"
    # A stand-in for the packaged hypridle.service, with the drop-in on top.
    printf '[Unit]\nDescription=hypridle\n[Service]\nExecStart=%s\n' "$tmp/stub" \
        > "$tmp/units/hypridle.service"
    cp "$dropin" "$tmp/units/hypridle.service.d/"
    # A stand-in for a generated autostart unit, with the agent drop-in.
    agent_unit='app-polkit\x2dmate\x2dauthentication\x2dagent\x2d1@autostart.service'
    mkdir -p "$tmp/units/$agent_unit.d"
    printf '[Unit]\nDescription=agent\n[Service]\nExecStart=%s\n' "$tmp/stub" \
        > "$tmp/units/$agent_unit"
    cp "$not_here" "$tmp/units/$agent_unit.d/quickspace.conf"
    for u in quickspace.service hypridle.service "$agent_unit"; do
        out=$(cd "$tmp/units" && XDG_RUNTIME_DIR="$tmp/run" \
            systemd-analyze verify --user --man=no "$u" 2>&1)
        status=$?
        check "systemd-analyze verify $u exits 0: $out" test "$status" -eq 0
        # The system bus doesn't exist in a container; nothing else may print.
        out=$(printf '%s\n' "$out" | grep -v '^Failed to connect to system bus')
        check "systemd-analyze verify $u prints nothing: $out" test -z "$out"
    done
else
    echo "SKIP: systemd-analyze verify (not installed)"
fi

# --- Portals --------------------------------------------------------------------
check "the portal config names hyprland then gtk" \
    has_line "$portals" "default=hyprland;gtk"
check "the portal config never picks kde, gnome or wlr" \
    lacks_line_matching "$portals" '^[^#]*(kde|gnome|wlr)'

# --- make install / install-session ----------------------------------------------
home="$tmp/home"
# The fake HOME would send Go to an empty module cache, and so the network.
if make -s install HOME="$home" GOMODCACHE="$(go env GOMODCACHE)" GOCACHE="$(go env GOCACHE)" \
    >"$tmp/install.log" 2>&1; then
    for f in .config/hypr/quickspace/layout.lua \
             .config/hypr/quickspace/geometry.lua \
             .config/hypr/quickspace/focus.lua \
             .config/systemd/user/quickspace.service \
             .config/systemd/user/hypridle.service.d/quickspace.conf \
             .config/xdg-desktop-portal/quickspace-portals.conf \
             '.config/systemd/user/app-polkit\x2dmate\x2dauthentication\x2dagent\x2d1@autostart.service.d/quickspace.conf' \
             '.config/systemd/user/app-polkit\x2dgnome\x2dauthentication\x2dagent\x2d1@autostart.service.d/quickspace.conf'; do
        check "make install puts $f in place" test -f "$home/$f"
    done
else
    fail "make install: $(cat "$tmp/install.log")"
fi
if make -s install-session DESTDIR="$tmp/root" PREFIX=/usr >"$tmp/session.log" 2>&1; then
    check "make install-session installs the wrapper" \
        test -x "$tmp/root/usr/bin/quickspace-hyprland"
    check "make install-session installs the quickspace command" \
        test -x "$tmp/root/usr/bin/quickspace"
    check "make install-session installs quickspace-grant" \
        test -x "$tmp/root/usr/bin/quickspace-grant"
    check "make install-session installs the unit's shell" \
        test -x "$tmp/root/usr/bin/quickspace-shell"
    check "make install-session installs the session entry" \
        test -f "$tmp/root/usr/share/wayland-sessions/quickspace.desktop"
else
    fail "make install-session: $(cat "$tmp/session.log")"
fi

printf 'session_test.sh: %d passed, %d failed\n' "$passes" "$failures"
test "$failures" -eq 0
