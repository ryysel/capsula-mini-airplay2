#!/bin/sh
# Host-only config migration regression tests. No hardware or services touched.
set -eu
root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for pkg in capsula-2019 mini-a113x; do
    helper=$root/packages/$pkg/etc/apply-timing-profile.sh
    cp "$root/packages/$pkg/etc/shairport-sync.conf" "$tmp/config"
    sh "$helper" "$tmp/config" fast_audio
    grep -q 'audio_backend_latency_offset_in_seconds = -1.7;' "$tmp/config"
    grep -q 'audio_backend_buffer_desired_length_in_seconds = 0.10;' "$tmp/config"
    test "$(grep -c '^[[:space:]]*audio_backend_latency_offset_in_seconds' "$tmp/config")" = 1
    if [ "$pkg" = capsula-2019 ]; then
        test "$(grep -c '^[[:space:]]*volume_control_profile' "$tmp/config")" = 1
        grep -q 'volume_control_profile = "flat";' "$tmp/config"
    fi
    cp "$tmp/config" "$tmp/once"
    sh "$helper" "$tmp/config" fast_audio
    cmp "$tmp/config" "$tmp/once"
    sh "$helper" "$tmp/config" synchronized
    grep -q 'audio_backend_latency_offset_in_seconds = 0.0;' "$tmp/config"
    grep -q 'audio_backend_buffer_desired_length_in_seconds = 0.20;' "$tmp/config"
    cp "$tmp/config" "$tmp/once"
    if sh "$helper" "$tmp/config" invalid; then exit 1; fi
    cmp "$tmp/config" "$tmp/once"
    printf 'general = { name = "custom"; };\n' > "$tmp/custom"
    cp "$tmp/custom" "$tmp/original"
    if sh "$helper" "$tmp/custom" fast_audio; then exit 1; fi
    cmp "$tmp/custom" "$tmp/original"
done
echo TIMING_PROFILE_TESTS_PASS
