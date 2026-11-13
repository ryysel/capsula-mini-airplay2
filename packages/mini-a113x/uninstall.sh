#!/bin/sh
# Remove the AirPlay 2 receiver installed by install.sh.
set -eu

test "$(id -u)" = 0 || { echo "Run as root" >&2; exit 1; }

for svc in shairport-sync capsula-art nqptp avahi-daemon; do
    rc-service "$svc" stop >/dev/null 2>&1 || true
    rc-update del "$svc" default >/dev/null 2>&1 || true
done

rm -f /usr/local/bin/shairport-sync \
      /usr/local/sbin/nqptp \
      /usr/local/bin/capsula-art \
      /etc/init.d/nqptp \
      /etc/init.d/capsula-art \
      /etc/init.d/shairport-sync \
      /run/capsula-art.pid
rm -rf /tmp/shairport-sync-covers

# Restore the configuration and the wake button as they were before the
# installer touched them.
if [ -f /etc/shairport-sync.conf.stock ]; then
    cp -p /etc/shairport-sync.conf.stock /etc/shairport-sync.conf
    rm -f /etc/shairport-sync.conf.stock
else
    rm -f /etc/shairport-sync.conf
fi
if [ -f /usr/local/bin/marusya-wake.stock ]; then
    cp -p /usr/local/bin/marusya-wake.stock /usr/local/bin/marusya-wake
    rm -f /usr/local/bin/marusya-wake.stock
fi

echo "Removed. /etc/asound.conf and apk packages were left untouched."
echo "To remove packages too: apk del avahi avahi-tools libplist libsodium libgcrypt libconfig popt soxr libgomp libuuid"
