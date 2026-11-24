#!/bin/sh
# SPDX-License-Identifier: MIT
# Stock Mini only. Stage startup integration; never stop/re-exec voice-agent.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
D=/data/local/capsula-airplay
ROM=/rom/usr/bin/voice-agent
ROM_WRAP=/rom/usr/bin/voice-agent.sh
WRAP=/data/overlay/upper/usr/bin/voice-agent.sh
OLD=82a498025166d199343398ac7f9fdcb659c472f9b0de0ab784c30d9fc11713cb
NEW=99483ff16996719e7ed2201dcf1b4a63ab15b472f15068d1c6aa77272fa3041f
sum() { sha256sum "$1" | cut -d' ' -f1; }
die() { echo "$*" >&2; exit 1; }
action=${1:-check}
case "$action" in check|install|disable) ;; *) die 'Usage: display-arbiter-install.sh check|install|disable';; esac
for file in "$D/etc/mini-display-arbiter.enabled" "$D/etc/mini-display-arbiter.pending"; do
    [ ! -L "$file" ] || die "Refusing symlink: $file"
done
if [ "$action" = disable ]; then
    rm -f "$D/etc/mini-display-arbiter.enabled"
    echo 'Display arbiter disabled for next boot; current instance becomes native-only when the UI releases.'
    exit 0
fi
[ "$(sum "$ROM")" = e91c758edaae7ef258691438439906b4bd5986609a3be9fde946e59fc15ed9b7 ] ||
    die 'Unsupported stock Mini voice-agent; display hook not changed'
[ ! -L "$WRAP" ] || die "Refusing symlink: $WRAP"
current=$ROM_WRAP
[ ! -f "$WRAP" ] || current=$WRAP
got=$(sum "$current")
case "$got" in
    "$OLD"|"$NEW") ;;
    *) [ "$got" = "$(sum "$ROM_WRAP")" ] || die 'Unknown voice-agent wrapper; refusing display-hook replacement' ;;
esac
[ ! -e "$D/etc/mini-display-arbiter.pending" ] ||
    die 'Previous arbiter startup did not clear its guard. Disable VU and inspect it before retrying.'
if [ "$action" = check ]; then
    echo DISPLAY_ARBITER_PREFLIGHT_PASS
    exit 0
fi
[ -f "$D/bin/libcapsula-display-arbiter.so" ] || die 'Display adapter library not installed'
if [ "$got" != "$NEW" ]; then
    [ "$got" = "$OLD" ] || die 'Install the stock fallback wrapper before the display hook'
    [ ! -e "$WRAP.display-new" ] || die 'Existing display wrapper staging file; inspect before retrying'
    [ -f "$WRAP.before-display-arbiter" ] || cp -p "$WRAP" "$WRAP.before-display-arbiter"
    found=0
    : >"$WRAP.display-new"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            'voice-agent "$@" &')
                cat "$root/etc/display-arbiter-launch.sh" >>"$WRAP.display-new"
                found=$((found+1))
                ;;
            *) printf '%s\n' "$line" >>"$WRAP.display-new" ;;
        esac
    done <"$WRAP"
    [ "$found" = 1 ] && [ "$(sum "$WRAP.display-new")" = "$NEW" ] ||
        die 'Display wrapper did not match the tested launch script'
    sh -n "$WRAP.display-new"
    chmod 755 "$WRAP.display-new"
    mv "$WRAP.display-new" "$WRAP"
fi
mkdir -p "$D/etc"
touch "$D/etc/mini-display-arbiter.enabled"
echo 'DISPLAY_ARBITER_STAGED: manually reboot Mini to load native arbitration; never stop voice-agent.'
