#!/bin/sh
# Native volume guard patch, Mini stock 44.90 ONLY. No writes to /rom.
set -eu
SRC=/rom/usr/bin/voice-agent
DST=/data/overlay/upper/usr/bin/voice-agent
STOCK=e91c758edaae7ef258691438439906b4bd5986609a3be9fde946e59fc15ed9b7
PATCHED=7282da6b2bcfe5dfe94c53753eee9a5f07e1dfb68d52e1103c41860753658ed6
sum() { sha256sum "$1" | cut -d' ' -f1; }
[ "$(sum "$SRC")" = "$STOCK" ] || { echo 'Unknown firmware: refusing'; exit 1; }
if [ -e "$DST" ]; then
  [ "$(sum "$DST")" = "$PATCHED" ] || { echo 'Unknown overlay: refusing'; exit 1; }
  echo 'Native volume already patched'
  exit 0
fi
mkdir -p /data/overlay/upper/usr/bin
[ ! -e "$DST.new" ] || { echo 'Existing staging file: refusing'; exit 1; }
cp "$SRC" "$DST.new"
# ldrb w0,[x19,#4] -> mov w0,#1: accept local stereoctl events.
# File offsets equal virtual addresses for these verified text mappings.
printf '\040\000\200\122' | dd of="$DST.new" bs=1 seek=1557908 conv=notrunc 2>/dev/null
printf '\040\000\200\122' | dd of="$DST.new" bs=1 seek=1558024 conv=notrunc 2>/dev/null
[ "$(sum "$DST.new")" = "$PATCHED" ] || { echo 'PATCH HASH MISMATCH'; exit 1; }
chmod 755 "$DST.new"
mv "$DST.new" "$DST"
sync
echo 'PATCH_VERIFIED. Native sink, buttons and numeric display activate after reboot.'
