#!/bin/sh
# Native volume for the VK Капсула 2019.
#
# The stock voice-agent applies an incoming OnVolumeChangedEvent only when the
# event is flagged "remote" (voice_agent.cpp:7875). Everything relayed through
# the local stereoctl socket is flagged remote=0, so a volume sent from outside
# is recorded but never applied: the phone slider and the speaker knob stay two
# independent gains. Two guards in that handler are replaced with "always true"
# (8 bytes in total), after which an OnSetVolumeRequest relayed by stereoctl is
# applied natively -- PulseAudio sink, LED ring, saved settings and the VK
# cloud state all follow the same value.
#
# The firmware root is an overlayfs with upperdir=/data/overlay/upper, so the
# patched binary is written there (never into the read-only squashfs) and is
# used from the next boot on. Remove that file to roll back.
#
# The bytes are patched into the vendor binary, which is why this package ships
# a tiny patcher instead of a modified 13 MiB copy: the stock build is
# identified by its SHA-256 and the result is verified before it is kept.
set -eu

STOCK_SHA=566e30bd0059428d5f46d6134ab538ea862f2b993ff525e8499b1304f8434209
PATCHED_SHA=e58d5e46c2b26e7c20ab740c11b03993472aa032d142cc25c127204728dcb9b5
SRC=/usr/bin/voice-agent
DST=/data/overlay/upper/usr/bin/voice-agent
OFF1=1545316 # 0x179464, "ldrb w0,[x19,#4]" -> "mov w0,#1"
OFF2=1545432 # 0x1794d8, "ldrb w0,[x19,#4]" -> "mov w0,#1"

sum_of() { sha256sum "$1" | cut -d' ' -f1; }

if [ -f "$DST" ]; then
    if [ "$(sum_of "$DST")" = "$PATCHED_SHA" ]; then
        echo "voice-agent: already patched"
        exit 0
    fi
    echo "voice-agent: $DST exists but is not the expected build; leaving it alone" >&2
    exit 1
fi

test -f "$SRC" || { echo "voice-agent not found at $SRC" >&2; exit 1; }
cur=$(sum_of "$SRC")
if [ "$cur" != "$STOCK_SHA" ]; then
    echo "voice-agent: unknown build ($cur), refusing to patch" >&2
    echo "  this package was written for the 44.90 firmware" >&2
    exit 1
fi

mkdir -p "$(dirname "$DST")"
cp "$SRC" "$DST"

# 52 80 00 20 little-endian == "mov w0, #1" (AArch64).
printf '20008052\n' | xxd -r -p > /tmp/capsula-voice-agent.bin
dd of="$DST" bs=1 seek=$OFF1 conv=notrunc < /tmp/capsula-voice-agent.bin 2>/dev/null
dd of="$DST" bs=1 seek=$OFF2 conv=notrunc < /tmp/capsula-voice-agent.bin 2>/dev/null
rm -f /tmp/capsula-voice-agent.bin
chmod 0755 "$DST"

if [ "$(sum_of "$DST")" != "$PATCHED_SHA" ]; then
    rm -f "$DST"
    echo "voice-agent: patch verification failed, rolled back" >&2
    exit 1
fi

sync
echo "voice-agent: patched; takes effect after the next reboot"
