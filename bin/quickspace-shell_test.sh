#!/bin/sh
#
# Tests for bin/quickspace-shell, with a fake theme daemon, polkit agent,
# busctl and systemd-notify. A name's owner is described by a file of that
# name in $FAKE_OWNED, which the fake theme daemon fills with the owner's
# unit ($FAKE_UNIT, quickspace.service by default).

cd "$(dirname "$0")/.." || exit 1
shell=$PWD/bin/quickspace-shell

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
# The long-lived fakes record their pids here, to be stopped after each run.
cleanup() {
    if test -s "$tmp/pids"; then
        # shellcheck disable=SC2046  # one pid per line
        kill $(cat "$tmp/pids") 2>/dev/null # a fake may have exited already
    fi
    : > "$tmp/pids"
}
trap 'cleanup; rm -rf "$tmp"' EXIT
fake=$tmp/bin
mkdir "$fake"

cat > "$fake/busctl" <<'FAKE'
#!/bin/sh
# busctl --user status NAME
test -e "$FAKE_OWNED/$3" || { echo "Failed to get credentials: No such device or address" >&2; exit 1; }
printf 'PID=1\nComm=fake\nUserUnit=%s\n' "$(cat "$FAKE_OWNED/$3")"
FAKE
# sleep fails for the delay in $FAKE_SLEEP_FAILS and is the real one
# otherwise.
cat > "$fake/sleep" <<FAKE
#!/bin/sh
if test -n "\$FAKE_SLEEP_FAILS" && test "\$1" = "\$FAKE_SLEEP_FAILS"; then
    echo "sleep: broken" >&2
    exit 1
fi
exec $(command -v sleep) "\$@"
FAKE
cat > "$fake/systemd-notify" <<'FAKE'
#!/bin/sh
printf 'systemd-notify %s\n' "$*" >> "$FAKE_LOG"
exit "${FAKE_NOTIFY_STATUS:-0}"
FAKE
# Claims the names in $FAKE_NAMES, then exits, which ends the shell's wait;
# with $FAKE_DAEMON_STAYS it stays up until the test kills it.
cat > "$tmp/theme-daemon" <<'FAKE'
#!/bin/sh
printf 'theme-daemon\n' >> "$FAKE_LOG"
for n in $FAKE_NAMES; do echo "${FAKE_UNIT:-quickspace.service}" > "$FAKE_OWNED/$n"; done
if test -n "$FAKE_DAEMON_STAYS"; then
    echo $$ >> "$FAKE_PIDS"
    exec sleep 600 >/dev/null 2>&1
fi
exit "${FAKE_DAEMON_EXIT:-0}"
FAKE
# Stays up until the test kills it, or exits at once with $FAKE_AGENT_EXIT,
# the first time only with $FAKE_AGENT_EXIT_ONCE; started again after that,
# it says so on stderr. With $FAKE_AGENT_PIDFILE it records its pid there,
# where the test's cleanup won't kill it, and says it's running.
cat > "$tmp/agent" <<'FAKE'
#!/bin/sh
printf 'agent\n' >> "$FAKE_LOG"
if test -n "$FAKE_AGENT_PIDFILE"; then
    echo $$ > "$FAKE_AGENT_PIDFILE"
    echo "fake agent running" >&2
    exec sleep 600 >/dev/null 2>&1
fi
if test -n "$FAKE_AGENT_EXIT_ONCE" && test -e "$FAKE_OWNED/agent-ran"; then
    echo "fake agent started again" >&2
elif test -n "$FAKE_AGENT_EXIT"; then
    : > "$FAKE_OWNED/agent-ran"
    exit "$FAKE_AGENT_EXIT"
fi
echo $$ >> "$FAKE_PIDS"
exec sleep 600 >/dev/null 2>&1
FAKE
# swww-daemon stays up and starts answering at once; swww answers `query`
# once the daemon is up (never, printing $FAKE_QUERY_ERR, if that's set)
# and logs `img`, failing it with $FAKE_IMG_FAILS.
# They're in their own directory so a run can leave them off the PATH.
swww=$tmp/swww-bin
mkdir "$swww"
cat > "$swww/swww-daemon" <<'FAKE'
#!/bin/sh
: > "$FAKE_OWNED/swww-up"
echo $$ >> "$FAKE_PIDS"
exec sleep 600 >/dev/null 2>&1
FAKE
cat > "$swww/swww" <<'FAKE'
#!/bin/sh
case "$1" in
    query)
        if test -n "$FAKE_QUERY_ERR"; then
            echo "$FAKE_QUERY_ERR" >&2
            exit 1
        fi
        test -e "$FAKE_OWNED/swww-up"
        ;;
    img)
        printf 'swww img %s\n' "$2" >> "$FAKE_LOG"
        test -z "$FAKE_IMG_FAILS"
        ;;
esac
FAKE
# swaybg logs its arguments and stays up; it's in its own directory too.
swaybg=$tmp/swaybg-bin
mkdir "$swaybg"
cat > "$swaybg/swaybg" <<'FAKE'
#!/bin/sh
printf 'swaybg %s\n' "$*" >> "$FAKE_LOG"
echo $$ >> "$FAKE_PIDS"
exec sleep 600 >/dev/null 2>&1
FAKE
cat > "$tmp/input-setup" <<'FAKE'
#!/bin/sh
printf 'input-setup\n' >> "$FAKE_LOG"
exit "${FAKE_INPUT_STATUS:-0}"
FAKE
: > "$tmp/wallpaper.jpg"
chmod +x "$fake"/* "$swww"/* "$swaybg"/* "$tmp/theme-daemon" "$tmp/agent" "$tmp/input-setup"

both="org.freedesktop.Notifications org.kde.StatusNotifierWatcher"

# run ENV...: runs the shell with the fakes. With $stop_on set, the fakes are
# stopped as soon as the shell prints a line containing it, which ends a
# shell that would otherwise run for the session.
stop_on=
run() {
    rm -rf "$tmp/owned"
    mkdir "$tmp/owned"
    : > "$tmp/log"
    # stderr goes through a pipe, so `cat` finishes only once every writer
    # has: the shell, and the agent's watcher once cleanup stops the agent.
    # The long-lived fakes drop the pipe, so they can't hold it open.
    {
        env PATH="$fake:$swww:$PATH" FAKE_OWNED="$tmp/owned" FAKE_LOG="$tmp/log" FAKE_PIDS="$tmp/pids" \
            QUICKSPACE_THEME_DAEMON="$tmp/theme-daemon" QUICKSPACE_POLKIT_AGENT="$tmp/agent" \
            QUICKSPACE_WALLPAPER="$tmp/wallpaper.jpg" QUICKSPACE_INPUT_SETUP="$tmp/input-setup" \
            QUICKSPACE_SHELL_WAIT=1 "$@" sh "$shell" 2>&1 >/dev/null
        echo $? > "$tmp/status"
        cleanup
    } | while IFS= read -r line; do
        printf '%s\n' "$line"
        if test -n "$stop_on"; then
            case "$line" in *"$stop_on"*) cleanup ;; esac
        fi
    done > "$tmp/err"
    status=$(cat "$tmp/status")
}

run FAKE_NAMES="$both"
log=$(cat "$tmp/log")
check "the theme daemon starts" contains "$log" "theme-daemon"
check "the polkit agent starts" contains "$log" "agent"
check "ready is reported once both names are owned" contains "$log" "systemd-notify --ready"
# The fake daemon exits right away; in a session that means the bar is gone.
check "the theme daemon exiting ends the shell with a failure" test "$status" -ne 0
check "the exit is reported" contains "$(cat "$tmp/err")" "the theme daemon exited"
check "the wallpaper is set" contains "$log" "swww img $tmp/wallpaper.jpg"
check "the input setup runs" contains "$log" "input-setup"

run FAKE_NAMES="$both" FAKE_IMG_FAILS=1 FAKE_INPUT_STATUS=4
check "a failed wallpaper doesn't hold up ready" contains "$(cat "$tmp/log")" "systemd-notify --ready"
check "a failed wallpaper is reported" contains "$(cat "$tmp/err")" "swww img $tmp/wallpaper.jpg failed"
check "a failed input setup is reported" contains "$(cat "$tmp/err")" "input-setup failed (4)"

run FAKE_NAMES="$both" QUICKSPACE_WALLPAPER="$tmp/missing.jpg"
check "a missing QUICKSPACE_WALLPAPER fails, not to be retried" test "$status" -eq 78
check "a missing QUICKSPACE_WALLPAPER is reported by name" \
    contains "$(cat "$tmp/err")" "QUICKSPACE_WALLPAPER is '$tmp/missing.jpg'"
check "a missing QUICKSPACE_WALLPAPER starts nothing" test ! -s "$tmp/log"

run FAKE_NAMES="$both" QUICKSPACE_INPUT_SETUP="$tmp/no-such-setup"
check "a missing QUICKSPACE_INPUT_SETUP fails, not to be retried" test "$status" -eq 78
check "a missing QUICKSPACE_INPUT_SETUP is reported by name" \
    contains "$(cat "$tmp/err")" "QUICKSPACE_INPUT_SETUP is '$tmp/no-such-setup'"

# swww-daemon never answers: once ready, the shell reports it with swww's
# last error, then runs for the session as usual.
stop_on="never answered"
run FAKE_NAMES="$both" FAKE_DAEMON_STAYS=1 FAKE_QUERY_ERR="swww: protocol version mismatch"
stop_on=
check "a daemon that never answers doesn't hold up ready" contains "$(cat "$tmp/log")" "systemd-notify --ready"
check "a daemon that never answers is reported with swww's error" \
    contains "$(cat "$tmp/err")" "swww-daemon never answered; no wallpaper (last swww query error: swww: protocol version mismatch)"

# The theme daemon exiting while the wallpaper waits ends the shell at once,
# rather than after the wallpaper's wait (30 s here).
run FAKE_NAMES="$both" FAKE_QUERY_ERR="not up" QUICKSPACE_SHELL_WAIT=30
check "the theme daemon exiting during the wallpaper wait ends the shell" \
    contains "$(cat "$tmp/err")" "the theme daemon exited"
check "it doesn't wait out the wallpaper first" \
    test -z "$(grep 'never answered' "$tmp/err")"

# swww-daemon without its client.
mkdir "$tmp/daemon-only"
cp "$swww/swww-daemon" "$tmp/daemon-only/"
if ! command -v swww >/dev/null 2>&1 && ! command -v swaybg >/dev/null 2>&1; then
    run FAKE_NAMES="$both" PATH="$fake:$tmp/daemon-only:$PATH"
    check "swww-daemon without swww is reported" \
        contains "$(cat "$tmp/err")" "swww-daemon is installed but its client, swww, isn't, and swaybg isn't installed either"
    check "swww-daemon without swww isn't started" test ! -e "$tmp/owned/swww-up"
fi

# Without swww or swaybg on the PATH; skipped where the host has a real one,
# which this run would otherwise start.
if ! command -v swww-daemon >/dev/null 2>&1 && ! command -v swaybg >/dev/null 2>&1; then
    run FAKE_NAMES="$both" PATH="$fake:$PATH"
    check "no wallpaper program is reported" contains "$(cat "$tmp/err")" "neither swww nor swaybg is installed; no wallpaper"
    check "no wallpaper program doesn't hold up ready" contains "$(cat "$tmp/log")" "systemd-notify --ready"
fi

# swaybg stands in for swww; skipped where the host has a real swww, which
# this run would prefer.
if ! command -v swww-daemon >/dev/null 2>&1; then
    run FAKE_NAMES="$both" PATH="$fake:$swaybg:$PATH"
    check "without swww, swaybg shows the wallpaper" contains "$(cat "$tmp/log")" "swaybg -m fill -i $tmp/wallpaper.jpg"
    check "swaybg doesn't hold up ready" contains "$(cat "$tmp/log")" "systemd-notify --ready"
    # The default wallpaper, under a HOME that has none.
    run FAKE_NAMES="$both" PATH="$fake:$swaybg:$PATH" QUICKSPACE_WALLPAPER= HOME="$tmp/no-home"
    check "swaybg isn't started without a wallpaper" test -z "$(grep '^swaybg' "$tmp/log")"
    check "a missing wallpaper is reported" contains "$(cat "$tmp/err")" "no wallpaper at $tmp/no-home/.config/hypr/wallpaper.jpg"
fi
run FAKE_NAMES="$both" PATH="$fake:$swww:$swaybg:$PATH"
check "swww is preferred to swaybg" test -z "$(grep '^swaybg' "$tmp/log")"

run FAKE_NAMES="org.freedesktop.Notifications" FAKE_DAEMON_STAYS=1
check "a missing owner fails the start" test "$status" -eq 1
check "a missing owner never reports ready" \
    test -z "$(grep systemd-notify "$tmp/log")"
check "the failure names the missing owner" \
    contains "$(cat "$tmp/err")" "no owner in quickspace.service for: org.kde.StatusNotifierWatcher"
check "the failure doesn't name an owner that is there" \
    test -z "$(grep 'org.freedesktop.Notifications' "$tmp/err")"

run FAKE_NAMES="org.freedesktop.Notifications" FAKE_DAEMON_STAYS=1
check "the failure passes on busctl's last error" \
    contains "$(cat "$tmp/err")" "(last busctl error: Failed to get credentials: No such device or address)"

run FAKE_NAMES="org.freedesktop.Notifications" FAKE_DAEMON_EXIT=5
check "a theme daemon that exits early fails the start" test "$status" -eq 1
check "its exit status is reported" contains "$(cat "$tmp/err")" "the theme daemon exited (5) before its owners were up"
check "it isn't reported as a timeout" test -z "$(grep 'not ready after' "$tmp/err")"

run FAKE_NAMES="$both" FAKE_UNIT=other.service FAKE_DAEMON_STAYS=1
check "a name owned outside the unit doesn't count" test "$status" -eq 1
check "a name owned outside the unit never reports ready" \
    test -z "$(grep systemd-notify "$tmp/log")"

# An agent exits at once when another holds the session: the shell carries
# on to ready, and ends only when the theme daemon does.
run FAKE_NAMES="$both" FAKE_AGENT_EXIT=3
check "the polkit agent exiting doesn't stop ready" contains "$(cat "$tmp/log")" "systemd-notify --ready"
check "the agent's exit is reported" contains "$(cat "$tmp/err")" "the polkit agent exited (3); the shell keeps running and starts it again in 5 s"
check "the shell ends with the theme daemon, not the agent" contains "$(cat "$tmp/err")" "the theme daemon exited (0)"

# Once the other agent goes, or after a crash, the agent is started again.
stop_on="fake agent started again"
run FAKE_NAMES="$both" FAKE_DAEMON_STAYS=1 FAKE_AGENT_EXIT=3 FAKE_AGENT_EXIT_ONCE=1 QUICKSPACE_AGENT_RETRY=1
stop_on=
check "an agent that exited is started again" test "$(grep -c '^agent$' "$tmp/log")" -eq 2
check "its restart delay is reported" contains "$(cat "$tmp/err")" "starts it again in 1 s"

# Without a working sleep there's no backoff, so the agent isn't respawned.
stop_on="not starting the polkit agent again"
run FAKE_NAMES="$both" FAKE_DAEMON_STAYS=1 FAKE_AGENT_EXIT=3 QUICKSPACE_AGENT_RETRY=1 FAKE_SLEEP_FAILS=1
stop_on=
check "a failed backoff sleep is reported" contains "$(cat "$tmp/err")" "sleep 1 failed; not starting the polkit agent again"
check "with sleep's own error" contains "$(cat "$tmp/err")" "sleep: broken"
check "a loop that gave up isn't signaled at exit" test -z "$(grep 'kill:' "$tmp/err")"
check "a failed backoff sleep starts no more agents" test "$(grep -c '^agent$' "$tmp/log")" -eq 1

# The shell's exit stops the agent itself, not just its restart loop.
stop_on="fake agent running"
run FAKE_NAMES="$both" FAKE_DAEMON_STAYS=1 FAKE_AGENT_PIDFILE="$tmp/agent.pid"
stop_on=
check "the shell's exit stops the running agent" test -s "$tmp/agent.pid"
if test -s "$tmp/agent.pid"; then
    agent_pid=$(cat "$tmp/agent.pid")
    # kill -0 failing (no such process) is the pass.
    if kill -0 "$agent_pid" 2>/dev/null; then
        kill "$agent_pid"
        fail "the agent outlived the shell"
    else
        pass
    fi
fi

run FAKE_NAMES="$both" QUICKSPACE_AGENT_RETRY=61
check "a QUICKSPACE_AGENT_RETRY over a minute fails the start, not to be retried" test "$status" -eq 78
check "a bad QUICKSPACE_AGENT_RETRY is reported" contains "$(cat "$tmp/err")" "QUICKSPACE_AGENT_RETRY must be a whole number of seconds from 1 to 60, not '61'"
for bad in x 0 08; do
    run FAKE_NAMES="$both" QUICKSPACE_AGENT_RETRY=$bad
    check "QUICKSPACE_AGENT_RETRY=$bad fails the start" test "$status" -eq 78
done

run FAKE_NAMES="$both" FAKE_NOTIFY_STATUS=1
check "a failed ready notification fails the start" test "$status" -eq 1
check "a failed ready notification is reported" \
    contains "$(cat "$tmp/err")" "systemd-notify --ready failed"

run FAKE_NAMES="$both"
check "the default wait fits the unit's timeout, so it isn't extended" \
    test -z "$(grep EXTEND_TIMEOUT "$tmp/log")"
run FAKE_NAMES="$both" QUICKSPACE_SHELL_WAIT=30
check "a longer wait extends the unit's start timeout past it" \
    contains "$(cat "$tmp/log")" "systemd-notify EXTEND_TIMEOUT_USEC=33000000"
run FAKE_NAMES="$both" QUICKSPACE_SHELL_WAIT=30 FAKE_NOTIFY_STATUS=1
check "a refused extension is reported" \
    contains "$(cat "$tmp/err")" "couldn't extend the start timeout for QUICKSPACE_SHELL_WAIT=30"

for bad in 0 abc 1.5 -1 3601 999999999999999999999; do
    run FAKE_NAMES="$both" QUICKSPACE_SHELL_WAIT="$bad"
    check "QUICKSPACE_SHELL_WAIT=$bad fails the start, not to be retried" test "$status" -eq 78
    check "QUICKSPACE_SHELL_WAIT=$bad is reported by name" \
        contains "$(cat "$tmp/err")" "QUICKSPACE_SHELL_WAIT must be a whole number of seconds from 1 to 3600, not '$bad'"
    check "QUICKSPACE_SHELL_WAIT=$bad starts nothing" test ! -s "$tmp/log"
done

run FAKE_NAMES="$both" QUICKSPACE_POLKIT_AGENT="$tmp/no-such-agent"
check "a missing QUICKSPACE_POLKIT_AGENT fails the start, not to be retried" test "$status" -eq 78
check "a missing QUICKSPACE_POLKIT_AGENT is reported by name" \
    contains "$(cat "$tmp/err")" "QUICKSPACE_POLKIT_AGENT is '$tmp/no-such-agent'"
check "a missing QUICKSPACE_POLKIT_AGENT starts nothing" test ! -s "$tmp/log"

mkdir "$tmp/agent-dir"
run FAKE_NAMES="$both" QUICKSPACE_POLKIT_AGENT="$tmp/agent-dir"
check "a directory as QUICKSPACE_POLKIT_AGENT is rejected" test "$status" -eq 78
check "a directory as QUICKSPACE_POLKIT_AGENT starts nothing" test ! -s "$tmp/log"

run FAKE_NAMES="$both" QUICKSPACE_THEME_DAEMON="$tmp/nonexistent"
check "a missing theme daemon fails at once, not to be retried" test "$status" -eq 78
check "a missing QUICKSPACE_THEME_DAEMON is reported by name" \
    contains "$(cat "$tmp/err")" "QUICKSPACE_THEME_DAEMON is '$tmp/nonexistent'"

run FAKE_NAMES="$both" QUICKSPACE_THEME_DAEMON= HOME="$tmp/empty-home"
check "a missing default theme daemon fails, not to be retried" test "$status" -eq 78
check "a missing default theme daemon is reported" \
    contains "$(cat "$tmp/err")" "no theme daemon at $tmp/empty-home/.config/hypr/scripts/theme-daemon.sh"

# An empty search list, so no agent installed on this host is found.
run FAKE_NAMES="$both" QUICKSPACE_POLKIT_AGENT= QUICKSPACE_POLKIT_AGENTS=
check "the shell still gets ready without an agent" contains "$(cat "$tmp/log")" "systemd-notify --ready"
check "a missing agent is reported" contains "$(cat "$tmp/err")" "no polkit agent found"

mkdir "$tmp/agents"
cp "$tmp/agent" "$tmp/agents/found-agent"
run FAKE_NAMES="$both" QUICKSPACE_POLKIT_AGENT= QUICKSPACE_POLKIT_AGENTS="$tmp/agents/missing $tmp/agents/found-agent"
check "the first installed agent on the search list starts" contains "$(cat "$tmp/log")" "agent"

# Debian puts KDE's agent under a multiarch directory, which the search
# matches with a pattern rather than naming each architecture.
# The default list's own pattern must match every Debian triplet, armhf's
# ABI-suffixed one included.
kde_pattern=$(sed -n 's|^ *\(/usr/lib/\*[^ ]*polkit-kde-authentication-agent-1\)$|\1|p' "$shell")
check "the shell searches KDE's multiarch directories by pattern" test -n "$kde_pattern"
for triplet in x86_64-linux-gnu aarch64-linux-gnu arm-linux-gnueabihf; do
    mkdir -p "$tmp/multi/$triplet/libexec"
    cp "$tmp/agent" "$tmp/multi/$triplet/libexec/polkit-kde-authentication-agent-1"
    run FAKE_NAMES="$both" QUICKSPACE_POLKIT_AGENT= QUICKSPACE_POLKIT_AGENTS="$tmp/multi${kde_pattern#/usr/lib}"
    check "KDE's agent under $triplet is found" contains "$(cat "$tmp/log")" "agent"
    check "KDE's agent under $triplet leaves no agent missing" test -z "$(grep "no polkit agent found" "$tmp/err")"
    rm -rf "$tmp/multi/$triplet"
done

if command -v shellcheck >/dev/null 2>&1; then
    check "shellcheck passes" shellcheck -s sh "$shell" bin/quickspace-shell_test.sh
fi

printf 'quickspace-shell_test.sh: %d passed, %d failed\n' "$passes" "$failures"
test "$failures" -eq 0
