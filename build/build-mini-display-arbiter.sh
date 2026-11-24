#!/bin/sh
# Cross-build the stock-Mini-only native display adapter on a PC.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${1:-$ROOT/packages/mini-stock/bin/libcapsula-display-arbiter.so}
case "$OUT" in /*) ;; *) OUT=$PWD/$OUT ;; esac
CC=${CC:-aarch64-linux-gnu-gcc}
cd "$ROOT/packages/mini-stock/src/display-arbiter"
"$CC" -std=c11 -Wall -Wextra -Werror -O2 -fPIC -shared \
    -Wl,-z,relro,-z,now -Wl,-soname,libcapsula-display-arbiter.so \
    -pthread display_arbiter.c -o "$OUT"
