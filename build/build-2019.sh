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
# HomePod (1,1) is the tall speaker icon; 5,1 is the small round HomePod mini.
# The source tree may already carry a model from an earlier build, so replace
# whatever is there instead of only the upstream default.
sed -i 's/config.model = strdup("[^"]*");/config.model = strdup("AudioAccessory1,1");/' shairport.c
grep -q 'config.model = strdup("AudioAccessory1,1");' shairport.c

# Local patch: on the VK Capsula 2019 the speaker volume is Marusya's own
# value (voice-agent: a 0..100 integer that drives the PulseAudio `master`
# sink, the LED indicator, the saved settings and the VK cloud state). Writing
# the sink directly only creates a second, independent gain. So the AirPlay
# volume is forwarded to stereoctl as OnSetVolumeRequest and applied natively.
if ! grep -q 'capsula_airplay_volume' audio_pa.c; then
    sed -i 's|#include <errno.h>|#include <errno.h>\n#include <math.h>\n#include <sys/socket.h>\n#include <sys/un.h>\n#include "rtsp.h"\n#include "ap2_event_receiver.h"\n#include "utilities/structured_buffer.h"\n#include <plist/plist.h>|' audio_pa.c
    sed -i 's|^audio_output audio_pa = {|static void capsula_airplay_volume(double vol);\nstatic output_parameters_t *capsula_volume_parameters(void);\n\naudio_output audio_pa = {|' audio_pa.c
    sed -i 's|\.volume = NULL,|.volume = capsula_airplay_volume,|' audio_pa.c
    sed -i 's|\.parameters = NULL,|.parameters = capsula_volume_parameters,|' audio_pa.c
    cat >> audio_pa.c <<'PATCH'

// ---- capsula-2019 volume bridge -------------------------------------------
// The speaker volume is voice-agent's own 0..100 value: it drives the
// PulseAudio `master` sink, the LED ring, the saved settings and the cloud
// state. Shairport therefore never touches the sink. It forwards the AirPlay
// volume to stereoctl as OnSetVolumeRequest (uint16 LE type + msgpack over a
// SOCK_SEQPACKET socket) and voice-agent applies it natively. The same socket
// is watched so that a change made with the speaker's buttons is reported back
// to the AirPlay sender.
static int capsula_vol_sock = -1;
static int capsula_last_sent = -1;
static int capsula_last_notified = -1;

static int capsula_vol_connect(void) {
  int fd = socket(AF_UNIX, SOCK_SEQPACKET, 0);
  if (fd < 0)
    return -1;
  struct sockaddr_un sa;
  memset(&sa, 0, sizeof(sa));
  sa.sun_family = AF_UNIX;
  strncpy(sa.sun_path, "/tmp/stereoctl.sock", sizeof(sa.sun_path) - 1);
  if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
    close(fd);
    return -1;
  }
  return fd;
}

static void capsula_marusya_set_volume(int v) {
  // Type 7 is OnSetVolumeRequest; a msgpack positive fixint is one byte.
  unsigned char frame[3] = {0x07, 0x00, 0x00};
  if (v < 0)
    v = 0;
  if (v > 100)
    v = 100;
  frame[2] = (unsigned char)v;
  if (capsula_vol_sock < 0)
    capsula_vol_sock = capsula_vol_connect();
  if (capsula_vol_sock < 0)
    return;
  if (send(capsula_vol_sock, frame, sizeof(frame), 0) != (ssize_t)sizeof(frame)) {
    close(capsula_vol_sock);
    capsula_vol_sock = -1;
    return;
  }
  capsula_last_sent = v;
}

// Mirrors ap2_event_send_unit_volume_notification() from remote/remote.c,
// which is not compiled in this build (no metadata support).
static ssize_t capsula_send_unit_volume(rtsp_conn_info *conn, double volume) {
  ssize_t result = -1;
  if ((volume >= 0.0) && (volume <= 1.0)) {
    structured_buffer *sbuf = sbuf_new(4096);
    if (sbuf != NULL) {
      pthread_cleanup_push(sbuf_cleanup, sbuf);
      plist_t params_plist = plist_new_dict();
      plist_dict_set_item(params_plist, "volume", plist_new_real(volume));
      plist_t request_plist = plist_new_dict();
      plist_dict_set_item(request_plist, "value", plist_new_string("dvlc"));
      plist_dict_set_item(request_plist, "volume", plist_new_real(volume));
      plist_dict_set_item(request_plist, "type", plist_new_string("sendMediaRemoteCommand"));
      plist_dict_set_item(request_plist, "params", params_plist);
      char *plistString = NULL;
      uint32_t plistStringLength = 0;
      plist_to_bin(request_plist, &plistString, &plistStringLength);
      if (plistString != NULL) {
        sbuf_printf(sbuf, "POST /command RTSP/1.0\r\nContent-Length: %u\r\n",
                    plistStringLength);
        sbuf_printf(sbuf, "Content-Type: application/x-apple-binary-plist\r\n\r\n");
        sbuf_append(sbuf, plistString, plistStringLength);
        free(plistString);
        char *b = 0;
        size_t l = 0;
        sbuf_buf_and_length(sbuf, &b, &l);
        result = ap2_event_port_send_message(conn, b, l);
        sbuf_clear(sbuf);
      }
      plist_free(request_plist);
      pthread_cleanup_pop(1);
    }
  }
  return result;
}

static void capsula_vol_reader_handle(int v) {
  if ((v < 0) || (v > 100))
    return;
  if ((v == capsula_last_sent) || (v == capsula_last_notified))
    return; // our own echo, or an already reported value
  capsula_last_notified = v;
  capsula_last_sent = v;
  double unit = (double)v / 100.0;
  pthread_rwlock_rdlock(&principal_conn_lock);
  rtsp_conn_info *conn = principal_conn;
  if ((conn != NULL) && (conn->airplay_type == ap_2)) {
    debug(2, "capsula volume: speaker %d -> sender unit volume %.3f", v, unit);
    capsula_send_unit_volume(conn, unit);
  }
  pthread_rwlock_unlock(&principal_conn_lock);
}

static void *capsula_vol_reader(__attribute__((unused)) void *arg) {
  for (;;) {
    int fd = capsula_vol_connect();
    if (fd < 0) {
      sleep(1);
      continue;
    }
    for (;;) {
      unsigned char buf[256];
      ssize_t n = recv(fd, buf, sizeof(buf), 0);
      if (n <= 0)
        break;
      // broadcast frame: uint16 type 9, msgpack array [volume, remote]
      if ((n >= 4) && (buf[0] == 0x09) && (buf[1] == 0x00) && (buf[2] == 0x92)) {
        if (buf[3] <= 0x7f)
          capsula_vol_reader_handle((int)buf[3]);
        else if (buf[3] >= 0xe0)
          capsula_vol_reader_handle((int)buf[3] - 256);
      }
    }
    close(fd);
    sleep(1);
  }
  return NULL;
}

__attribute__((constructor)) static void capsula_vol_reader_start(void) {
  pthread_t thread;
  if (pthread_create(&thread, NULL, capsula_vol_reader, NULL) == 0)
    pthread_detach(thread);
}

static output_parameters_t *capsula_volume_parameters(void) {
  static volume_range_t range = {-3000, 0};
  static output_parameters_t parameters = {&range};
  return &parameters;
}

static void capsula_airplay_volume(double vol) {
  // 'vol' is the attenuation in centi-dB, 0 being the maximum. The senders
  // map their slider position u to dB with 30*log10(u), so invert that: the
  // speaker then shows the same percentage as the phone.
  double db = vol / 100.0;
  int v = (int)lround(100.0 * pow(10.0, db / 30.0));
  if (v < 0)
    v = 0;
  if (v > 100)
    v = 100;
  debug(2, "capsula volume: sender %.2f dB -> speaker %d", db, v);
  capsula_marusya_set_volume(v);
}
PATCH
fi
# Local-only media endpoint, using the upstream AP2 transport implementation.
cp /work/build/capsula-media-control.c capsula-media-control.c
if ! grep -q capsula-media-control.c Makefile.am; then
    printf '\nshairport_sync_SOURCES += remote/remote.c capsula-media-control.c\n' >> Makefile.am
fi
if ! grep -q 'capsula_media_control_start();' audio_pa.c; then
    sed -i '/static int init(__attribute__((unused))/a\  extern void capsula_media_control_start(void);\n  capsula_media_control_start();' audio_pa.c
fi
run autoreconf /tmp/sps.log autoreconf -fi
# libgcrypt is static here and needs libgpg-error symbols at link time.
export LIBS="-lgpg-error"
run configure /tmp/sps.log ./configure --host=aarch64-linux-gnu --prefix=/usr \
    --sysconfdir=/etc --with-piddir=/run \
    --with-pulseaudio --with-avahi --with-ssl=openssl --with-airplay-2 --with-soxr \
    --with-metadata --without-dbus
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
