#!/bin/sh
# Select a firmware-specific package; all Mini installer options are forwarded.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
action=${CAPSULA_ACTION:-install}
if [ -f /etc/alpine-release ] && [ "$(uname -m)" = aarch64 ]; then
    exec sh "$root/packages/mini-a113x/$action.sh" "$@"
fi
if grep -q '^ID=buildroot' /etc/os-release 2>/dev/null &&
    tr '\000' '\n' < /proc/device-tree/compatible | grep -qi rk3308; then
    exec sh "$root/packages/capsula-2019/$action.sh" "$@"
fi
echo 'Unsupported firmware. Requires Capsula 2019 Buildroot/RK3308 or Capsula Mini Alpine 3.24/aarch64.' >&2
exit 1
