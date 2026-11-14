#!/bin/sh
# Config-only migration, shared by Alpine and the restricted Buildroot shell.
# Preserve name, volume and metadata. Refuse an unrecognised general block.
set -eu
conf=${1:?configuration path required}
mode=${2:-fast_audio}
case "$mode" in
    fast_audio) offset=-1.7; buffer=0.10 ;;
    synchronized) offset=0.0; buffer=0.20 ;;
    *) echo 'timing must be fast_audio or synchronized' >&2; exit 2 ;;
esac
[ -f "$conf" ] && [ ! -L "$conf" ] || { echo 'Expected a regular config file' >&2; exit 1; }
tmp=$conf.timing.$$
trap 'rm -f "$tmp"' EXIT
inside=0
found=0
closed=0
while IFS= read -r line || [ -n "$line" ]; do
    trimmed=${line#"${line%%[! 	]*}"}
    case "$trimmed" in
        'general = {'|'general={'|'general ={'|'general= {')
            [ "$found" = 0 ] || { echo 'Duplicate general block' >&2; exit 1; }
            inside=1; found=1 ;;
    esac
    if [ "$inside" = 1 ]; then
        case "$trimmed" in
            audio_backend_buffer_desired_length_in_seconds*|audio_backend_latency_offset_in_seconds*|resync_threshold_in_seconds*|drift_tolerance_in_seconds*) continue ;;
            '};'*)
                printf '\taudio_backend_buffer_desired_length_in_seconds = %s;\n' "$buffer"
                printf '\taudio_backend_latency_offset_in_seconds = %s;\n' "$offset"
                printf '\tresync_threshold_in_seconds = 0.050;\n'
                printf '\tdrift_tolerance_in_seconds = 0.002;\n'
                inside=0; closed=1 ;;
        esac
    fi
    printf '%s\n' "$line"
done < "$conf" > "$tmp"
[ "$found" = 1 ] && [ "$closed" = 1 ] && [ "$inside" = 0 ] || {
    echo 'Expected one multiline general block; original config unchanged' >&2; exit 1;
}
chmod 0644 "$tmp"
mv "$tmp" "$conf"
echo "timing_mode=$mode offset=$offset backend_buffer=$buffer"
