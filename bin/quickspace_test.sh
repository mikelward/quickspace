#!/bin/sh
#
# Tests for bin/quickspace, against fake systemctl, hyprctl and uwsm on PATH.

cd "$(dirname "$0")/.." || exit 1
qs=$PWD/bin/quickspace

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
log=$tmp/log

# Each fake logs its arguments. systemctl sleeps $FAKE_SYSTEMCTL_SLEEP and
# exits $FAKE_SYSTEMCTL_STATUS; hyprctl answers $FAKE_HYPRCTL_REPLY (ok by
# default); uwsm runs the command after --, as `uwsm app` does.
cat > "$fake/systemctl" <<'FAKE'
#!/bin/sh
printf "systemctl %s\n" "$*" >> "$FAKE_LOG"
sleep "${FAKE_SYSTEMCTL_SLEEP:-0}"
test "${FAKE_SYSTEMCTL_STATUS:-0}" -eq 0 || echo "Job failed" >&2
exit "${FAKE_SYSTEMCTL_STATUS:-0}"
FAKE
cat > "$fake/hyprctl" <<'FAKE'
#!/bin/sh
printf "hyprctl %s\n" "$*" >> "$FAKE_LOG"
echo "${FAKE_HYPRCTL_REPLY:-ok}"
FAKE
cat > "$fake/uwsm" <<'FAKE'
#!/bin/sh
printf "uwsm %s\n" "$*" >> "$FAKE_LOG"
while test "$1" != --; do shift; done
shift
exec "$@"
FAKE
cat > "$fake/app" <<'FAKE'
#!/bin/sh
printf "app %s\n" "$*" >> "$FAKE_LOG"
FAKE
chmod +x "$fake"/*

# run ENV... -- ARGS...: runs quickspace with the fakes first on PATH, in a
# quickspace session unless the env says otherwise.
run() {
    : > "$log"
    env PATH="$fake:$PATH" FAKE_LOG="$log" XDG_CURRENT_DESKTOP=quickspace:Hyprland \
        "$@" 2> "$tmp/err"
}

run "$qs" launch app one two
check "launch exits 0" test $? -eq 0
out=$(cat "$log")
check "launch waits for the shell" contains "$out" "systemctl --user start quickspace.service"
check "launch grants focus to the command's basename" \
    contains "$out" 'hyprctl eval quickspace_focus.grant("app")'
check "launch runs the app through uwsm app" contains "$out" "uwsm app -- app one two"
check "the app gets its arguments" contains "$out" "app one two"
check "the wait comes before the grant, and the grant before the app" \
    test "$(sed -n 's/ .*//p' "$log" | tr '\n' ' ')" = "systemctl hyprctl uwsm app "
check "a clean launch says nothing" test ! -s "$tmp/err"

run "$qs" launch --app org.gnome.Nautilus -- "$fake/app" .
check "--app names the grant" \
    contains "$(cat "$log")" 'quickspace_focus.grant("org.gnome.Nautilus")'
run "$qs" launch --app=kitty app
check "--app=ID works too" contains "$(cat "$log")" 'quickspace_focus.grant("kitty")'
run "$qs" launch --app 'a"b\c' app
check "the grant escapes the ID for Lua" \
    contains "$(cat "$log")" 'quickspace_focus.grant("a\"b\\c")'

run XDG_CURRENT_DESKTOP=KDE "$qs" launch app x
out=$(cat "$log")
check "outside quickspace it just runs the command" test "$out" = "app x"

# A stuck shell: the wait gives up at the bound and the app starts anyway.
run QUICKSPACE_LAUNCH_WAIT=1 FAKE_SYSTEMCTL_SLEEP=5 "$qs" launch app
check "a stuck shell still launches the app" contains "$(cat "$log")" "app "
check "a stuck shell is reported" contains "$(cat "$tmp/err")" "the shell isn't ready"
run FAKE_SYSTEMCTL_STATUS=1 "$qs" launch app
check "a failed shell still launches the app" contains "$(cat "$log")" "uwsm app -- app"
check "a failed shell is reported with systemctl's error" \
    contains "$(cat "$tmp/err")" "Job failed"

run FAKE_HYPRCTL_REPLY='error: attempt to index a nil value' "$qs" launch app
check "a rejected grant still launches the app" contains "$(cat "$log")" "uwsm app -- app"
check "a rejected grant is reported" \
    contains "$(cat "$tmp/err")" "couldn't record a focus grant for app: error: attempt"

run "$qs" launch
check "launch with no command is a usage error" test $? -eq 2
run "$qs" launch --bogus app
check "an unknown option is a usage error" test $? -eq 2
run "$qs" frobnicate
check "an unknown subcommand is a usage error" test $? -eq 2

if command -v shellcheck >/dev/null 2>&1; then
    check "shellcheck passes" shellcheck -s sh "$qs" bin/quickspace_test.sh
fi

printf 'quickspace_test.sh: %d passed, %d failed\n' "$passes" "$failures"
test "$failures" -eq 0
