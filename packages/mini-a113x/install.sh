#!/bin/sh
# Install AirPlay 2 receiver (shairport-sync + nqptp) on Alpine 3.24 / aarch64.
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
same_or_absent etc/shairport-sync.conf   /etc/shairport-sync.conf
same_or_absent etc/init.d.nqptp          /etc/init.d/nqptp
same_or_absent etc/init.d.shairport-sync /etc/init.d/shairport-sync

df -Pk / | awk 'NR == 2 { if ($4 < 20000) { print "Not enough free space" > "/dev/stderr"; exit 1 } }'

apk add --no-cache avahi avahi-tools libplist libsodium libgcrypt \
    libconfig popt soxr libgomp libuuid >/dev/null

mkdir -p /usr/local/bin /usr/local/sbin
install -m 0755 bin/shairport-sync /usr/local/bin/shairport-sync
install -m 0755 bin/nqptp /usr/local/sbin/nqptp
install -m 0755 etc/init.d.nqptp /etc/init.d/nqptp
install -m 0755 etc/init.d.shairport-sync /etc/init.d/shairport-sync

# Keep an existing local configuration: only write the shipped one when absent
# or already identical.
if [ ! -e /etc/shairport-sync.conf ]; then
    install -m 0644 etc/shairport-sync.conf /etc/shairport-sync.conf
fi
if [ "$name" != "Капсула Мини" ]; then
    sed -i "s|^\([[:space:]]*name = \).*|\1\"$name\";|" /etc/shairport-sync.conf
fi

rc-update add avahi-daemon default
rc-update add nqptp default
rc-update add shairport-sync default

rc-service dbus start >/dev/null 2>&1 || true
rc-service avahi-daemon start || true
rc-service nqptp start || true
sleep 2
rc-service shairport-sync start || true
sleep 3

echo "== services"
rc-service avahi-daemon status
rc-service nqptp status
rc-service shairport-sync status
echo "== ports"
ss -lunp | grep -E ':(319|320) ' || true
ss -lntp | grep -E ':7000 ' || true
echo "== airplay"
avahi-browse -rt _airplay._tcp 2>/dev/null | grep -A8 'hostname' | head -12 || true
echo "== hashes"
sha256sum /usr/local/bin/shairport-sync /usr/local/sbin/nqptp
echo INSTALL_PASS
