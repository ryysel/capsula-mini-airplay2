#!/bin/sh
# Rebuild the helper daemons and the bundle for VK Capsula Mini stock
# (Buildroot 2022.11.1, glibc 2.33, Amlogic A113X).
#
# Run on a Linux x86_64 host with the aarch64 cross toolchain
# (Debian/Ubuntu: apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu).
# The receiver binaries come from the build workspaces; this script does not
# rebuild shairport-sync or nqptp, it only documents and repacks them.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
pkg=$root/packages/mini-stock
cc=${CROSS_CC:-aarch64-linux-gnu-gcc}
strip=${CROSS_STRIP:-aarch64-linux-gnu-strip}

echo "== helper daemons (static, glibc 2.33 compatible) =="
for name in capsula-airplay-keys capsula-airplay-ring; do
    "$cc" -static -O2 -o "/tmp/$name" "$pkg/src/$name.c" -lm
    "$strip" "/tmp/$name"
    cp "/tmp/$name" "$pkg/bin/$name"
    chmod 0755 "$pkg/bin/$name"
    echo "built $name"
done

echo "== receiver binaries =="
for name in shairport-sync nqptp libuuid.so.1.3.0 capsula-art; do
    if [ ! -f "$pkg/bin/$name" ]; then
        echo "missing $pkg/bin/$name" >&2
        echo "copy it from the build workspace; see docs/MINI_STOCK.md" >&2
        exit 1
    fi
    echo "using existing $name"
done

echo "== checksums =="
cd "$pkg"
find . -type f ! -name SHA256SUMS | sort | xargs sha256sum > SHA256SUMS
cat SHA256SUMS

echo "== done: $pkg =="
