#!/bin/sh
# Remove the AirPlay 2 receiver and control layer installed by install.sh.
set -eu
test "$(id -u)" = 0 || { echo "Run as root" >&2; exit 1; }

for svc in ap2-bridge shairport-sync nqptp avahi-daemon; do
    rc-service "$svc" stop >/dev/null 2>&1 || true
    rc-update del "$svc" default >/dev/null 2>&1 || true
done

rm -f /usr/local/bin/shairport-sync \
      /usr/local/sbin/nqptp \
      /usr/local/bin/capsule-ipc \
      /usr/local/bin/ap2ctl \
      /usr/local/bin/ap2-volume-sync \
      /usr/local/bin/ap2-bridge \
      /etc/shairport-sync.conf \
      /etc/init.d/nqptp \
      /etc/init.d/shairport-sync \
      /etc/init.d/ap2-bridge \
      /usr/share/dbus-1/system.d/shairport-sync.conf
dbus-send --system --type=signal / org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
rm -f /run/ap2-bridge.state /run/ap2-volume.suppress /run/ap2-volume.phone

echo "Removed. /etc/asound.conf and apk packages were left untouched."
echo "Backups from install.sh remain under /root/airplay2-backup-*."
echo "To remove packages too: apk del avahi avahi-tools dbus glib libplist libsodium libgcrypt libconfig popt soxr libgomp libuuid"
