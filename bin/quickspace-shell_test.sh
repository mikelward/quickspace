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
# Stays up until the test kills it, or exits at once with $FAKE_AGENT_EXIT.
cat > "$tmp/agent" <<'FAKE'
#!/bin/sh
printf 'agent\n' >> "$FAKE_LOG"
if test -n "$FAKE_AGENT_EXIT"; then
    exit "$FAKE_AGENT_EXIT"
fi
echo $$ >> "$FAKE_PIDS"
exec sleep 600 >/dev/null 2>&1
FAKE
chmod +x "$fake"/* "$tmp/theme-daemon" "$tmp/agent"

both="org.freedesktop.Notifications org.kde.StatusNotifierWatcher"

run() {
    rm -rf "$tmp/owned"
    mkdir "$tmp/owned"
    : > "$tmp/log"
    # stderr goes through a pipe, so `cat` finishes only once every writer
    # has: the shell, and the agent's watcher once cleanup stops the agent.
    # The long-lived fakes drop the pipe, so they can't hold it open.
    {
        env PATH="$fake:$PATH" FAKE_OWNED="$tmp/owned" FAKE_LOG="$tmp/log" FAKE_PIDS="$tmp/pids" \
            QUICKSPACE_THEME_DAEMON="$tmp/theme-daemon" QUICKSPACE_POLKIT_AGENT="$tmp/agent" \
            QUICKSPACE_SHELL_WAIT=1 "$@" sh "$shell" 2>&1 >/dev/null
        echo $? > "$tmp/status"
        cleanup
    } | cat > "$tmp/err"
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

run FAKE_NAMES="$both" FAKE_DAEMON_STAYS=1 FAKE_AGENT_EXIT=3
check "the polkit agent exiting ends the shell with a failure" test "$status" -eq 1
check "the agent's exit is reported" contains "$(cat "$tmp/err")" "the polkit agent exited (3)"

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

if command -v shellcheck >/dev/null 2>&1; then
    check "shellcheck passes" shellcheck -s sh "$shell" bin/quickspace-shell_test.sh
fi

printf 'quickspace-shell_test.sh: %d passed, %d failed\n' "$passes" "$failures"
test "$failures" -eq 0
