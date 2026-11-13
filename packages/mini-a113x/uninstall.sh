#!/bin/sh
# Remove the AirPlay 2 receiver installed by install.sh.
set -eu

test "$(id -u)" = 0 || { echo "Run as root" >&2; exit 1; }

for svc in shairport-sync nqptp avahi-daemon; do
    rc-service "$svc" stop >/dev/null 2>&1 || true
    rc-update del "$svc" default >/dev/null 2>&1 || true
done

rm -f /usr/local/bin/shairport-sync \
      /usr/local/sbin/nqptp \
      /etc/shairport-sync.conf \
      /etc/init.d/nqptp \
      /etc/init.d/shairport-sync

echo "Removed. /etc/asound.conf and apk packages were left untouched."
echo "To remove packages too: apk del avahi avahi-tools libplist libsodium libgcrypt libconfig popt soxr libgomp libuuid"
