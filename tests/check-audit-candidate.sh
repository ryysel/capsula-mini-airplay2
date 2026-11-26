#!/bin/sh
# Host tests only; never invoke an installer against the host filesystem.
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for script in tests/test-*.py; do python3 "$script"; done
for source in tests/test-*.c; do
    cc -std=c11 -Wall -Wextra -Werror -fsanitize=undefined \
        -I packages/capsula-2019/src/receiver "$source" -lm -o "$tmp/test"
    "$tmp/test"
done
sh tests/test-timing-profile.sh
(cd packages/capsula-2019/src/capsula-ui && go test -race ./... && go vet ./...)
python3 build/build-model-packages.py "$tmp/models"
(cd "$tmp/models" && sha256sum -c SHA256SUMS.models)
