#!/bin/sh
# Remove the AirPlay 2 receiver for VK Капсула 2019 and the voice-agent volume
# patch.
# No awk/sed on this firmware: the wrapper is filtered line by line in sh.
set -eu

BASE=/data/local
DEST=$BASE/capsula-airplay
WRAP=/data/overlay/upper/usr/bin/voice-agent.sh
VA=/data/overlay/upper/usr/bin/voice-agent
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

uid=$(grep '^Uid:' /proc/self/status | cut -f2)
test "$uid" = 0 || { echo "Run as root on the capsule." >&2; exit 1; }

if [ -f "$WRAP" ] && grep -q -e 'capsula-boot' -e 'capsula:fallback' "$WRAP"; then
    wrapper_sum=$(sha256sum "$WRAP" | cut -d' ' -f1)
    expected=$(while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "exec voice-agent"*) cat <<'PACKAGE_BLOCK'
( sleep 10; [ -x /data/local/bin/capsula-boot ] && /data/local/bin/capsula-boot ) >/dev/null 2>&1 &

# capsula:fallback -- start the (possibly UPX-packed) overlay copy; if it dies
# right away, exec the stock binary from /rom so voice-agent always comes up.
voice-agent "$@" &
capsula_pid=$!
capsula_wait=0
while [ "$capsula_wait" -lt 3 ] && kill -0 "$capsula_pid" 2>/dev/null; do
    sleep 1
    capsula_wait=$((capsula_wait + 1))
done
if kill -0 "$capsula_pid" 2>/dev/null; then
    wait "$capsula_pid"
    exit $?
fi
logger -t voice-agent "packed copy exited at startup; using stock" 2>/dev/null || true
exec /rom/usr/bin/voice-agent "$@"
PACKAGE_BLOCK
                ;;
            *) printf '%s\n' "$line" ;;
        esac
    done < /rom/usr/bin/voice-agent.sh | sha256sum | cut -d' ' -f1)
    case "$wrapper_sum" in
        "$expected") : ;;
        *) echo 'Custom wrapper: preserve it and remove package hooks manually first.' >&2; exit 1 ;;
    esac
fi

"$BASE/capsula-boot.d/30-airplay.sh" stop 2>/dev/null || true

rm -f "$BASE/capsula-boot.d/30-airplay.sh"
# Only remove known installed files; retain calibration, backups and unrelated files.
for file in bin/capsula-ui bin/capsula-led-media bin/shairport-sync bin/nqptp bin/apply-timing-profile init.d/nqptp init.d/shairport-sync init.d/capsula-ui; do
    rm -f "$DEST/$file"
done

# The wrapper only exists in the overlay when the package added its boot hook
# and the stock fallback. Removing the overlay copy reveals the stock script.
if [ -f "$WRAP" ] && grep -q -e 'capsula-boot' -e 'capsula:fallback' "$WRAP"; then
    saved=$WRAP.pre-uninstall-$$
    [ ! -e "$saved" ] || exit 1
    mv "$WRAP" "$saved"
    echo "Previous wrapper preserved: $saved"
    echo "voice-agent wrapper: package hook removed"
fi

# The patched voice-agent only exists in the overlay; removing that copy
# restores the stock binary from the read-only firmware on the next boot.
if [ -f "$VA" ]; then
    if sh "$root/voice-agent-pack.sh" check; then
        rm -f "$VA"
        echo "voice-agent: volume patch removed"
    else
        echo "Keeping unrecognised overlay voice-agent; it is not this package's patch."
    fi
fi

sync

echo "Removed. Reboot to restore the stock voice-agent and wrapper."
echo UNINSTALL_PASS
