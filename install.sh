#!/bin/sh
# Select a firmware-specific package; every installer option is forwarded.
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
action=${CAPSULA_ACTION:-install}

# Capsula Mini running Alpine 3.24/aarch64.
if [ -f /etc/alpine-release ] && [ "$(uname -m)" = aarch64 ]; then
    exec sh "$root/packages/mini-a113x/$action.sh" "$@"
fi

if grep -q '^ID=buildroot' /etc/os-release 2>/dev/null; then
    compat=$(tr '\000' '\n' < /proc/device-tree/compatible 2>/dev/null || true)
    # Capsula 2019: RK3308.
    if printf '%s\n' "$compat" | grep -qi rk3308; then
        exec sh "$root/packages/capsula-2019/$action.sh" "$@"
    fi
    # Capsula Mini with the stock Buildroot OS: Amlogic A113X/AXG.
    if printf '%s\n' "$compat" | grep -qi amlogic &&
        printf '%s\n' "$compat" | grep -qi axg; then
        exec sh "$root/packages/mini-stock/$action.sh" "$@"
    fi
fi

echo 'Unsupported firmware. Supported: Capsula 2019 (Buildroot/RK3308), Capsula Mini Alpine 3.24/aarch64, Capsula Mini stock Buildroot/A113X.' >&2
exit 1
