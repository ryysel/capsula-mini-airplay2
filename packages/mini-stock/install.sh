#!/bin/sh
# Install the AirPlay 2 receiver on VK Capsula Mini with the stock Buildroot OS
# (Amlogic A113X). Everything is installed under /data/local/capsula-airplay;
# the read-only firmware and voice-agent are not replaced.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
cd "$root"

timing_mode=fast_audio
upgrade=no
check=no
name_mode=preserve
name=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --timing) shift; [ "$#" -gt 0 ] || exit 2; timing_mode=$1 ;;
        --upgrade) upgrade=yes ;;
        --check) check=yes ;;
        --name) shift; [ "$#" -gt 0 ] || exit 2; name=$1; name_mode=custom ;;
        --*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) [ "$name_mode" = preserve ] || exit 2; name=$1; name_mode=custom ;;
    esac
    shift
done
die() { echo "$*" >&2; exit 1; }
same_file() {
    [ -f "$2" ] || return 1
    a=$(sha256sum "$1" | cut -d' ' -f1)
    b=$(sha256sum "$2" | cut -d' ' -f1)
    [ "$a" = "$b" ]
}
case "$timing_mode" in fast_audio|synchronized) ;; *) die 'Invalid timing mode';; esac
uid=$(grep '^Uid:' /proc/self/status | cut -f2)
[ "$uid" = 0 ] || die 'Run as root'
[ "$(uname -m)" = aarch64 ] || die 'Only aarch64 is supported'
grep -q '^ID=buildroot' /etc/os-release 2>/dev/null || die 'Stock Buildroot firmware is required'
compat=$(tr '\000' '\n' < /proc/device-tree/compatible 2>/dev/null || true)
printf '%s\n' "$compat" | grep -qi amlogic || die 'Amlogic platform not found'
printf '%s\n' "$compat" | grep -qi axg || die 'A113X/AXG platform not found'
[ -f SHA256SUMS ] || die 'SHA256SUMS is missing'
sha256sum -c SHA256SUMS >/dev/null || die 'Bundle checksum verification failed'
overlay_line=$(grep ' / overlay ' /proc/mounts || true)
[ -n "$overlay_line" ] || die 'Overlay root is not mounted'
printf '%s\n' "$overlay_line" | grep -q 'rw' || die 'Overlay root is not writable'
[ -d /data/overlay/upper ] && [ -w /data/overlay/upper ] || die '/data/overlay/upper is not writable'

if [ -n "$name" ]; then
    len=$(printf '%s' "$name" | wc -c)
    [ "$len" -ge 1 ] && [ "$len" -le 50 ] || die 'Name must be 1..50 UTF-8 bytes'
    [ "$(printf '%s' "$name" | wc -l)" -eq 0 ] || die 'Name must be a single line'
    if printf '%s' "$name" | LC_ALL=C grep -q '[[:cntrl:]"\\]'; then
        die 'Name must not contain control characters, double quotes or backslashes'
    fi
fi

DEST=/data/local/capsula-airplay
CONF=$DEST/etc/shairport-sync.conf
INIT=/etc/init.d/S99airplay
# rcS expands its script list before the overlay is mounted, so
# /etc/init.d/S99airplay (overlay only) is not run at boot. The stock
# avahi script is therefore replaced in the overlay: it runs at S50,
# after S04overlaymount, and starts the AirPlay stack itself.
AVA=/etc/init.d/S50avahi-daemon
AVA_UPPER=/data/overlay/upper/etc/init.d/S50avahi-daemon

# Check every target before changing anything. A different file needs --upgrade.
for pair in \
    "bin/shairport-sync|$DEST/bin/shairport-sync" \
    "bin/nqptp|$DEST/bin/nqptp" \
    "bin/capsula-art|$DEST/bin/capsula-art" \
    "bin/capsula-airplay-keys|$DEST/bin/capsula-airplay-keys" \
    "bin/capsula-airplay-ring|$DEST/bin/capsula-airplay-ring" \
    "bin/libuuid.so.1.3.0|$DEST/bin/libuuid.so.1.3.0" \
    "etc/init.d.nqptp|$DEST/init.d/nqptp" \
    "etc/init.d.shairport-sync|$DEST/init.d/shairport-sync" \
    "etc/S99airplay|$INIT" \
    "etc/S50avahi-daemon|$AVA_UPPER"; do
    src=${pair%%|*}
    dst=${pair#*|}
    [ ! -L "$dst" ] || die "Refusing symlink: $dst"
    if [ -e "$dst" ] && ! same_file "$src" "$dst" && [ "$upgrade" != yes ]; then
        die "Different existing file: $dst. Use --upgrade for a backed-up update."
    fi
done
[ ! -L "$CONF" ] || die "Refusing symlink: $CONF"

free=$(df -Pk /data | tail -1 | tr -s ' ' | cut -d' ' -f4)
[ "$free" -ge 25000 ] || die 'Need at least 25 MiB free on /data'

if [ "$check" = yes ]; then
    echo 'PREFLIGHT_PASS stock-mini'
    exit 0
fi

backup=none
if [ -d "$DEST" ]; then
    backup=$DEST.backup-$(date +%Y%m%d-%H%M%S)
    cp -a "$DEST" "$backup"
    echo "Backup: $backup"
fi

# Stop only our services; voice-agent and the watchdog stay untouched.
for svc in capsula-airplay-ring capsula-airplay-keys; do
    pidfile=/var/run/$svc.pid
    if [ -f "$pidfile" ]; then
        kill "$(cat "$pidfile")" 2>/dev/null || true
        rm -f "$pidfile"
    fi
done
kill "$(pidof capsula-airplay)" 2>/dev/null || true
kill "$(pidof shairport-sync)" 2>/dev/null || true
kill "$(pidof nqptp)" 2>/dev/null || true
i=0
while [ "$i" -lt 10 ] && { pidof shairport-sync >/dev/null || pidof nqptp >/dev/null; }; do
    sleep 1
    i=$((i + 1))
done
[ "$i" -lt 10 ] || die 'Could not stop the previous receiver; reboot and retry'
rm -f /dev/shm/nqptp-*

mkdir -p "$DEST/bin" "$DEST/etc" "$DEST/init.d"
for f in shairport-sync nqptp capsula-art capsula-airplay-keys capsula-airplay-ring; do
    cp "bin/$f" "$DEST/bin/$f"
    chmod 0755 "$DEST/bin/$f"
done
cp bin/libuuid.so.1.3.0 "$DEST/bin/libuuid.so.1.3.0"
chmod 0644 "$DEST/bin/libuuid.so.1.3.0"
ln -sf libuuid.so.1.3.0 "$DEST/bin/libuuid.so.1"
cp etc/init.d.nqptp "$DEST/init.d/nqptp"
cp etc/init.d.shairport-sync "$DEST/init.d/shairport-sync"
cp etc/S99airplay "$DEST/S99airplay"
chmod 0755 "$DEST/init.d/nqptp" "$DEST/init.d/shairport-sync" "$DEST/S99airplay"
if [ ! -e "$CONF" ]; then
    cp etc/shairport-sync.conf "$CONF"
fi
chmod 0644 "$CONF"

if [ "$name_mode" = custom ]; then
    : > "$CONF.new"
    while IFS= read -r line || [ -n "$line" ]; do
        if printf '%s' "$line" | grep -q '^[[:space:]]*name[[:space:]]*='; then
            printf '\tname = "%s";\n' "$name"
        else
            printf '%s\n' "$line"
        fi
    done < "$CONF" > "$CONF.new"
    mv "$CONF.new" "$CONF"
fi

case "$timing_mode" in
    synchronized) buffer=0.20; offset=0.0 ;;
    *) buffer=0.10; offset=-1.7 ;;
esac
: > "$CONF.new"
while IFS= read -r line || [ -n "$line" ]; do
    if printf '%s' "$line" | grep -q '^[[:space:]]*audio_backend_buffer_desired_length_in_seconds'; then
        printf '\taudio_backend_buffer_desired_length_in_seconds = %s;\n' "$buffer"
    elif printf '%s' "$line" | grep -q '^[[:space:]]*audio_backend_latency_offset_in_seconds'; then
        printf '\taudio_backend_latency_offset_in_seconds = %s;\n' "$offset"
    else
        printf '%s\n' "$line"
    fi
done < "$CONF" > "$CONF.new"
chmod 0644 "$CONF.new"
mv "$CONF.new" "$CONF"

cp etc/S99airplay "$INIT.new"
chmod 0755 "$INIT.new"
mv "$INIT.new" "$INIT"
cp etc/S50avahi-daemon "$AVA.new"
chmod 0755 "$AVA.new"
mv "$AVA.new" "$AVA"

"$INIT" start
i=0
while [ "$i" -lt 15 ] && ! pidof shairport-sync >/dev/null; do
    sleep 1
    i=$((i + 1))
done
pidof shairport-sync >/dev/null || die "shairport-sync failed to start. Backup: $backup"
i=0
while [ "$i" -lt 15 ] && ! pidof nqptp >/dev/null; do
    sleep 1
    i=$((i + 1))
done
pidof nqptp >/dev/null || die "nqptp failed to start. Backup: $backup"
avahi-daemon -c >/dev/null 2>&1 || die "avahi-daemon is not running. Backup: $backup"
echo "INSTALL_PASS stock-mini backup=$backup"
