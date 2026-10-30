#!/bin/sh
# Install the AirPlay 2 receiver (shairport-sync + nqptp) on Alpine 3.24/aarch64.
# Optional control layer: D-Bus transport and two-way volume through the
# capsule-tweaker IPC, installed only when the tweaker socket is present.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
cd "$root"
upgrade=no
check=no
name_mode=preserve
name=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --upgrade) upgrade=yes ;;
        --check) check=yes ;;
        --hostname) name_mode=hostname ;;
        --name) shift; [ "$#" -gt 0 ] || exit 2; name=$1; name_mode=custom ;;
        --name-file) shift; [ "$#" -gt 0 ] || exit 2; name_file=$1; name_mode=file ;;
        --*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) [ "$name_mode" = preserve ] || exit 2; name=$1; name_mode=custom ;;
    esac
    shift
done
die() { echo "$*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die 'Run as root'
[ "$(uname -m)" = aarch64 ] || die 'Only aarch64 is supported'
[ -f /etc/alpine-release ] || die 'Alpine is required'
case "$(cat /etc/alpine-release)" in 3.24.*|3.24) ;; *) die 'Alpine 3.24 is required' ;; esac
sha256sum -c SHA256SUMS || die 'Bundle checksum verification failed'
[ -s /etc/asound.conf ] || die 'Configure ALSA default first; /etc/asound.conf is missing'
[ -d /dev/snd ] || die 'No ALSA device found'
conf=/etc/shairport-sync.conf
if [ "$name_mode" = file ]; then
    [ -f "$name_file" ] || die "Name file not found: $name_file"
    name=$(cat "$name_file")
    name_mode=custom
fi
if [ "$name_mode" = hostname ] || { [ "$name_mode" = preserve ] && [ ! -e "$conf" ]; }; then
    name=$(cat /etc/hostname) || die 'Cannot read /etc/hostname'
    name_mode=hostname
fi
if [ "$name_mode" != preserve ]; then
    [ -n "$name" ] && [ "$(printf %s "$name" | wc -c)" -le 50 ] || die 'Name must be 1..50 UTF-8 bytes'
    [ "$(printf %s "$name" | wc -l)" -eq 0 ] || die 'Name must be a single line'
    if printf %s "$name" | LC_ALL=C grep -q '[[:cntrl:]"\\]'; then
        die 'Name must not contain control characters, double quotes or backslashes'
    fi
    echo "AirPlay name: $name ($name_mode)"
else
    echo 'Keeping existing AirPlay name and configuration'
fi

# The control layer needs the tweaker's IPC socket; without it the receiver
# keeps its own software volume.
bridge=no
if [ -S /run/capsule-controls.sock ]; then bridge=yes; fi

# Check every target before changing anything.
for pair in 'bin/shairport-sync:/usr/local/bin/shairport-sync' \
            'bin/nqptp:/usr/local/sbin/nqptp' \
            'bin/capsule-ipc:/usr/local/bin/capsule-ipc' \
            'bin/ap2ctl:/usr/local/bin/ap2ctl' \
            'bin/ap2-volume-sync:/usr/local/bin/ap2-volume-sync' \
            'bin/ap2-bridge:/usr/local/bin/ap2-bridge' \
            'etc/init.d.nqptp:/etc/init.d/nqptp' \
            'etc/init.d.shairport-sync:/etc/init.d/shairport-sync' \
            'etc/init.d.ap2-bridge:/etc/init.d/ap2-bridge'; do
    src=${pair%%:*}; dst=${pair#*:}
    [ ! -L "$dst" ] || die "Refusing symlink: $dst"
    if [ -e "$dst" ] && ! cmp -s "$src" "$dst" && [ "$upgrade" != yes ]; then
        die "Different existing file: $dst. Use --upgrade for a backed-up update."
    fi
done
[ ! -L "$conf" ] || die "Refusing symlink: $conf"
df -Pk / | awk 'NR==2 {if ($4 < 30000) exit 1}' || die 'Need at least 30 MiB free'
if [ "$check" = yes ]; then echo "PREFLIGHT_PASS bridge=$bridge"; exit 0; fi

backup=$(mktemp -d /root/airplay2-backup-XXXXXXXX)
chmod 700 "$backup"
echo "Backup: $backup"
for path in /usr/local/bin/shairport-sync /usr/local/sbin/nqptp \
            /usr/local/bin/capsule-ipc /usr/local/bin/ap2ctl \
            /usr/local/bin/ap2-volume-sync /usr/local/bin/ap2-bridge \
            /etc/shairport-sync.conf /etc/init.d/nqptp \
            /etc/init.d/shairport-sync /etc/init.d/ap2-bridge; do
    if [ -e "$path" ]; then
        mkdir -p "$backup/files$(dirname "$path")"
        cp -p "$path" "$backup/files$path"
    fi
done
cp /etc/apk/world "$backup/apk-world.before"
rc-update show > "$backup/runlevels.before"
apk add --no-cache avahi avahi-tools dbus glib libplist libsodium libgcrypt \
    libconfig popt soxr libgomp libuuid

# Stop only our receiver, timing daemon and bridge before replacing binaries.
for svc in ap2-bridge shairport-sync nqptp; do
    if [ -f "/etc/init.d/$svc" ]; then rc-service "$svc" stop || die "Could not stop $svc"; fi
done
mkdir -p /usr/local/bin /usr/local/sbin /usr/share/dbus-1/system.d
for pair in 'bin/shairport-sync:/usr/local/bin/shairport-sync' \
            'bin/nqptp:/usr/local/sbin/nqptp' \
            'bin/capsule-ipc:/usr/local/bin/capsule-ipc' \
            'bin/ap2ctl:/usr/local/bin/ap2ctl' \
            'bin/ap2-volume-sync:/usr/local/bin/ap2-volume-sync' \
            'bin/ap2-bridge:/usr/local/bin/ap2-bridge' \
            'etc/init.d.nqptp:/etc/init.d/nqptp' \
            'etc/init.d.shairport-sync:/etc/init.d/shairport-sync' \
            'etc/init.d.ap2-bridge:/etc/init.d/ap2-bridge'; do
    src=${pair%%:*}; dst=${pair#*:}
    install -m 0755 "$src" "$dst.new"
    mv -f "$dst.new" "$dst"
done
install -m 0644 etc/dbus-policy.conf /usr/share/dbus-1/system.d/shairport-sync.conf
dbus-send --system --type=signal / org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true

[ -e "$conf" ] || install -m 0644 etc/shairport-sync.conf "$conf"
if [ "$name_mode" != preserve ]; then
    AIRPLAY_INSTALL_NAME=$name awk '
      /^[ \t]*name[ \t]*=/ { print "\tname = \"" ENVIRON["AIRPLAY_INSTALL_NAME"] "\";"; found=1; next }
      {print}
      END {if (!found) exit 1}
    ' "$conf" > "$conf.new" || die "No name field in config; backup: $backup"
    chmod 0644 "$conf.new"
    mv -f "$conf.new" "$conf"
fi
if [ "$bridge" = yes ] && ! grep -q 'run_this_when_volume_is_set' "$conf"; then
    awk '
      /^[ \t]*name[ \t]*=/ && !done {
          print
          print "\tignore_volume_control = \"yes\";"
          print "\trun_this_when_volume_is_set = \"/usr/local/bin/ap2-volume-sync\";"
          done = 1; next
      }
      { print }
    ' "$conf" > "$conf.new"
    chmod 0644 "$conf.new"
    mv -f "$conf.new" "$conf"
fi

for svc in avahi-daemon nqptp shairport-sync; do rc-update add "$svc" default; done
if [ "$bridge" = yes ]; then rc-update add ap2-bridge default; fi
rc-service dbus status >/dev/null 2>&1 || rc-service dbus start
rc-service avahi-daemon status >/dev/null 2>&1 || rc-service avahi-daemon start
rc-service nqptp start
rc-service shairport-sync start
if [ "$bridge" = yes ]; then rc-service ap2-bridge start; fi
sleep 3
for svc in avahi-daemon nqptp shairport-sync; do
    rc-service "$svc" status || die "Service failed: $svc. Backup: $backup"
done
if [ "$bridge" = yes ]; then
    rc-service ap2-bridge status || die "Bridge failed. Backup: $backup"
fi
if ! dbus-send --system --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.NameHasOwner string:org.gnome.ShairportSync | grep -q 'boolean true'; then
    die "No AirPlay D-Bus name. Backup: $backup"
fi
echo "INSTALL_PASS bridge=$bridge backup=$backup"
