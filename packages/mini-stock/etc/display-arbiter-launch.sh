# capsula:display-arbiter -- stock Mini only; an early failure fails closed.
capsula_display_base=/data/local/capsula-airplay
capsula_display_lib=$capsula_display_base/bin/libcapsula-display-arbiter.so
capsula_display_pending=$capsula_display_base/etc/mini-display-arbiter.pending
if [ -f "$capsula_display_base/etc/mini-display-arbiter.enabled" ] &&
   [ ! -e "$capsula_display_pending" ] && [ -r "$capsula_display_lib" ]; then
    : > "$capsula_display_pending"
    CAPSULA_DISPLAY_ARBITER=1 LD_PRELOAD="$capsula_display_lib${LD_PRELOAD:+:$LD_PRELOAD}" voice-agent "$@" &
else
    voice-agent "$@" &
fi
