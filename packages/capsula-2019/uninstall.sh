#!/bin/sh
# Remove the AirPlay 2 receiver for VK Капсула 2019 and the voice-agent volume
# patch.
# No awk/sed on this firmware: the wrapper is filtered line by line in sh.
set -eu

BASE=/data/local
DEST=$BASE/capsula-airplay
WRAP=/data/overlay/upper/usr/bin/voice-agent.sh
VA=/data/overlay/upper/usr/bin/voice-agent
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

uid=$(grep '^Uid:' /proc/self/status | cut -f2)
test "$uid" = 0 || { echo "Run as root on the capsule." >&2; exit 1; }

"$BASE/capsula-boot.d/30-airplay.sh" stop 2>/dev/null || true
killall -15 shairport-sync 2>/dev/null || true
killall -15 nqptp 2>/dev/null || true

rm -f "$BASE/capsula-boot.d/30-airplay.sh"
rm -rf "$DEST"

# The wrapper only exists in the overlay when the package added its boot hook
# and the stock fallback. Removing the overlay copy reveals the stock script.
if [ -f "$WRAP" ] && grep -q -e 'capsula-boot' -e 'capsula:fallback' "$WRAP"; then
    rm -f "$WRAP"
    echo "voice-agent wrapper: package hook removed"
fi

# The patched voice-agent only exists in the overlay; removing that copy
# restores the stock binary from the read-only firmware on the next boot.
if [ -f "$VA" ]; then
    if sh "$root/voice-agent-pack.sh" check; then
        rm -f "$VA"
        echo "voice-agent: volume patch removed"
    else
        echo "Keeping unrecognised overlay voice-agent; it is not this package's patch."
    fi
fi

sync

echo "Removed. Reboot to restore the stock voice-agent and wrapper."
echo UNINSTALL_PASS
