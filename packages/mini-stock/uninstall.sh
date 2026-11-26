#!/bin/sh
set -eu
uid=$(grep '^Uid:' /proc/self/status | cut -f2)
[ "$uid" = 0 ] || { echo 'Run as root' >&2; exit 1; }
D=/data/local/capsula-airplay
UPPER=/data/overlay/upper/usr/bin/voice-agent
WRAP=/data/overlay/upper/usr/bin/voice-agent.sh
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$WRAP" ] && grep -q 'capsula:fallback' "$WRAP"; then
    wrapper_sum=$(sha256sum "$WRAP" | cut -d' ' -f1)
    case "$wrapper_sum" in
        82a498025166d199343398ac7f9fdcb659c472f9b0de0ab784c30d9fc11713cb|99483ff16996719e7ed2201dcf1b4a63ab15b472f15068d1c6aa77272fa3041f) : ;;
        *) echo 'Custom wrapper: preserve it and remove package hooks manually first.' >&2; exit 1 ;;
    esac
fi

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
  saved=$WRAP.pre-uninstall-$$
    [ ! -e "$saved" ] || exit 1
    mv "$WRAP" "$saved"
    echo "Previous wrapper preserved: $saved"
  echo 'voice-agent wrapper: fallback removed'
fi
if [ -x "$D/S99airplay" ]; then sh "$D/S99airplay" stop || true; fi
# Unlinking through overlayfs would white-out the lower script, NOT reveal it.
# Restore its original bytes instead.
cp /rom/etc/init.d/S50avahi-daemon /etc/init.d/S50avahi-daemon.rollback
chmod 755 /etc/init.d/S50avahi-daemon.rollback
mv /etc/init.d/S50avahi-daemon.rollback /etc/init.d/S50avahi-daemon
rm -f /etc/init.d/S99airplay
# Only remove known installed files; retain calibration, backups and unrelated files.
for file in bin/shairport-sync bin/nqptp bin/capsula-ui bin/capsula-airplay-keys bin/libuuid.so.1.3.0 bin/libuuid.so.1 init.d/nqptp init.d/shairport-sync S99airplay; do
    rm -f "$D/$file"
done
echo 'AirPlay removed. Firmware and account preserved; backups remain.'
echo 'Reboot manually to load the stock voice-agent again.'
