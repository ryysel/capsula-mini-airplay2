#!/bin/sh
# AirPlay 2 receiver installer for VK Capsula speakers.
#
# Picks the package that matches this speaker and hands over to it:
#   capsula-2019  - VK Капсула 2019 (RK3308, Buildroot, glibc, PulseAudio)
#   mini-a113x    - VK Капсула Мини (Amlogic A113X, Alpine Linux)
#
# Usage: sh install.sh ["AirPlay name"]
set -eu

root=$(cd "$(dirname "$0")" && pwd)
name=${1:-}

detect() {
    if [ -f /etc/alpine-release ]; then
        case "$(uname -m)" in
            aarch64) echo mini-a113x; return 0 ;;
        esac
        return 1
    fi
    if [ -f /etc/os-release ] && grep -q '^ID=buildroot' /etc/os-release 2>/dev/null; then
        model="/proc/device-tree/compatible"
        [ -r "$model" ] || model="/sys/firmware/devicetree/base/compatible"
        if tr '\0' '\n' < "$model" 2>/dev/null | grep -qi 'rk3308'; then
            echo capsula-2019
            return 0
        fi
    fi
    return 1
}

device=$(detect) || {
    echo "This speaker is not supported by this package." >&2
    echo "Supported: VK Capsula 2019 (RK3308/Buildroot), VK Capsula Mini (A113X/Alpine)." >&2
    exit 1
}

pkg="$root/packages/$device"
[ -f "$pkg/install.sh" ] || { echo "Package for $device is missing: $pkg" >&2; exit 1; }

echo "Detected speaker: $device"
if [ -n "$name" ]; then
    exec sh "$pkg/install.sh" "$name"
fi
exec sh "$pkg/install.sh"
