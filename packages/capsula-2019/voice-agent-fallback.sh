#!/bin/sh
# Start-path fallback for the voice-agent.
#
# The patched copy of /usr/bin/voice-agent lives in the overlay and is UPX
# packed. If that copy ever fails to start (bad flash, unexpected firmware
# change), the assistant -- and the watchdog that expects it -- must still come
# up. This installs the stock wrapper with one addition: start the overlay copy,
# and if it dies within a few seconds, exec the stock binary from /rom.
#
# Idempotent. Never writes to /rom.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
STOCK=/usr/bin/voice-agent.sh
FALLBACK=/rom/usr/bin/voice-agent
WRAP=/data/overlay/upper/usr/bin/voice-agent.sh
MARK='# capsula:fallback'

[ -f "$STOCK" ] || { echo 'voice-agent: stock wrapper not found' >&2; exit 1; }
[ -x "$FALLBACK" ] || { echo 'voice-agent: stock binary not found in /rom' >&2; exit 1; }

if [ -f "$WRAP" ] && grep -q "$MARK" "$WRAP"; then
    echo 'voice-agent wrapper: fallback already installed'
    exit 0
fi

src=$STOCK
[ ! -f "$WRAP" ] || src=$WRAP
[ ! -e "$WRAP.new" ] || { echo "voice-agent wrapper: $WRAP.new already exists" >&2; exit 1; }

: > "$WRAP.new"
found=no
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        "exec voice-agent"*)
            cat >> "$WRAP.new" <<'BLOCK'
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
BLOCK
            found=yes
            ;;
        *)
            printf '%s\n' "$line" >> "$WRAP.new"
            ;;
    esac
done < "$src"

if [ "$found" != yes ]; then
    rm -f "$WRAP.new"
    echo 'voice-agent wrapper: no "exec voice-agent" line in the stock wrapper' >&2
    exit 1
fi
chmod 0755 "$WRAP.new"
mv -f "$WRAP.new" "$WRAP"
echo 'voice-agent wrapper: stock fallback installed'
