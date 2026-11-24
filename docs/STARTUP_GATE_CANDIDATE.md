# Experimental 2019 fast-audio startup gate

This experimental receiver is included only in the v1.6.0-rc.1 prerelease.
Startup drop-late/underflow events remain on repeated connections: this is
not a qualified stable fix. It re-selects the
initial queued packet after the PA/FFmpeg output preparation, before sending
silence or real audio. The original stale-packet selection then uses a lead
bounded by the player's budget and the existing PA 100 ms target buffer.

Only AP2 + PulseAudio + negative-offset cold startup is gated. Classic,
synchronized mode and already-primed resync follow the prior path. Format
changes invalidate preparation; startup re-selection does not rerun the heavy
setup for every discarded packet. Steady-state offset, backend buffering,
resync thresholds, volume and metadata are unchanged.

`player.c` is the upstream 5.6.2 source plus this gate, carrying upstream's
license header. `build/build-2019.sh` restores upstream player.c from the
versioned source tarball on each invocation and applies this overlay only for
capsula-2019. This avoids leaking a Big-only candidate into a later Mini build.

Host check:

```sh
gcc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    tests/test-capsula-startup-gate.c -lm -o test-startup-gate
./test-startup-gate
```

The test replays the recorded -144.527 ms lead and 352-frame/44.1 kHz packet
cadence. It validates selection policy and state/bounds, not full RTP-thread
behaviour or physical sound. Live validation is still required.
