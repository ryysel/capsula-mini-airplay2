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
timing_mode=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --upgrade) : ;;
        --timing) shift; [ "$#" -gt 0 ] || exit 2; timing_mode=$1 ;;
        --*) echo 'Usage: install.sh [name] [--timing fast_audio|synchronized]' >&2; exit 2 ;;
        *) [ -z "$name" ] || exit 2; name=$1 ;;
    esac
    shift
done
case "$timing_mode" in ''|fast_audio|synchronized) ;; *) echo 'Invalid timing mode' >&2; exit 2;; esac
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

lock=/tmp/capsula-airplay-install.lock
mkdir "$lock" || { echo 'Another installation or stale install lock' >&2; exit 1; }
trap 'rmdir "$lock"' EXIT
if [ -x "$DEST/bin/capsula-ui" ] && [ "$("$DEST/bin/capsula-ui" --control state 2>/dev/null || true)" = active ]; then
    echo 'AirPlay active; disconnect before upgrading' >&2
    exit 1
fi
(
conf=$DEST/etc/shairport-sync.conf
prepared=$(mktemp /tmp/capsula-conf.XXXXXX)
trap 'rm -f "$prepared" "$prepared.new"' EXIT
if [ -f "$conf" ]; then cp "$conf" "$prepared"; else cp etc/shairport-sync.conf "$prepared"; fi
if [ -n "$name" ]; then
    inside=no
    count=0
    while IFS= read -r line || [ -n "$line" ]; do
        trimmed=${line#"${line%%[! 	]*}"}
        case "$trimmed" in
            'general = {'|'general={'|'general ={'|'general= {') inside=yes ;;
            '};'*) inside=no ;;
        esac
        if [ "$inside" = yes ] && printf '%s\n' "$trimmed" | grep -q '^name[[:space:]]*='; then
            count=$((count + 1))
            printf '\tname = "%s";\n' "$name"
        else
            printf '%s\n' "$line"
        fi
    done < "$prepared" > "$prepared.new"
    [ "$count" = 1 ] || { echo 'Expected one general.name' >&2; exit 1; }
    mv "$prepared.new" "$prepared"
fi
if ! grep -q 'metadata.*=' "$prepared"; then
    cat >> "$prepared" <<'META'

metadata = {
    enabled = "yes";
    include_cover_art = "yes";
    pipe_name = "/tmp/capsula-airplay-metadata";
    cover_art_cache_directory = "/tmp/capsula-airplay-covers";
};
META
fi

if [ -z "$timing_mode" ]; then
    timing_mode=fast_audio
    if grep -Eq '^[[:space:]]*audio_backend_latency_offset_in_seconds[[:space:]]*=[[:space:]]*[-+]?0([.]0*)?[[:space:]]*;' "$prepared"; then
        timing_mode=synchronized
    fi
fi
sh etc/apply-timing-profile.sh "$prepared" "$timing_mode"

# Snapshot managed paths before changing services. Files outside this list
# (including panel.json and experimental images) are never rollback targets.
BACKUP=$BASE/capsula-airplay-backups/$(date +%Y%m%d-%H%M%S)-$$
# Fixed package paths contain no spaces.
targets="$DEST/bin/capsula-ui $DEST/bin/capsula-led-media $DEST/bin/shairport-sync
    $DEST/bin/nqptp $DEST/bin/apply-timing-profile $DEST/etc/shairport-sync.conf
    $DEST/init.d/capsula-ui $DEST/init.d/nqptp $DEST/init.d/shairport-sync
    $BASE/bin/capsula-boot $BASE/capsula-boot.d/30-airplay.sh $WRAP /data/overlay/upper/usr/bin/voice-agent"
if [ -f /data/overlay/upper/usr/bin/voice-agent ]; then
    sh ./voice-agent-pack.sh check || { echo 'Unrecognized existing volume patch' >&2; exit 1; }
    # It is already installed and will not be overwritten.
    targets=${targets% /data/overlay/upper/usr/bin/voice-agent}
fi
backup_size=0
for target in $targets; do
    if [ -f "$target" ]; then
        bytes=$(wc -c < "$target")
        backup_size=$((backup_size + (bytes + 1023) / 1024 + 4))
    fi
done
free=$(df -Pk /data | tail -1 | tr -s ' ' | cut -d' ' -f4)
# Space for a new payload and one temporary unpacked voice-agent.
bytes=$(wc -c < /rom/usr/bin/voice-agent)
need=2048
if [ ! -e /data/overlay/upper/usr/bin/voice-agent ]; then
    need=$((need + 2 * ((bytes + 1023) / 1024)))
fi
payload=$(du -sk bin | cut -f1)
[ "$free" -ge $((need + payload + backup_size)) ] || { echo "Insufficient space for snapshot and upgrade" >&2; exit 1; }
mkdir -p "$BASE/capsula-airplay-backups"
mkdir -m 700 "$BACKUP"
for target in $targets; do
    [ ! -L "$target" ] || { echo "Refusing symlink: $target" >&2; exit 1; }
    if [ -f "$target" ]; then
        mkdir -p "$BACKUP$(dirname "$target")"
        cp -p "$target" "$BACKUP$target"
    else
        [ ! -e "$target" ] || exit 1
    fi
    printf '%s\n' "$target" >> "$BACKUP/paths"
done
finish_install() {
    status=$?
    trap - EXIT HUP INT TERM
    rm -f "$prepared" "$prepared.new"
    if [ "$status" -ne 0 ]; then
        echo "Install failed; restoring $BACKUP" >&2
        if [ -x "$BASE/capsula-boot.d/30-airplay.sh" ]; then
            "$BASE/capsula-boot.d/30-airplay.sh" stop || true
        fi
        while IFS= read -r target; do
            if [ -f "$BACKUP$target" ]; then
                cp -p "$BACKUP$target" "$target.restore-$$" && mv -f "$target.restore-$$" "$target" || exit 1
            else
                rm -f "$target"
            fi
        done < "$BACKUP/paths"
        if [ "$was_running" = yes ] && [ -x "$BASE/capsula-boot.d/30-airplay.sh" ]; then
            "$BASE/capsula-boot.d/30-airplay.sh" start
        fi
    fi
    exit "$status"
}
was_running=no
if [ -f /var/run/shairport-sync.pid ]; then
    pid=$(cat /var/run/shairport-sync.pid)
    [ "$(readlink "/proc/$pid/exe")" != "$DEST/bin/shairport-sync" ] || was_running=yes
fi
trap finish_install EXIT
trap 'exit 1' HUP INT TERM
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

cp "$prepared" "$conf.new"
chmod 0644 "$conf.new"
mv "$conf.new" "$conf"
cp etc/apply-timing-profile.sh "$DEST/bin/apply-timing-profile"
chmod 0755 "$DEST/bin/apply-timing-profile"

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
if [ ! -f /data/overlay/upper/usr/bin/voice-agent ]; then
    sh ./voice-agent-volume-patch.sh
fi
sh ./voice-agent-fallback.sh

sync

echo "== starting services"
"$BASE/capsula-boot.d/30-airplay.sh" start
sleep 3

echo "== status"
for service in nqptp shairport-sync capsula-ui capsula-led-media; do
    pid=$(cat "/var/run/$service.pid" 2>/dev/null || true)
    if [ -z "$pid" ] || [ "$(readlink "/proc/$pid/exe")" != "$DEST/bin/$service" ]; then
        echo "$service failed to start; previous payload: $BACKUP" >&2
        exit 1
    fi
done
netstat -ln 2>/dev/null | grep -E ':(7000|319|320) ' || true

echo
echo "AirPlay name: $(grep -m1 'name = ' "$DEST/etc/shairport-sync.conf" | cut -d'"' -f2)"
echo "Reboot once: the boot hook and the patched voice-agent are picked up then,"
echo "and from that point the phone slider and the speaker buttons share one volume."
echo INSTALL_PASS

)
