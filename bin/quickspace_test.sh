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
check "the grant comes before the wait, and the wait before the app" \
    test "$(sed -n 's/ .*//p' "$log" | tr '\n' ' ')" = "hyprctl systemctl uwsm app "
check "a clean launch says nothing" test ! -s "$tmp/err"

run "$qs" launch --app org.gnome.Nautilus -- "$fake/app" .
check "--app names the grant" \
    contains "$(cat "$log")" 'quickspace_focus.grant("org.gnome.Nautilus")'
run "$qs" launch --app=kitty app
check "--app=ID works too" contains "$(cat "$log")" 'quickspace_focus.grant("kitty")'
run "$qs" launch --app '*' -- "$fake/app"
check "--app '*' grants the next window of any app" \
    contains "$(cat "$log")" 'quickspace_focus.grant("*")'
for opener in xdg-open "gio open"; do
    printf '#!/bin/sh\n' > "$fake/${opener%% *}"
    chmod +x "$fake/${opener%% *}"
    # shellcheck disable=SC2086  # "gio open" is two words
    run "$qs" launch "$fake"/$opener https://example.com/
    check "$opener grants the first window of any app" \
        contains "$(cat "$log")" 'quickspace_focus.grant("*")'
done
run "$qs" launch "$fake/gio" trash file.txt
check "gio trash opens no app, so it grants no wildcard" \
    contains "$(cat "$log")" 'quickspace_focus.grant("gio")'
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
for bad in 0 abc -1 3601 999999999999999999999; do
    run QUICKSPACE_LAUNCH_WAIT="$bad" "$qs" launch app
    check "QUICKSPACE_LAUNCH_WAIT=$bad is reported by name" \
        contains "$(cat "$tmp/err")" "QUICKSPACE_LAUNCH_WAIT must be a whole number of seconds from 1 to 3600, not '$bad'"
    check "QUICKSPACE_LAUNCH_WAIT=$bad still launches the app" contains "$(cat "$log")" "uwsm app -- app"
done
run FAKE_SYSTEMCTL_STATUS=1 "$qs" launch app
check "a failed shell still launches the app" contains "$(cat "$log")" "uwsm app -- app"
check "a failed shell is reported with systemctl's error" \
    contains "$(cat "$tmp/err")" "Job failed"

run FAKE_HYPRCTL_REPLY='error: attempt to index a nil value' "$qs" launch app
check "a rejected grant still launches the app" contains "$(cat "$log")" "uwsm app -- app"
check "a rejected grant is reported" \
    contains "$(cat "$tmp/err")" "couldn't record a focus grant for app: error: attempt"

run "$qs" grant google-chrome
check "grant exits 0 once recorded" test $? -eq 0
check "grant records only the grant" test "$(cat "$log")" = 'hyprctl eval quickspace_focus.grant("google-chrome")'
run "$qs" grant 'a"b'
check "grant escapes the ID for Lua" contains "$(cat "$log")" 'quickspace_focus.grant("a\"b")'
run FAKE_HYPRCTL_REPLY='error: no quickspace_focus' "$qs" grant app
check "a rejected grant exits 1" test $? -eq 1
check "a rejected grant says why" \
    contains "$(cat "$tmp/err")" "quickspace grant: couldn't record a focus grant for app: error: no quickspace_focus"
run XDG_CURRENT_DESKTOP=KDE "$qs" grant app
check "outside quickspace grant does nothing" test $? -eq 0 -a ! -s "$log"
run "$qs" grant
check "grant with no ID is a usage error" test $? -eq 2
run "$qs" grant ''
check "grant with an empty ID is a usage error" test $? -eq 2
run "$qs" grant a b
check "grant takes one ID" test $? -eq 2

run "$qs" launch
check "launch with no command is a usage error" test $? -eq 2
run "$qs" launch --bogus app
check "an unknown option is a usage error" test $? -eq 2
run "$qs" frobnicate
check "an unknown subcommand is a usage error" test $? -eq 2

# autostart-allowed: the allowlist the autostart drop-in consults.
allowed() {
    env XDG_CONFIG_HOME="$tmp/config" sh "$qs" autostart-allowed "$1" 2>"$tmp/err"
}
check "nm-applet's autostart is allowed" allowed 'app-nm\x2dapplet@autostart.service'
check "blueman's autostart is allowed" allowed 'app-blueman@autostart.service'
check "another desktop's autostart is skipped" test "$(allowed 'app-hplip\x2dsystray@autostart.service'; echo $?)" -eq 1
check "a skip says how to allow it" \
    contains "$(cat "$tmp/err")" "not starting hplip-systray in quickspace; add hplip-systray to $tmp/config/quickspace/autostart"
mkdir -p "$tmp/config/quickspace"
printf '# extra applets\nhplip-systray\n\n  xiccd  \nhas space\nhash#tag\n# commented-out\n\\x23lead\n' > "$tmp/config/quickspace/autostart"
check "the user's list allows more" allowed 'app-hplip\x2dsystray@autostart.service'
check "surrounding spaces in the user's list are ignored" allowed 'app-xiccd@autostart.service'
check "an ID with a space is matched whole" allowed 'app-has\x20space@autostart.service'
check "an ID with a # is matched whole" allowed 'app-hash\x23tag@autostart.service'
check "half of an ID with a space isn't allowed" test "$(allowed 'app-has@autostart.service'; echo $?)" -eq 1
check "an ID starting with # is allowed by its escaped form" allowed 'app-\x23lead@autostart.service'
check "a commented-out line allows nothing" test "$(allowed 'app-commented\x2dout@autostart.service'; echo $?)" -eq 1
check "the defaults still apply beside the user's list" allowed 'app-nm\x2dapplet@autostart.service'
check "an entry the user's list lacks is still skipped" \
    test "$(allowed 'app-xfce4\x2dnotifyd@autostart.service'; echo $?)" -eq 1
rm -rf "$tmp/config"
mkdir -p "$tmp/config/quickspace/autostart"
check "an unreadable allowlist stops the check rather than denying" \
    test "$(allowed 'app-nm\x2dapplet@autostart.service'; echo $?)" -eq 3
check "an unreadable allowlist is named" contains "$(cat "$tmp/err")" "couldn't read $tmp/config/quickspace/autostart"
rm -rf "$tmp/config"
mkdir -p "$tmp/config/quickspace"
ln -s "$tmp/nowhere" "$tmp/config/quickspace/autostart"
check "a dangling allowlist symlink stops the check too" \
    test "$(allowed 'app-hplip\x2dsystray@autostart.service'; echo $?)" -eq 3
rm -rf "$tmp/config"
check "other escaped characters are undone too" \
    test "$(XDG_CONFIG_HOME="$tmp/config" sh "$qs" autostart-allowed 'app-org.example.a\x2bb@autostart.service' 2>&1)" = \
        "quickspace: not starting org.example.a+b in quickspace; add org.example.a+b to $tmp/config/quickspace/autostart to allow it"
check "a unit that isn't an autostart one is a usage error" test "$(allowed 'app-foo.service'; echo $?)" -eq 2

# The drop-in on every app-*.service: only autostart units in quickspace ask
# the allowlist; everything else passes without asking.
dropin=$(sed -n "s/^ExecCondition=\/bin\/sh -c '\(.*\)'\$/\1/p" systemd/user/app-.service.d/quickspace-autostart.conf)
check "the drop-in has one ExecCondition" test -n "$dropin"
cat > "$fake/quickspace" <<'FAKE'
#!/bin/sh
printf "quickspace %s\n" "$*" >> "$FAKE_LOG"
exit "${FAKE_ALLOWED_STATUS:-0}"
FAKE
chmod +x "$fake/quickspace"
condition() {
    unit=$1
    shift
    : > "$log"
    # As systemd does: $$ becomes $, and %n the unit's name.
    cmd=$(printf '%s\n' "$dropin" | sed -e 's/\$\$/$/g' -e "s/%n/$(printf '%s' "$unit" | sed 's/\\/\\\\/g')/g")
    env PATH="$fake:$PATH" FAKE_LOG="$log" "$@" sh -c "$cmd"
}
condition 'app-hplip\x2dsystray@autostart.service' XDG_CURRENT_DESKTOP=quickspace:Hyprland FAKE_ALLOWED_STATUS=1
check "in quickspace, an autostart unit gets the allowlist's answer" test $? -eq 1
check "the allowlist is asked about that unit" \
    contains "$(cat "$log")" 'quickspace autostart-allowed app-hplip\x2dsystray@autostart.service'
condition 'app-hplip\x2dsystray@autostart.service' XDG_CURRENT_DESKTOP=KDE FAKE_ALLOWED_STATUS=1
check "under Plasma, an autostart unit runs" test $? -eq 0
check "under Plasma, the allowlist isn't asked" test ! -s "$log"
condition 'app-nm\x2dapplet@autostart.service' XDG_CURRENT_DESKTOP=quickspace:Hyprland FAKE_ALLOWED_STATUS=0
check "in quickspace, an allowed autostart unit runs" test $? -eq 0
condition 'app-nm\x2dapplet@autostart.service' XDG_CURRENT_DESKTOP=quickspace:Hyprland FAKE_ALLOWED_STATUS=127 2>"$tmp/err"
check "a helper that can't run fails the unit, rather than skipping it" test $? -eq 255
check "a failing helper is named in the unit's log" \
    contains "$(cat "$tmp/err")" 'quickspace autostart-allowed failed (127) for app-nm\x2dapplet@autostart.service'
condition 'app-nm\x2dapplet@autostart.service' XDG_CURRENT_DESKTOP=quickspace:Hyprland FAKE_ALLOWED_STATUS=2 2>/dev/null
check "a helper usage error fails the unit too" test $? -eq 255
condition 'app-org.kde.dolphin@1234.service' XDG_CURRENT_DESKTOP=quickspace:Hyprland FAKE_ALLOWED_STATUS=1
check "in quickspace, an app that isn't autostarted runs" test $? -eq 0
check "in quickspace, an app that isn't autostarted isn't asked about" test ! -s "$log"

if command -v shellcheck >/dev/null 2>&1; then
    check "shellcheck passes" shellcheck -s sh "$qs" bin/quickspace_test.sh
fi

printf 'quickspace_test.sh: %d passed, %d failed\n' "$passes" "$failures"
test "$failures" -eq 0
