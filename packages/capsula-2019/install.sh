#!/bin/sh
# AirPlay 2 receiver for VK Капсула 2019 (RK3308, Buildroot, glibc, PulseAudio).
#
# Installs into /data/local (persistent, not the read-only squashfs):
#   /data/local/capsula-airplay/bin/{shairport-sync,nqptp}
#   /data/local/capsula-airplay/etc/shairport-sync.conf
#   /data/local/capsula-airplay/init.d/{nqptp,shairport-sync}
#   /data/local/bin/capsula-boot
#   /data/local/capsula-boot.d/30-airplay.sh
# and adds a late-boot hook to the overlay copy of /usr/bin/voice-agent.sh.
#
# The firmware has no awk/sed/install: only busybox sh, cp, mv, chmod, grep.
#
# Usage: sh install.sh ["AirPlay name"]
set -eu

name=${1:-}
root=$(cd "$(dirname "$0")" && pwd)
cd "$root"

BASE=/data/local
DEST=$BASE/capsula-airplay
WRAP=/data/overlay/upper/usr/bin/voice-agent.sh

uid=$(grep '^Uid:' /proc/self/status | cut -f2)
test "$uid" = 0 || { echo "Run as root on the capsule." >&2; exit 1; }
test "$(uname -m)" = aarch64 || { echo "Only aarch64 is supported." >&2; exit 1; }
grep -q '^ID=buildroot' /etc/os-release 2>/dev/null || {
    echo "This is not the VK Капсула 2019 Buildroot firmware." >&2; exit 1; }

compat=$(cat /proc/device-tree/compatible 2>/dev/null || true)
case "$compat" in
    *rk3308*) ;;
    *) echo "RK3308 not found; this package is for the 2019 Capsule." >&2; exit 1 ;;
esac

test -f SHA256SUMS || { echo "SHA256SUMS is missing." >&2; exit 1; }
sha256sum -c SHA256SUMS > /dev/null

mkdir -p "$DEST/bin" "$DEST/etc" "$DEST/init.d" "$BASE/bin" "$BASE/capsula-boot.d"

cp -f bin/shairport-sync "$DEST/bin/shairport-sync"
cp -f bin/nqptp "$DEST/bin/nqptp"
cp -f etc/nqptp.init "$DEST/init.d/nqptp"
cp -f etc/shairport-sync.init "$DEST/init.d/shairport-sync"
cp -f etc/capsula-boot "$BASE/bin/capsula-boot"
cp -f etc/30-airplay.sh "$BASE/capsula-boot.d/30-airplay.sh"
chmod 0755 "$DEST/bin/shairport-sync" "$DEST/bin/nqptp" \
    "$DEST/init.d/nqptp" "$DEST/init.d/shairport-sync" \
    "$BASE/bin/capsula-boot" "$BASE/capsula-boot.d/30-airplay.sh"

if [ ! -e "$DEST/etc/shairport-sync.conf" ]; then
    cp -f etc/shairport-sync.conf "$DEST/etc/shairport-sync.conf"
    chmod 0644 "$DEST/etc/shairport-sync.conf"
else
    echo "Keeping existing $DEST/etc/shairport-sync.conf"
fi

if [ -n "$name" ]; then
    # No sed on this firmware: rewrite the whole (short) config from scratch.
    {
        printf '%s\n' \
            '// AirPlay 2 receiver for VK Капсула 2019 (RK3308, Buildroot, glibc).' \
            '// Audio goes to PulseAudio, the same sound server voice-agent uses.' \
            '' \
            'general = {' \
            "	name = \"$name\";" \
            '	output_backend = "pulseaudio";' \
            '	port = 7000;' \
            '	interpolation = "basic";' \
            '	volume_range_db = 60.0;' \
            '	audio_backend_buffer_desired_length_in_seconds = 0.2;' \
            '};' \
            '' \
            'pulseaudio = {' \
            '	// Empty: use the default PulseAudio sink.' \
            '};'
    } > "$DEST/etc/shairport-sync.conf"
    chmod 0644 "$DEST/etc/shairport-sync.conf"
fi

# The stock rcS expands /etc/init.d/S??* before the overlay is mounted, so a
# new S* script never runs. Hook into the voice-agent wrapper, which starts
# after the overlay is up. Write it into the overlay upper directly: a write
# through the merged path may not survive a reboot.
if [ ! -f "$WRAP" ]; then
    mkdir -p "$(dirname "$WRAP")"
    cp /usr/bin/voice-agent.sh "$WRAP"
fi
if ! grep -q 'capsula-boot' "$WRAP"; then
    hook='( sleep 10; [ -x /data/local/bin/capsula-boot ] && /data/local/bin/capsula-boot ) >/dev/null 2>&1 &'
    : > "$WRAP.new"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "exec voice-agent"*) printf '%s\n\n' "$hook" >> "$WRAP.new" ;;
        esac
        printf '%s\n' "$line" >> "$WRAP.new"
    done < "$WRAP"
    mv -f "$WRAP.new" "$WRAP"
    chmod 0755 "$WRAP"
fi
sync

echo "== starting services"
"$BASE/capsula-boot.d/30-airplay.sh" start
sleep 3

echo "== status"
pidof nqptp > /dev/null 2>&1 && echo "nqptp: running" || echo "nqptp: NOT running"
pidof shairport-sync > /dev/null 2>&1 && echo "shairport-sync: running" || echo "shairport-sync: NOT running"
netstat -ln 2>/dev/null | grep -E ':(7000|319|320) ' || true

echo
echo "AirPlay name: $(grep -m1 'name = ' "$DEST/etc/shairport-sync.conf" | cut -d'"' -f2)"
echo "Reboot once so the boot hook is picked up by the voice-agent wrapper."
echo INSTALL_PASS
