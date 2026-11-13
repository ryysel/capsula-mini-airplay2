#!/bin/sh
# AirPlay 2 receiver for VK Капсула 2019 (RK3308, Buildroot, glibc, PulseAudio).
#
# Installs into /data/local (persistent, not the read-only squashfs):
#   /data/local/capsula-airplay/bin/{shairport-sync,nqptp}
#   /data/local/capsula-airplay/etc/shairport-sync.conf
#   /data/local/capsula-airplay/init.d/{nqptp,shairport-sync}
#   /data/local/bin/capsula-boot
#   /data/local/capsula-boot.d/30-airplay.sh
# adds a late-boot hook to the overlay copy of /usr/bin/voice-agent.sh and
# patches voice-agent so that the AirPlay volume is applied natively (see
# voice-agent-volume-patch.sh).
#
# The firmware has no awk/sed/install: only busybox sh, cp, mv, chmod, grep.
#
# Usage: sh install.sh ["AirPlay name"]
set -eu

name=
timing_mode=fast_audio
while [ "$#" -gt 0 ]; do
    case "$1" in
        --timing) shift; [ "$#" -gt 0 ] || exit 2; timing_mode=$1 ;;
        --*) echo 'Usage: install.sh [name] [--timing fast_audio|synchronized]' >&2; exit 2 ;;
        *) [ -z "$name" ] || exit 2; name=$1 ;;
    esac
    shift
done
case "$timing_mode" in fast_audio|synchronized) ;; *) echo 'Invalid timing mode' >&2; exit 2;; esac
root=$(cd "$(dirname "$0")" && pwd)
cd "$root"

# Validate explicit names before stopping services or changing any files.
if [ -n "$name" ]; then
    case "$name" in --*|*'"'*|*'\'* ) echo 'Invalid AirPlay name' >&2; exit 1;; esac
    [ "$(printf '%s' "$name" | wc -c)" -le 50 ] || { echo 'Name exceeds 50 UTF-8 bytes' >&2; exit 1; }
    [ "$(printf '%s' "$name" | wc -l)" -eq 0 ] || { echo 'Name must be a single line' >&2; exit 1; }
fi

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

# Back up only package-managed payloads, never account data or firmware.
BACKUP=$DEST/backups/$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$BACKUP"
for part in bin etc init.d; do
    [ ! -d "$DEST/$part" ] || cp -a "$DEST/$part" "$BACKUP/$part"
done
# Stop the trial/previous package, not voice-agent or the watchdog.
for p in /var/run/capsula-ui.pid /var/run/capsula-led-media.pid; do
    if [ -f "$p" ]; then
        start-stop-daemon -K -p "$p" -s TERM 2>/dev/null || true
        rm -f "$p"
    fi
done
[ ! -x "$DEST/init.d/shairport-sync" ] || "$DEST/init.d/shairport-sync" stop
[ ! -x "$DEST/init.d/nqptp" ] || "$DEST/init.d/nqptp" stop
sleep 1
mkdir -p "$DEST/bin" "$DEST/etc" "$DEST/init.d" "$BASE/bin" "$BASE/capsula-boot.d"

cp -f bin/capsula-ui "$DEST/bin/capsula-ui"
cp -f bin/capsula-led-media "$DEST/bin/capsula-led-media"
cp -f etc/capsula-ui.init "$DEST/init.d/capsula-ui"
chmod 0755 "$DEST/bin/capsula-ui" "$DEST/bin/capsula-led-media" "$DEST/init.d/capsula-ui"
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

# Keep custom settings and edit just the explicitly requested name.
if [ -n "$name" ]; then
    [ "$(printf '%s' "$name" | wc -c)" -le 50 ] || { echo 'Name exceeds 50 UTF-8 bytes' >&2; exit 1; }
    case "$name" in *'"'*|*'\'* ) echo 'Invalid name' >&2; exit 1;; esac
    : > "$DEST/etc/shairport-sync.conf.new"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in *'name = '*) printf '\tname = "%s";\n' "$name" ;; *) printf '%s\n' "$line" ;; esac
    done < "$DEST/etc/shairport-sync.conf" > "$DEST/etc/shairport-sync.conf.new"
    mv "$DEST/etc/shairport-sync.conf.new" "$DEST/etc/shairport-sync.conf"
fi
if ! grep -q 'metadata.*=' "$DEST/etc/shairport-sync.conf"; then
    cat >> "$DEST/etc/shairport-sync.conf" <<'META'

metadata = {
    enabled = "yes";
    include_cover_art = "yes";
    pipe_name = "/tmp/capsula-airplay-metadata";
    cover_art_cache_directory = "/tmp/capsula-airplay-covers";
};
META
fi

# Same explicit fast-audio values as the current Alice profile. A caller can
# request synchronized mode without losing name/volume/metadata settings.
cp -f etc/apply-timing-profile.sh "$DEST/bin/apply-timing-profile"
chmod 0755 "$DEST/bin/apply-timing-profile"
sh "$DEST/bin/apply-timing-profile" "$DEST/etc/shairport-sync.conf" "$timing_mode"

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

echo "== voice-agent volume patch"
# Applied but inert until voice-agent is restarted; the wrapper and the overlay
# binary are picked up on the next boot, so the installation ends with one.
sh ./voice-agent-volume-patch.sh

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
echo "Reboot once: the boot hook and the patched voice-agent are picked up then,"
echo "and from that point the phone slider and the speaker buttons share one volume."
echo INSTALL_PASS
