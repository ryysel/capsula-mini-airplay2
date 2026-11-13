#!/bin/sh
# Install AirPlay 2 receiver (shairport-sync + nqptp) on Alpine 3.24 / aarch64,
# together with the album-art ring overlay and the AirPlay-aware wake button.
# Run from the repository root: sh install.sh ["AirPlay name"]
set -eu

name=${1:-"Капсула Мини"}
root=$(cd "$(dirname "$0")" && pwd)
cd "$root"

test "$(id -u)" = 0 || { echo "Run as root" >&2; exit 1; }
test "$(uname -m)" = aarch64 || { echo "Only aarch64 is supported" >&2; exit 1; }
test -f /etc/alpine-release || { echo "This is not Alpine Linux" >&2; exit 1; }
case "$(cat /etc/alpine-release)" in
    3.24*) ;;
    *) echo "Tested on Alpine 3.24 only, found $(cat /etc/alpine-release)" >&2; exit 1 ;;
esac

test -f SHA256SUMS || { echo "SHA256SUMS not found" >&2; exit 1; }
sha256sum -c SHA256SUMS

same_or_absent() {
    src=$1 dst=$2
    if [ -e "$dst" ]; then
        if ! cmp -s "$src" "$dst"; then
            echo "Refusing to overwrite existing (different): $dst" >&2
            exit 1
        fi
        echo "Already in place: $dst"
    fi
}
same_or_absent bin/shairport-sync        /usr/local/bin/shairport-sync
same_or_absent bin/nqptp                 /usr/local/sbin/nqptp
same_or_absent etc/init.d.nqptp          /etc/init.d/nqptp
same_or_absent etc/init.d.shairport-sync /etc/init.d/shairport-sync

df -Pk / | awk 'NR == 2 { if ($4 < 20000) { print "Not enough free space" > "/dev/stderr"; exit 1 } }'

apk add --no-cache avahi avahi-tools libplist libsodium libgcrypt \
    libconfig popt soxr libgomp libuuid >/dev/null

mkdir -p /usr/local/bin /usr/local/sbin
# A running daemon holds its own binary; stop it before the swap so the write
# cannot fail with "text file busy".
rc-service capsula-art stop >/dev/null 2>&1 || true
install -m 0755 bin/shairport-sync /usr/local/bin/shairport-sync
install -m 0755 bin/nqptp /usr/local/sbin/nqptp
install -m 0755 bin/capsula-art /usr/local/bin/capsula-art
install -m 0755 etc/init.d.nqptp /etc/init.d/nqptp
install -m 0755 etc/init.d.shairport-sync /etc/init.d/shairport-sync
install -m 0755 etc/init.d.capsula-art /etc/init.d/capsula-art

# A local configuration is kept as .stock and replaced only when it does not
# yet carry the metadata block, so a reinstall never loses a custom name.
if [ ! -f /etc/shairport-sync.conf.stock ]; then
    cp -p /etc/shairport-sync.conf /etc/shairport-sync.conf.stock 2>/dev/null || true
fi
if ! grep -q 'cover_art_cache_directory' /etc/shairport-sync.conf 2>/dev/null; then
    keep=""
    if [ -e /etc/shairport-sync.conf ]; then
        keep=$(sed -n 's/^[[:space:]]*name = "\(.*\)";/\1/p' /etc/shairport-sync.conf | head -1)
    fi
    install -m 0644 etc/shairport-sync.conf /etc/shairport-sync.conf
    if [ -n "$keep" ] && [ "$keep" != "Капсула Мини" ]; then
        sed -i "s|^\([[:space:]]*name = \).*|\1\"$keep\";|" /etc/shairport-sync.conf
    fi
fi
if [ -n "$name" ] && [ "$name" != "Капсула Мини" ]; then
    sed -i "s|^\([[:space:]]*name = \).*|\1\"$name\";|" /etc/shairport-sync.conf
fi

# The broker runs marusya-wake on the top button. While a sender is connected
# the same press is play/pause; otherwise the stock wake path is untouched.
if [ -x /usr/local/bin/marusya-wake ]; then
    if [ ! -f /usr/local/bin/marusya-wake.stock ]; then
        cp -p /usr/local/bin/marusya-wake /usr/local/bin/marusya-wake.stock
    fi
    install -m 0755 etc/marusya-wake /usr/local/bin/marusya-wake
else
    echo "marusya-wake not found: skipping the AirPlay-aware button" >&2
fi

mkdir -p /tmp/shairport-sync-covers

rc-update add avahi-daemon default
rc-update add nqptp default
rc-update add capsula-art default
rc-update add shairport-sync default

rc-service dbus start >/dev/null 2>&1 || true
rc-service avahi-daemon start || true
rc-service nqptp start || true
rc-service capsula-art start || true
sleep 2
rc-service shairport-sync start || true
sleep 3

echo "== services"
rc-service avahi-daemon status
rc-service nqptp status
rc-service capsula-art status
rc-service shairport-sync status
echo "== ports"
ss -lunp | grep -E ':(319|320) ' || true
ss -lntp | grep -E ':7000 ' || true
echo "== airplay"
avahi-browse -rt _airplay._tcp 2>/dev/null | grep -A8 'hostname' | head -12 || true
echo "== hashes"
sha256sum /usr/local/bin/shairport-sync /usr/local/sbin/nqptp /usr/local/bin/capsula-art
echo INSTALL_PASS
