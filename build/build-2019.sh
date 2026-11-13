#!/bin/bash
# Cross-build AirPlay 2 receiver (shairport-sync + nqptp) for VK Capsula 2019
# (RK3308, Buildroot 2022.11, glibc 2.33, aarch64).
#
# Run inside the capsula-2019-airplay-builder image (see build/Dockerfile):
#   docker run --rm -v <workspace>:/work -w /work capsula-2019-airplay-builder \
#       bash /work/build/build-2019.sh
#
# Toolchain: bullseye cross gcc-10 / glibc 2.31 -> runs on target glibc 2.33.
# Static: libconfig, popt, soxr, libsodium, libgpg-error, libgcrypt, libplist,
#         ffmpeg (aac/alac only).
# Dynamic (already on the capsule): libc, libm, libpthread, libdl,
#         libavahi-client.so.3, libavahi-common.so.3, libpulse.so.0,
#         libpulse-simple.so.0, libuuid.so.1, libssl.so.1.1, libcrypto.so.1.1.
set -euo pipefail

WORK=${WORK:-/work}
SRC=$WORK/src
SYSROOT=$WORK/sysroot
OUT=$WORK/out
JOBS=$(nproc)

log() { echo "=== $*"; }

run() { # name logfile command...
    local name=$1 logf=$2
    shift 2
    echo "--- $name"
    if ! "$@" >"$logf" 2>&1; then
        echo "FAILED: $name"
        tail -40 "$logf"
        exit 1
    fi
}

if [ ! -d "$SYSROOT/usr/lib/aarch64-linux-gnu" ]; then
    log "extract arm64 debs into sysroot"
    mkdir -p "$SYSROOT"
    for d in /opt/debs/*.deb; do dpkg -x "$d" "$SYSROOT"; done
fi

export CC=aarch64-linux-gnu-gcc
export CXX=aarch64-linux-gnu-g++
export AR=aarch64-linux-gnu-ar
export RANLIB=aarch64-linux-gnu-ranlib
export STRIP=aarch64-linux-gnu-strip
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export CPPFLAGS="-I$SYSROOT/usr/include -I$SYSROOT/usr/include/aarch64-linux-gnu"
export LDFLAGS="-L$SYSROOT/usr/lib -L$SYSROOT/usr/lib/aarch64-linux-gnu -L$SYSROOT/lib -L$SYSROOT/lib/aarch64-linux-gnu -Wl,-rpath-link,$SYSROOT/usr/lib/aarch64-linux-gnu -Wl,-rpath-link,$SYSROOT/lib/aarch64-linux-gnu -Wl,--allow-shlib-undefined"
COMMON="--host=aarch64-linux-gnu --prefix=/usr --disable-shared --enable-static"

mkdir -p "$SRC" "$OUT"
cd "$SRC"
get() { [ -f "$2" ] || wget -q "$1" -O "$2"; }

# Skip deps that are already installed in the persistent sysroot.
have() {
    [ -f "$SYSROOT/usr/lib/$1" ] || [ -f "$SYSROOT/usr/lib/aarch64-linux-gnu/$1" ]
}

log "libconfig 1.7.3"
if have libconfig.a; then echo "already built"; else
get https://github.com/hyperrealm/libconfig/releases/download/v1.7.3/libconfig-1.7.3.tar.gz libconfig-1.7.3.tar.gz
[ -d libconfig-1.7.3 ] || tar xf libconfig-1.7.3.tar.gz
(cd libconfig-1.7.3 && run configure /tmp/libconfig.log ./configure $COMMON \
    && run make /tmp/libconfig.log make -j"$JOBS" \
    && run install /tmp/libconfig.log make install DESTDIR="$SYSROOT")
fi

log "popt 1.19"
if have libpopt.a; then echo "already built"; else
get https://github.com/rpm-software-management/popt/archive/refs/tags/popt-1.19-release.tar.gz popt-1.19.tar.gz
[ -d popt-popt-1.19-release ] || tar xf popt-1.19.tar.gz
(cd popt-popt-1.19-release && run autoreconf /tmp/popt.log autoreconf -fi \
    && run configure /tmp/popt.log ./configure $COMMON \
    && run make /tmp/popt.log make -j"$JOBS" \
    && run install /tmp/popt.log make install DESTDIR="$SYSROOT")
fi

log "soxr 0.1.3"
if have libsoxr.a; then echo "already built"; else
get https://github.com/chirlu/soxr/archive/refs/tags/0.1.3.tar.gz soxr-0.1.3.tar.gz
[ -d soxr-0.1.3 ] || tar xf soxr-0.1.3.tar.gz
(cd soxr-0.1.3 && run cmake /tmp/soxr.log cmake \
    -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER=$CC -DCMAKE_FIND_ROOT_PATH="$SYSROOT" \
    -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=OFF -DWITH_AVFFT=OFF \
    -DWITH_OPENMP=OFF \
    -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF . \
    && run make /tmp/soxr.log make -j"$JOBS" \
    && run install /tmp/soxr.log make install DESTDIR="$SYSROOT")
fi

log "libsodium 1.0.19"
if have libsodium.a; then echo "already built"; else
get https://github.com/jedisct1/libsodium/releases/download/1.0.19-RELEASE/libsodium-1.0.19.tar.gz libsodium-1.0.19.tar.gz
[ -d libsodium-stable ] || tar xf libsodium-1.0.19.tar.gz
(cd libsodium-stable && run configure /tmp/sodium.log ./configure $COMMON \
    && run make /tmp/sodium.log make -j"$JOBS" \
    && run install /tmp/sodium.log make install DESTDIR="$SYSROOT")
fi

log "libgpg-error 1.49"
if have libgpg-error.a; then echo "already built"; else
get https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.49.tar.bz2 libgpg-error-1.49.tar.bz2
[ -d libgpg-error-1.49 ] || tar xf libgpg-error-1.49.tar.bz2
(cd libgpg-error-1.49 && run configure /tmp/gpgerr.log ./configure $COMMON \
    && run make /tmp/gpgerr.log make -j"$JOBS" \
    && run install /tmp/gpgerr.log make install DESTDIR="$SYSROOT")
fi
# libgcrypt looks for gpg-error-config; 1.49 ships only gpgrt-config.
[ -x "$SYSROOT/usr/bin/gpgrt-config" ] && ln -sf gpgrt-config "$SYSROOT/usr/bin/gpg-error-config"

log "libgcrypt 1.10.3"
if have libgcrypt.a; then echo "already built"; else
get https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.10.3.tar.bz2 libgcrypt-1.10.3.tar.bz2
[ -d libgcrypt-1.10.3 ] || tar xf libgcrypt-1.10.3.tar.bz2
(cd libgcrypt-1.10.3 && run configure /tmp/gcrypt.log ./configure $COMMON \
    --with-libgpg-error-prefix="$SYSROOT/usr" \
    && run make /tmp/gcrypt.log make -j"$JOBS" \
    && run install /tmp/gcrypt.log make install DESTDIR="$SYSROOT")
fi

log "libplist 2.3.0"
if have libplist-2.0.a; then echo "already built"; else
get https://github.com/libimobiledevice/libplist/releases/download/2.3.0/libplist-2.3.0.tar.bz2 libplist-2.3.0.tar.bz2
[ -d libplist-2.3.0 ] || tar xf libplist-2.3.0.tar.bz2
(cd libplist-2.3.0 && run configure /tmp/plist.log ./configure $COMMON --without-cython \
    && run make /tmp/plist.log make -j"$JOBS" \
    && run install /tmp/plist.log make install DESTDIR="$SYSROOT")
fi

log "ffmpeg 7.1.3 (aac/alac only, static)"
if have libavcodec.a; then echo "already built"; else
get https://ffmpeg.org/releases/ffmpeg-7.1.3.tar.xz ffmpeg-7.1.3.tar.xz
[ -d ffmpeg-7.1.3 ] || tar xf ffmpeg-7.1.3.tar.xz
(cd ffmpeg-7.1.3 && run configure /tmp/ff.log ./configure --prefix=/usr \
    --enable-cross-compile --cross-prefix=aarch64-linux-gnu- --arch=aarch64 \
    --target-os=linux --disable-everything --disable-programs --disable-doc \
    --disable-network --disable-avdevice --disable-avfilter --disable-swscale \
    --disable-autodetect --disable-shared --enable-static \
    --enable-pic --enable-decoder=aac,alac --enable-parser=aac \
    --extra-cflags="-I$SYSROOT/usr/include" \
    --extra-ldflags="-L$SYSROOT/usr/lib" \
    && run make /tmp/ff.log make -j"$JOBS" \
    && run install /tmp/ff.log make install DESTDIR="$SYSROOT")
fi

log "nqptp 1.2.9"
get https://github.com/mikebrady/nqptp/archive/refs/tags/1.2.9.tar.gz nqptp-1.2.9.tar.gz
[ -d nqptp-1.2.9 ] || tar xf nqptp-1.2.9.tar.gz
(cd nqptp-1.2.9 && export ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes \
    && run autoreconf /tmp/nqptp.log autoreconf -fi \
    && run configure /tmp/nqptp.log ./configure $COMMON \
    && run make /tmp/nqptp.log make -j"$JOBS")
cp nqptp-1.2.9/nqptp "$OUT/nqptp"

log "shairport-sync 5.6.2 (AirPlay 2, PulseAudio, avahi, openssl)"
get https://github.com/mikebrady/shairport-sync/archive/refs/tags/5.6.2.tar.gz sps-5.6.2.tar.gz
[ -d shairport-sync-5.6.2 ] || tar xf sps-5.6.2.tar.gz
cd shairport-sync-5.6.2
sed -i 's/config.model = strdup("ShairportSync");/config.model = strdup("AudioAccessory5,1");/' shairport.c
grep -q 'config.model = strdup("AudioAccessory5,1");' shairport.c

# Local patch: the stock PulseAudio backend has no volume callback, so AirPlay
# volume only scaled the samples and the speaker's own knob stayed separate.
# Make the AirPlay volume drive the PulseAudio sink volume instead.
if ! grep -q 'airplay_volume_to_sink' audio_pa.c; then
    sed -i 's|#include <errno.h>|#include <errno.h>\n#include <math.h>|' audio_pa.c
    sed -i 's|^audio_output audio_pa = {|static void airplay_volume_to_sink(double vol);\n\naudio_output audio_pa = {|' audio_pa.c
    sed -i 's|\.volume = NULL,|.volume = airplay_volume_to_sink,|' audio_pa.c
    cat >> audio_pa.c <<'PATCH'

// Local patch (capsula-2019 package): the AirPlay volume sets the PulseAudio
// sink volume, so the phone slider and the speaker volume are one control.
static void airplay_volume_to_sink(double vol) {
  if (mainloop == NULL || context == NULL)
    return;
  double linear = pow(10.0, vol / 20.0);
  if (linear < 0.0)
    linear = 0.0;
  if (linear > 1.0)
    linear = 1.0;
  pa_threaded_mainloop_lock(mainloop);
  pa_cvolume cv;
  pa_cvolume_set(&cv, 2, pa_sw_volume_from_linear(linear));
  pa_operation *o = pa_context_set_sink_volume_by_name(
      context, config.pa_sink ? config.pa_sink : "@DEFAULT_SINK@", &cv, NULL, NULL);
  if (o)
    pa_operation_unref(o);
  pa_threaded_mainloop_unlock(mainloop);
}
PATCH
fi
[ -f configure ] || run autoreconf /tmp/sps.log autoreconf -fi
# libgcrypt is static here and needs libgpg-error symbols at link time.
export LIBS="-lgpg-error"
run configure /tmp/sps.log ./configure --host=aarch64-linux-gnu --prefix=/usr \
    --sysconfdir=/etc --with-piddir=/run \
    --with-pulseaudio --with-avahi --with-ssl=openssl --with-airplay-2 --with-soxr \
    --without-metadata --without-dbus
run make /tmp/sps.log make -j"$JOBS"
cp shairport-sync "$OUT/shairport-sync"
cd ..

$STRIP "$OUT/shairport-sync" "$OUT/nqptp"

log "report"
{
    echo "target: VK Capsula 2019 (RK3308, Buildroot 2022.11, glibc 2.33, aarch64)"
    echo "toolchain: $(aarch64-linux-gnu-gcc -dumpversion) / bullseye glibc 2.31"
    "$OUT/nqptp" -V 2>&1 || true
    echo "--- NEEDED ---"
    aarch64-linux-gnu-objdump -p "$OUT/shairport-sync" | grep NEEDED || true
    echo "--- max GLIBC symbol versions ---"
    aarch64-linux-gnu-readelf --version-info "$OUT/shairport-sync" \
        | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -4
    echo "--- sizes ---"
    ls -l "$OUT"
    sha256sum "$OUT/shairport-sync" "$OUT/nqptp"
} | tee "$OUT/BUILD_INFO.txt"

log "DONE"
