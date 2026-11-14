#!/bin/sh
# Helper/UI rebuild; receiver source overlay is documented alongside its source.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
pkg=$root/packages/mini-stock
cc=${CROSS_CC:-aarch64-linux-gnu-gcc}
strip=${CROSS_STRIP:-aarch64-linux-gnu-strip}
"$cc" -static -O2 -o "$pkg/bin/capsula-airplay-keys.new" "$pkg/src/capsula-airplay-keys.c"
"$strip" "$pkg/bin/capsula-airplay-keys.new"
mv "$pkg/bin/capsula-airplay-keys.new" "$pkg/bin/capsula-airplay-keys"
cd "$root/packages/capsula-2019/src/capsula-ui"
go test ./...
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -buildvcs=false -trimpath -o "$pkg/bin/capsula-ui" .
echo 'Receiver: see packages/mini-stock/src/receiver/README.md'
