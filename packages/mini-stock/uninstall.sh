#!/bin/sh
set -eu
uid=$(grep '^Uid:' /proc/self/status | cut -f2)
[ "$uid" = 0 ] || { echo 'Run as root' >&2; exit 1; }
D=/data/local/capsula-airplay
UPPER=/data/overlay/upper/usr/bin/voice-agent
PATCHED=7282da6b2bcfe5dfe94c53753eee9a5f07e1dfb68d52e1103c41860753658ed6
if [ -e "$UPPER" ]; then
  current=$(sha256sum "$UPPER" | cut -d' ' -f1)
  [ "$current" = "$PATCHED" ] || { echo 'Unknown voice-agent overlay; refusing'; exit 1; }
  # Restore the stock path atomically; never stop the running voice-agent.
  cp /rom/usr/bin/voice-agent /usr/bin/voice-agent.rollback
  chmod 755 /usr/bin/voice-agent.rollback
  mv /usr/bin/voice-agent.rollback /usr/bin/voice-agent
fi
if [ -x "$D/S99airplay" ]; then sh "$D/S99airplay" stop || true; fi
# Unlinking through overlayfs would white-out the lower script, NOT reveal it.
# Restore its original bytes instead.
cp /rom/etc/init.d/S50avahi-daemon /etc/init.d/S50avahi-daemon.rollback
chmod 755 /etc/init.d/S50avahi-daemon.rollback
mv /etc/init.d/S50avahi-daemon.rollback /etc/init.d/S50avahi-daemon
rm -f /etc/init.d/S99airplay
rm -rf "$D"
echo 'AirPlay removed. Firmware and account preserved; backups remain.'
echo 'Reboot manually to load the stock voice-agent again.'
