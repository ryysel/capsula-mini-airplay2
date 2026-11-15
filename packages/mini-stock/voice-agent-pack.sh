#!/bin/sh
# Compress the patched overlay copy of voice-agent with UPX.
#
# The 8-byte volume patch has to live in /data/overlay/upper, so overlayfs keeps
# a full copy of the vendor binary there (13 MiB). UPX shrinks that copy to
# ~5-6 MiB; the kernel unpacks it in memory when the process starts, nothing has
# to be installed on the speaker.
#
# The compression level is chosen by available memory: lzma and -9 need more
# RAM than these speakers have free with the assistant running, so the levels
# are tried from strongest to weakest.
#
# Usage: sh voice-agent-pack.sh check|pack
#   check  exit 0 if the overlay holds our patched build, packed or not
#   pack   make sure it is packed (no-op when it already is)
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PATCHED_SHA=7282da6b2bcfe5dfe94c53753eee9a5f07e1dfb68d52e1103c41860753658ed6
DST=/data/overlay/upper/usr/bin/voice-agent
STOCK=/rom/usr/bin/voice-agent
UPX=$root/bin/upx
TMP=/data/.voice-agent-verify

sum() { sha256sum "$1" | cut -d' ' -f1; }

is_packed() { "$UPX" -t "$1" >/dev/null 2>&1; }

# Unpack to a temporary file under /data (not tmpfs) and compare with the
# expected patched build. Leaves nothing behind.
unpack_matches() {
    rm -f "$TMP"
    if ! "$UPX" -d -o "$TMP" "$1" >/dev/null 2>&1; then
        rm -f "$TMP"
        return 1
    fi
    got=$(sum "$TMP")
    rm -f "$TMP"
    [ "$got" = "$PATCHED_SHA" ]
}

case "${1:-pack}" in
check)
    [ -f "$DST" ] || exit 1
    if [ "$(sum "$DST")" = "$PATCHED_SHA" ]; then
        exit 0
    fi
    [ -x "$UPX" ] || exit 1
    if is_packed "$DST" && unpack_matches "$DST"; then
        exit 0
    fi
    exit 1
    ;;
pack)
    ;;
*)
    echo "Usage: $0 check|pack" >&2
    exit 2
    ;;
esac

[ -x "$UPX" ] || { echo "voice-agent: $UPX is missing or not executable" >&2; exit 1; }
[ -f "$DST" ] || { echo 'voice-agent: overlay copy not found' >&2; exit 1; }

if is_packed "$DST"; then
    if unpack_matches "$DST"; then
        echo 'voice-agent: already packed'
        exit 0
    fi
    echo 'voice-agent: packed copy does not unpack to the patched build' >&2
    exit 1
fi

if [ "$(sum "$DST")" != "$PATCHED_SHA" ]; then
    echo 'voice-agent: overlay copy is not the expected patched build' >&2
    exit 1
fi

# UPX writes a temporary file next to the input and renames it only on success,
# so a killed or failed run leaves the uncompressed copy in place.
packed=no
for level in -9 -5 -1; do
    rm -f "$DST.upx"
    if "$UPX" "$level" "$DST" >/dev/null 2>&1 && is_packed "$DST"; then
        echo "voice-agent: packed with UPX $level"
        packed=yes
        break
    fi
    rm -f "$DST.upx"
done
[ "$packed" = yes ] || { echo 'voice-agent: UPX failed, keeping the uncompressed copy' >&2; exit 1; }
chmod 0755 "$DST"

if ! unpack_matches "$DST"; then
    # Never leave a copy that cannot be verified: drop it from the overlay
    # directly (a delete through the merged path would white out the stock
    # binary) and let the next install recreate it.
    rm -f "$DST"
    echo 'voice-agent: packed copy failed verification; overlay copy removed' >&2
    echo 'voice-agent: run install.sh again to recreate it' >&2
    exit 1
fi

sync
echo "voice-agent: $(wc -c < "$DST") bytes in the overlay instead of $(wc -c < "$STOCK")"
echo 'voice-agent: takes effect after the next reboot'
