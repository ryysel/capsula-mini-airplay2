#!/bin/sh
# AirPlay 2 receiver for Alpine 3.24 / aarch64 (musl), built natively in an
# arm64 container. Pins follow Yandex-Station-Universal-Repo/Station-airplay:
# shairport-sync 5.6.2, nqptp 1.2.9 (smi11), FFmpeg 7.1.3 (AAC/ALAC only).
# Output: /out/{shairport-sync,nqptp} plus version log. No private libs:
# the target device gets matching Alpine 3.24 packages via apk.
set -eu

SPS_TAG=5.6.2
NQPTP_TAG=1.2.9
FFMPEG_TAG=n7.1.3
SRC=/work/src
FFOUT=/work/ffout
OUT=/out

echo "=== deps ==="
apk add --no-cache build-base autoconf automake libtool git pkgconf xxd \
  alsa-lib-dev popt-dev libconfig-dev soxr-dev openssl-dev avahi-dev \
  libplist-dev libplist-util libsodium-dev libgcrypt-dev util-linux-dev linux-headers >/dev/null

mkdir -p "$SRC" "$OUT"
clone() { [ -d "$SRC/$3/.git" ] || { rm -rf "$SRC/$3"; git clone -q --depth=1 -b "$2" "$1" "$SRC/$3"; }; }
clone https://github.com/FFmpeg/FFmpeg.git "$FFMPEG_TAG" ffmpeg
clone https://github.com/mikebrady/nqptp.git "$NQPTP_TAG" nqptp
clone https://github.com/mikebrady/shairport-sync.git "$SPS_TAG" shairport-sync

echo "=== ffmpeg $FFMPEG_TAG (aac/alac, static) ==="
if [ ! -f "$FFOUT/lib/libavcodec.a" ]; then
cd "$SRC/ffmpeg"
[ -f config.h ] && make distclean >/dev/null 2>&1 || true
./configure --prefix="$FFOUT" \
  --disable-everything --disable-programs --disable-doc --disable-network \
  --disable-avdevice --disable-avfilter --disable-swscale \
  --disable-autodetect --disable-shared --enable-static --enable-pic \
  --enable-decoder=aac,alac --enable-parser=aac \
  --enable-demuxer=mov --enable-protocol=file \
  >/tmp/ffcfg.log 2>&1 || { tail -30 /tmp/ffcfg.log; exit 1; }
make -j4 >/tmp/ffmake.log 2>&1 || { tail -30 /tmp/ffmake.log; exit 1; }
make install >/dev/null
fi

echo "=== nqptp $NQPTP_TAG ==="
cd "$SRC/nqptp"
[ -x nqptp ] || {
  autoreconf -fi >/dev/null 2>&1
  ./configure >/dev/null
  make -j4 >/tmp/nqmake.log 2>&1 || { tail -30 /tmp/nqmake.log; exit 1; }
}

echo "=== shairport-sync $SPS_TAG (AirPlay 2) ==="
cd "$SRC/shairport-sync"
# Local modification: advertise the same round-speaker model as Mini/Lite.
# Apply once, invalidate only the receiver binary, and retain upstream version provenance.
git config --global --add safe.directory "$SRC/shairport-sync"
if grep -q 'config.model = strdup("ShairportSync");' shairport.c; then
  sed -i 's/config.model = strdup("ShairportSync");/config.model = strdup("AudioAccessory5,1");/' shairport.c
  rm -f shairport-sync
fi
grep -q '^  config.model = strdup("AudioAccessory5,1");' shairport.c
[ -x shairport-sync ] || {
  autoreconf -fi >/dev/null 2>&1
  PKG_CONFIG_PATH="$FFOUT/lib/pkgconfig" ./configure --sysconfdir=/etc \
    --with-alsa --with-soxr --with-avahi --with-ssl=openssl \
    --with-airplay-2 --with-metadata --with-piddir=/run \
    >/tmp/spscfg.log 2>&1 || { tail -40 /tmp/spscfg.log; exit 1; }
  make -j4 >/tmp/spsmake.log 2>&1 || { tail -40 /tmp/spsmake.log; exit 1; }
}

cp "$SRC/shairport-sync/shairport-sync" "$SRC/nqptp/nqptp" "$OUT/"
strip "$OUT/shairport-sync" "$OUT/nqptp"

{
  echo "shairport-source $(git -C "$SRC/shairport-sync" rev-parse HEAD)"
  echo "nqptp-source $(git -C "$SRC/nqptp" rev-parse HEAD)"
  echo "ffmpeg-source $(git -C "$SRC/ffmpeg" rev-parse HEAD)"
  "$OUT/shairport-sync" -V
  "$OUT/nqptp" -V
  ldd "$OUT/shairport-sync" || true
  sha256sum "$OUT/shairport-sync" "$OUT/nqptp"
} > "$OUT/BUILD_INFO.txt" 2>&1

echo "=== DONE $(date -u) ==="
