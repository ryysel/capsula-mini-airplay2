#!/bin/sh
# Remove the AirPlay 2 receiver installed by install.sh on VK Capsula Mini stock.
set -eu
uid=$(grep '^Uid:' /proc/self/status | cut -f2)
[ "$uid" = 0 ] || { echo 'Run as root' >&2; exit 1; }

# Stop the services through the control script when it is still present.
if [ -x /data/local/capsula-airplay/S99airplay ]; then
    sh /data/local/capsula-airplay/S99airplay stop || true
fi
if [ -x /etc/init.d/S99airplay ]; then
    /etc/init.d/S99airplay stop || true
fi

rm -f /etc/init.d/S99airplay
# Removing the overlay copy restores the stock avahi script from /rom.
rm -f /etc/init.d/S50avahi-daemon
rm -rf /data/local/capsula-airplay
rm -f /var/run/capsula-airplay-keys.pid /var/run/capsula-airplay-ring.pid
rm -f /var/run/nqptp.pid /var/run/shairport-sync.pid

echo 'Removed. The stock firmware, voice-agent and the OTA stub were left untouched.'
echo 'Backups from install.sh remain as /data/local/capsula-airplay.backup-*.'
