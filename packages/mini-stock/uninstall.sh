#!/bin/sh
set -eu
uid=$(grep '^Uid:' /proc/self/status | cut -f2)
[ "$uid" = 0 ] || { echo 'Run as root' >&2; exit 1; }
D=/data/local/capsula-airplay
UPPER=/data/overlay/upper/usr/bin/voice-agent
WRAP=/data/overlay/upper/usr/bin/voice-agent.sh
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ -e "$UPPER" ]; then
  if sh "$root/voice-agent-pack.sh" check; then
    # Remove the overlay copy itself, not the merged path: deleting through
    # overlayfs would white out the stock binary instead of revealing it.
    rm -f "$UPPER"
    echo 'voice-agent: volume patch removed'
  else
    echo 'Unknown voice-agent overlay; refusing' >&2
    exit 1
  fi
fi
if [ -f "$WRAP" ] && grep -q 'capsula:fallback' "$WRAP"; then
  rm -f "$WRAP"
  echo 'voice-agent wrapper: fallback removed'
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
