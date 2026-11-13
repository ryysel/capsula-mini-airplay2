#!/bin/sh
# Remove the AirPlay 2 receiver for VK Капсула 2019 and the voice-agent volume
# patch.
# No awk/sed on this firmware: the wrapper is filtered line by line in sh.
set -eu

BASE=/data/local
DEST=$BASE/capsula-airplay
WRAP=/data/overlay/upper/usr/bin/voice-agent.sh
VA=/data/overlay/upper/usr/bin/voice-agent

uid=$(grep '^Uid:' /proc/self/status | cut -f2)
test "$uid" = 0 || { echo "Run as root on the capsule." >&2; exit 1; }

"$BASE/capsula-boot.d/30-airplay.sh" stop 2>/dev/null || true
killall -15 shairport-sync 2>/dev/null || true
killall -15 nqptp 2>/dev/null || true

rm -f "$BASE/capsula-boot.d/30-airplay.sh"
rm -rf "$DEST"

if [ -f "$WRAP" ] && grep -q 'capsula-boot' "$WRAP"; then
    : > "$WRAP.new"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *capsula-boot*) continue ;;
        esac
        printf '%s\n' "$line" >> "$WRAP.new"
    done < "$WRAP"
    mv -f "$WRAP.new" "$WRAP"
    chmod 0755 "$WRAP"
fi

# The patched voice-agent only exists in the overlay; removing it restores the
# stock binary from the read-only squashfs on the next boot.
if [ -f "$VA" ]; then
    hash=$(sha256sum "$VA" | cut -d' ' -f1)
    if [ "$hash" = e58d5e46c2b26e7c20ab740c11b03993472aa032d142cc25c127204728dcb9b5 ]; then
        rm -f "$VA"
        echo "voice-agent: volume patch removed"
    else
        echo "Keeping unrecognised overlay voice-agent; it is not this package's patch."
    fi
fi

sync

echo "Removed. Reboot to restore the stock voice-agent and wrapper."
echo UNINSTALL_PASS
