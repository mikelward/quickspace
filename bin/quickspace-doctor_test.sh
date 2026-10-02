#!/bin/sh
#
# Tests for bin/quickspace-doctor, against recorded answers from fake
# systemctl, busctl, pgrep and hyprctl, and portal
# directories under a temporary XDG tree.

cd "$(dirname "$0")/.." || exit 1
doctor=$PWD/bin/quickspace-doctor

passes=0
failures=0
pass() { passes=$((passes + 1)); }
fail() {
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$1" >&2
}
check() {
    _name=$1
    shift
    if "$@"; then pass; else fail "$_name"; fi
}
contains() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
fake=$tmp/bin
mkdir "$fake"

# systemctl --user is-active UNIT answers active, or $FAKE_INACTIVE's state
# for the unit it names (UNIT=STATE). $FAKE_AUTOSTART_UNITS holds autostart
# units as NAME=STARTED words, STARTED being the unit's
# ExecMainStartTimestampMonotonic (0: its command never started); list-units
# and show answer from it, or fail with $FAKE_LIST_FAILS or $FAKE_SHOW_FAILS.
cat > "$fake/systemctl" <<'FAKE'
#!/bin/sh
if test "$2" = list-units; then
    printf '%s\n' "$*" > "$FAKE_TMP/systemctl-args"
    if test -n "$FAKE_LIST_FAILS"; then
        echo "$FAKE_LIST_FAILS" >&2
        exit 1
    fi
    # One unit per "NAME=STARTED" word; list-units prints its name.
    for u in $FAKE_AUTOSTART_UNITS; do
        printf '%s loaded inactive dead x\n' "${u%%=*}"
    done
    exit 0
fi
if test "$2" = show && test "$4" = MainPID; then
    if test -n "$FAKE_MAINPID_FAILS"; then
        echo "$FAKE_MAINPID_FAILS" >&2
        exit 1
    fi
    echo "${FAKE_MAIN_PID:-100}"
    exit 0
fi
if test "$2" = show && test "$4" = ActiveEnterTimestampMonotonic; then
    echo "${FAKE_SESSION_START:-100}"
    exit 0
fi
if test "$2" = show; then
    if test -n "$FAKE_SHOW_FAILS"; then
        echo "$FAKE_SHOW_FAILS" >&2
        exit 1
    fi
    shift 7 # --user show -p Id -p ExecMainStartTimestampMonotonic --
    for name in "$@"; do
        for u in $FAKE_AUTOSTART_UNITS; do
            if test "${u%%=*}" = "$name"; then
                printf 'Id=%s\nExecMainStartTimestampMonotonic=%s\n\n' "$name" "${u#*=}"
            fi
        done
    done
    exit 0
fi
case " $FAKE_INACTIVE " in
    *" $3="*) state=${FAKE_INACTIVE#*"$3"=}; echo "${state%% *}"; exit 3 ;;
esac
echo active
FAKE
# busctl --user status NAME: the owner is a file of that name in
# $FAKE_OWNED holding "COMM UNIT".
cat > "$fake/busctl" <<'FAKE'
#!/bin/sh
test -e "$FAKE_OWNED/$3" || { echo "Failed to get credentials: No such device or address" >&2; exit 1; }
read -r comm unit < "$FAKE_OWNED/$3"
printf 'PID=42\nComm=%s\nUserUnit=%s\n' "$comm" "$unit"
FAKE
# pgrep -u UID -x NAME: one pid per $FAKE_PROCS word (where _ stands for a
# space) that the regex NAME matches whole, or
# failing with $FAKE_PGREP_FAILS.
cat > "$fake/pgrep" <<'FAKE'
#!/bin/sh
if test -n "$FAKE_PGREP_FAILS"; then
    echo "$FAKE_PGREP_FAILS" >&2
    exit 3
fi
found=1
for p in $FAKE_PROCS; do
    # NAME is an extended regex, as in procps.
    if printf '%s\n' "$p" | tr _ ' ' | grep -Eqx -- "$4"; then
        # The pid is 100, or $FAKE_PID_NAME (- as _) if that's set.
        eval "pid=\${FAKE_PID_$(printf '%s' "$p" | tr -c 'A-Za-z0-9_' _):-100}"
        echo "$pid"
        found=0
    fi
done
exit $found
FAKE
# hyprctl configerrors prints $FAKE_CONFIGERRORS, or fails with
# $FAKE_HYPRCTL_FAILS.
cat > "$fake/hyprctl" <<'FAKE'
#!/bin/sh
if test -n "$FAKE_HYPRCTL_FAILS"; then
    echo "$FAKE_HYPRCTL_FAILS"
    exit 1
fi
printf '%s' "$FAKE_CONFIGERRORS"
FAKE
chmod +x "$fake"/*

# A healthy session: every owner in place, one of each daemon, the portal
# config installed, and no autostart unit running.
healthy() {
    rm -rf "${tmp:?}/owned" "${tmp:?}/proc" "${tmp:?}/config" "${tmp:?}/etc" "${tmp:?}/share"
    mkdir -p "$tmp/owned" "$tmp/config/xdg-desktop-portal" "$tmp/etc" "$tmp/share"
    echo "swaync quickspace.service" > "$tmp/owned/org.freedesktop.Notifications"
    echo "waybar quickspace.service" > "$tmp/owned/org.kde.StatusNotifierWatcher"
    echo "hypridle hypridle.service" > "$tmp/owned/org.freedesktop.ScreenSaver"
    # Every other fake pgrep match is pid 100, in quickspace.service.
    mkdir -p "$tmp/proc/100"
    echo "0::/user.slice/user-1000.slice/user@1000.service/session.slice/quickspace.service" > "$tmp/proc/100/cgroup"
    # hypridle is pid 101, in its own unit.
    mkdir -p "$tmp/proc/101"
    echo "0::/user.slice/user-1000.slice/user@1000.service/session.slice/hypridle.service" > "$tmp/proc/101/cgroup"
    printf 'HOME=/home/user\0' > "$tmp/proc/100/environ"
    cp xdg-desktop-portal/quickspace-portals.conf "$tmp/config/xdg-desktop-portal/"
}

# run ENV...: runs the doctor in a quickspace session unless ENV says
# otherwise, with the given fakes' answers.
run() {
    env PATH="$fake:$PATH" FAKE_OWNED="$tmp/owned" FAKE_TMP="$tmp" \
        XDG_CURRENT_DESKTOP=quickspace:Hyprland XDG_CONFIG_HOME="$tmp/config" QUICKSPACE_PROC="$tmp/proc" \
        XDG_CONFIG_DIRS="$tmp/etc" XDG_DATA_HOME="$tmp/no-data-home" XDG_DATA_DIRS="$tmp/share" \
        FAKE_PROCS="hypridle swaync waybar hyprpolkitagent" FAKE_PID_hypridle=101 \
        "$@" sh "$doctor" > "$tmp/out" 2> "$tmp/err"
    status=$?
    out=$(cat "$tmp/out")
}

healthy
run
check "a healthy session exits 0" test "$status" -eq 0
check "a healthy session says so" test "$out" = "No problems found."

run XDG_CURRENT_DESKTOP=KDE
check "outside quickspace it exits 2" test "$status" -eq 2
check "outside quickspace it says why" contains "$(cat "$tmp/err")" "not in a quickspace session"

run FAKE_INACTIVE="hypridle.service=failed"
check "a failed unit is a problem" test "$status" -eq 1
check "a failed unit is named, with where to look" \
    contains "$out" "hypridle.service is failed: see \`systemctl --user status hypridle.service\`"

healthy
rm "$tmp/owned/org.freedesktop.ScreenSaver"
run
check "a missing owner is reported with busctl's error" \
    contains "$out" "org.freedesktop.ScreenSaver has no owner (Failed to get credentials: No such device or address): hypridle.service should own it"

healthy
echo "dunst app-dunst@autostart.service" > "$tmp/owned/org.freedesktop.Notifications"
run
check "a name owned by the wrong unit names the owner" \
    contains "$out" "org.freedesktop.Notifications is owned by dunst in app-dunst@autostart.service, not quickspace.service"

healthy
run FAKE_PROCS="hypridle hypridle swaync waybar hyprpolkitagent"
check "a daemon running twice is a problem" contains "$out" "2 hypridle processes are running"
run FAKE_PROCS="hypridle swaync waybar hyprpolkitagent swww-daemon swww-daemon"
check "two wallpaper daemons are a problem" contains "$out" "2 swww-daemon processes are running"

healthy
mkdir -p "$tmp/proc/200"
echo "0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-swww.scope" > "$tmp/proc/200/cgroup"
run FAKE_PROCS="hypridle swaync waybar hyprpolkitagent swww-daemon" FAKE_PID_swww_daemon=200
check "a daemon outside its unit is a problem, named by its scope" contains "$out" "swww-daemon (pid 200) runs in app-swww.scope, not quickspace.service"

run FAKE_PROCS="hypridle swaync waybar hyprpolkitagent polkit-gnome-au"
check "two polkit agents are a problem" contains "$out" "2 polkit agents are running"

run FAKE_PROCS="hypridle swaync waybar hyprpolkitagent mako"
check "a rival daemon is a problem" contains "$out" "mako is running, but quickspace owns its job"
run FAKE_PROCS="hypridle swaync waybar hyprpolkitagent swayidle"
check "swayidle is a rival to hypridle" contains "$out" "swayidle is running, but quickspace owns its job"
run FAKE_PROCS="hypridle swaync waybar hyprpolkitagent swaybg"
check "the shell's own swaybg isn't a problem" test -z "$(grep swaybg "$tmp/out")"
run FAKE_PROCS="hypridle swaync waybar hyprpolkitagent swww-daemon swaybg"
check "swww-daemon and swaybg together are a problem, even in the unit" \
    contains "$out" "swww-daemon and swaybg are both running"
run FAKE_PROCS="hypridle swaync waybar hyprpolkitagent swaybg" FAKE_PID_swaybg=200
check "a swaybg outside the shell is a problem" \
    contains "$out" "swaybg (pid 200) runs in app-swww.scope, not quickspace.service"

run FAKE_PROCS="hypridle swaync waybar"
check "no polkit agent is a problem" contains "$out" "no polkit agent is running"

healthy
printf '%s\n' '0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-polkit\x2dgnome@autostart.service' > "$tmp/proc/100/cgroup"
run FAKE_PROCS="hypridle swaync waybar polkit-gnome-au"
check "a polkit agent outside quickspace.service is a problem" \
    contains "$out" "the polkit agent (pid 100) runs in app-polkit\\x2dgnome@autostart.service, not quickspace.service"
rm "$tmp/proc/100/cgroup"
run
check "a polkit agent with no cgroup (gone) is reported with no unit" contains "$out" "runs in no user unit"
healthy

healthy
printf 'HOME=/home/user\0QUICKSPACE_POLKIT_AGENT=/opt/agents/my-polkit-agent-with-a-long-name\0' > "$tmp/proc/100/environ"
run FAKE_PROCS="hypridle swaync waybar my-polkit-agent"
check "an agent set with QUICKSPACE_POLKIT_AGENT counts, by its first 15 characters" test -z "$(grep 'polkit agent' "$tmp/out")"
printf 'QUICKSPACE_POLKIT_AGENTS=/opt/a/agent-one /opt/b/agent-two\0' > "$tmp/proc/100/environ"
run FAKE_PROCS="hypridle swaync waybar agent-two"
check "an agent from QUICKSPACE_POLKIT_AGENTS counts" test -z "$(grep 'polkit agent' "$tmp/out")"
printf 'QUICKSPACE_POLKIT_AGENT=/opt/My Agent/bin/my agent\0' > "$tmp/proc/100/environ"
run FAKE_PROCS="hypridle swaync waybar my_agent"
check "a QUICKSPACE_POLKIT_AGENT path with spaces is one agent" test -z "$(grep 'polkit agent' "$tmp/out")"
printf 'QUICKSPACE_POLKIT_AGENT=/opt/bin/agent+foo\0' > "$tmp/proc/100/environ"
run FAKE_PROCS="hypridle swaync waybar agent+foo"
check "a configured agent name is matched literally, not as a regex" test -z "$(grep 'polkit agent' "$tmp/out")"
run FAKE_PROCS="hypridle swaync waybar agenttfoo"
check "a configured agent name's metacharacters match only themselves" contains "$out" "no polkit agent is running"
healthy

healthy
run FAKE_MAINPID_FAILS="Failed to connect to bus"
check "failing to read the shell's MainPID is a problem" \
    contains "$out" "couldn't read quickspace.service's MainPID (Failed to connect to bus), so an agent set with QUICKSPACE_POLKIT_AGENT may be missed"
rm "$tmp/proc/100/environ"
run FAKE_PROCS="hypridle swaync waybar"
check "an unreadable shell environment is a problem" \
    contains "$out" "couldn't read quickspace.service's environment (pid 100:"
check "an unreadable shell environment doesn't claim there's no polkit agent" test -z "$(grep 'no polkit agent' "$tmp/out")"
run FAKE_PROCS="hypridle swaync waybar" FAKE_MAIN_PID=0 FAKE_INACTIVE=quickspace.service=inactive
check "a stopped shell has no environment to read" test -z "$(grep "quickspace.service's environment" "$tmp/out")"
healthy

run FAKE_PGREP_FAILS="cannot read /proc"
check "pgrep failing is a problem, not a clean bill" test "$status" -eq 1
check "pgrep failing doesn't claim there's no polkit agent" test -z "$(grep 'no polkit agent' "$tmp/out")"
check "pgrep failing is reported once, with its error" \
    test "$(grep -c 'pgrep failed (3: cannot read /proc), so the process checks are incomplete' "$tmp/out")" -eq 1

run XDG_CURRENT_DESKTOP=Hyprland:quickspace
check "quickspace not first in XDG_CURRENT_DESKTOP is a problem" \
    contains "$out" "XDG_CURRENT_DESKTOP is 'Hyprland:quickspace': quickspace must come first"

healthy
rm "$tmp/config/xdg-desktop-portal/quickspace-portals.conf"
run
check "a missing portal config is a problem" contains "$out" "quickspace-portals.conf isn't installed"
mkdir -p "$tmp/data/xdg-desktop-portal"
cp xdg-desktop-portal/quickspace-portals.conf "$tmp/data/xdg-desktop-portal/"
run XDG_DATA_HOME="$tmp/data"
check "a portal config under XDG_DATA_HOME counts" test "$status" -eq 0
rm -r "$tmp/data"
mkdir -p "$tmp/share/xdg-desktop-portal"
cp xdg-desktop-portal/quickspace-portals.conf "$tmp/share/xdg-desktop-portal/"
run
check "a portal config under XDG_DATA_DIRS counts" test "$status" -eq 0

healthy
printf '[preferred]\ndefault=kde\n' > "$tmp/config/xdg-desktop-portal/quickspace-portals.conf"
# A good one later in the search path doesn't help: only the first is read.
mkdir -p "$tmp/share/xdg-desktop-portal"
cp xdg-desktop-portal/quickspace-portals.conf "$tmp/share/xdg-desktop-portal/"
run
check "the first portal config found must be the shipped one" \
    contains "$out" "$tmp/config/xdg-desktop-portal/quickspace-portals.conf isn't the one quickspace ships"
: > "$tmp/config/xdg-desktop-portal/quickspace-portals.conf"
run
check "an empty portal config is a problem" contains "$out" "isn't the one quickspace ships"
{ echo "not a key file line"; cat xdg-desktop-portal/quickspace-portals.conf; } > "$tmp/config/xdg-desktop-portal/quickspace-portals.conf"
run
check "an edited portal config is a problem even with the right default" contains "$out" "isn't the one quickspace ships"
chmod 000 "$tmp/config/xdg-desktop-portal/quickspace-portals.conf"
if ! cat "$tmp/config/xdg-desktop-portal/quickspace-portals.conf" >/dev/null 2>&1; then
    run
    check "an unreadable portal config is reported" contains "$out" "couldn't read $tmp/config/xdg-desktop-portal/quickspace-portals.conf"
fi # root reads it anyway
chmod 644 "$tmp/config/xdg-desktop-portal/quickspace-portals.conf"

# The doctor's copy of the shipped config must match the repo's.
check "the doctor's copy of quickspace-portals.conf is the shipped one" \
    test "$(sed -n "/^    cat <<'EOF'$/,/^EOF$/p" "$doctor" | sed '1d;$d')" = "$(cat xdg-desktop-portal/quickspace-portals.conf)"

healthy
run FAKE_CONFIGERRORS="$(printf 'line 3: bad keyword\nline 9: bad value\n')"
check "each config error is a problem" test "$(grep -c '^Hyprland config error' "$tmp/out")" -eq 2
check "config errors fail the check" test "$status" -eq 1
run FAKE_HYPRCTL_FAILS="HYPRLAND_INSTANCE_SIGNATURE not set"
check "hyprctl failing is reported" \
    contains "$out" "hyprctl configerrors failed (HYPRLAND_INSTANCE_SIGNATURE not set)"

healthy
run FAKE_AUTOSTART_UNITS="app-nm\\x2dapplet@autostart.service=123 app-hplip\\x2dsystray@autostart.service=789 app-oneshot@autostart.service=456 app-skipped@autostart.service=0 app-earlier@autostart.service=50"
check "each autostart unit off the allowlist whose command started is a problem" \
    test "$(grep -c '^autostart unit' "$tmp/out")" -eq 2
check "an autostart unit that ran and exited counts" contains "$out" "autostart unit app-oneshot@autostart.service ran in quickspace"
check "an autostart unit is named, with the fix" \
    contains "$out" "autostart unit app-hplip\\x2dsystray@autostart.service ran in quickspace but isn't on the autostart allowlist: run quickspace's make install, whose app-.service.d drop-in skips it, then systemctl --user daemon-reload, then systemctl --user stop 'app-hplip\\x2dsystray@autostart.service'"
check "an allowlisted autostart unit isn't a problem" test -z "$(grep 'nm\\x2dapplet' "$tmp/out")"
check "a unit whose condition stopped its command isn't a problem" test -z "$(grep 'app-skipped' "$tmp/out")"
check "a unit that ran before this session began isn't a problem" test -z "$(grep 'app-earlier' "$tmp/out")"
check "systemctl is asked for every loaded autostart unit, dead ones too" \
    contains "$(cat "$tmp/systemctl-args")" "list-units --all --plain --no-legend app-*@autostart.service"
run FAKE_AUTOSTART_UNITS="app-hplip\\x2dsystray@autostart.service=789" QUICKSPACE_CMD="$tmp/no-such-quickspace"
check "a failed allowlist check is reported as one, not as a unit off the list" \
    contains "$out" "couldn't check autostart unit app-hplip\\x2dsystray@autostart.service against the allowlist ("
check "a failed allowlist check doesn't suggest allowing the unit" test -z "$(grep "isn't on the autostart allowlist" "$tmp/out")"
run FAKE_LIST_FAILS="Failed to connect to bus"
check "systemctl failing to list the units is a problem" \
    contains "$out" "systemctl couldn't read the autostart units (Failed to connect to bus)"
run FAKE_AUTOSTART_UNITS="app-x@autostart.service=1" FAKE_SHOW_FAILS="Access denied"
check "systemctl failing to show the units is a problem" \
    contains "$out" "systemctl couldn't read the autostart units (Access denied)"

doctor_out=$(env PATH="$fake:$PATH" XDG_CURRENT_DESKTOP=KDE sh bin/quickspace doctor 2>&1)
check "quickspace doctor runs it" contains "$doctor_out" "quickspace-doctor: not in a quickspace session"

if command -v shellcheck >/dev/null 2>&1; then
    check "shellcheck passes" shellcheck -s sh "$doctor" bin/quickspace-doctor_test.sh
fi

printf 'quickspace-doctor_test.sh: %d passed, %d failed\n' "$passes" "$failures"
test "$failures" -eq 0
