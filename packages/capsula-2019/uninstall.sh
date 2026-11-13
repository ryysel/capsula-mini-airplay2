#!/bin/sh
# Remove the AirPlay 2 receiver for VK Капсула 2019.
# No awk/sed on this firmware: the wrapper is filtered line by line in sh.
set -eu

BASE=/data/local
DEST=$BASE/capsula-airplay
WRAP=/data/overlay/upper/usr/bin/voice-agent.sh

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
sync

echo "Removed. Reboot to fully restore the stock voice-agent wrapper."
echo UNINSTALL_PASS
