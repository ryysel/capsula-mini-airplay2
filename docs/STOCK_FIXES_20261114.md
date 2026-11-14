# Capsula stock fixes — released in v1.5.1 (2026-11-14)

## Released behaviour

- Both stock models use offset **-1.7 s** with a **0.15 s** backend buffer.
  The earlier 0.10 s budget caused PulseAudio underflow on the stock graph.
- PA startup: the uncork threshold is min(20 ms, half the player budget) and
  delay() ignores phantom server latency while corked.
- Newly decoded PCM immediately satisfies an outstanding writable request
  instead of waiting for the next server callback; `minreq` is 5 ms.
- Mini native volume: exact-hash 8-byte guard patch for stock 44.90, activated
  by one owner-approved reboot. Stock `/rom` binary is unchanged.
- Both models forward phone volume to stereoctl and native voice-agent.
  `volume_control_profile="flat"` removes Shairport's extra taper; percent
  and dB round-trip tests cover all 101 integer percentages. Native buttons
  update idle advertised volume and the receiver's saved session volume as
  well as notifying the phone.
- Unified Go renderer: same palette extraction, JPEG/PNG/TIFF, 300 ms fade,
  RGB channel mapping on Mini and a single LED broker on 2019.
- Brightness follows real outgoing PCM RMS/peak, with fast attack and smooth
  release; stale samples decay on pause. It is not a timer pretending to beat.
- Mini drains its metadata FIFO; the renderer is the only reader. Native
  numeric volume display remains owned by voice-agent.
- 2019 UI and LED broker are in its persistent boot hook. Both journal readers
  now follow `logread -f` instead of rescanning the whole buffer.

## Instrumentally checked

- Controlled 440 Hz tone through the real backend, captured from
  `master.monitor`, gaps measured inside the tone:
  - Mini, after the pump fix, 0.15: 0 gaps >= 1 ms.
  - 2019, 0.10: 9–20 PA underflows per run and gaps up to 244 ms.
  - 2019, 0.15 and 0.25: four consecutive runs with 0 underflows and
    0 gaps >= 1 ms inside the tone.
  - Caveat: the early 2019 runs had the old polling UI and/or stock clock
    running, so the buffer comparison is not fully isolated.
- Final binaries passed the PA selftest on both devices: about 1 MB consumed
  over 3 s, corked=0.
- Mini native requests 30 -> 45 -> 35 changed master-sink gain after patch;
  2019 did the same. No direct sink-volume workaround is used now.
- Shared renderer race tests: palette/primary channels/gradient/envelope PASS.
- Hardware/glibc requirements inspected: receiver requires no newer than
  GLIBC_2.29 (target is 2.33).

## Owner live checks

- Both stock capsules play music through AirPlay with the new backend.
- Mini: cover colours, PCM pulsation and phone/button volume confirmed.
- 2019: owner confirmed playback after the same backend was ported.

Not established: acoustic alignment with Alice at -1.7, cold boot for either
capsule after the final changes, and the cause of the earlier spontaneous
Mini reboot. The Mini boot hook is restored to start the renderer again, but
a cold boot with it has not been repeated.

## Retractions

Earlier claims that -1.7 was physically impossible, that 98% of frames were
dropped, and that Audio-Latency=15000 fixed the problem were unproven or wrong.
The 2816-byte debug line was a first packet, not a steady-state rate.
The experimental Audio-Latency change is removed. The earlier statement that
0.10 s was a sufficient fast profile was wrong on the stock PulseAudio graph.

## Rollback

Receiver/UI pre-change binaries are retained on RAID in the
capsula-finish-20261114 workspace, outside git, and the previous config is
kept on each device as `shairport-sync.conf.before-015`. Mini vendor binary is
NEVER redistributed: uninstall restores stock bytes from /rom, then requires a
manual reboot. Merely unlinking S50 through overlayfs would create a
whiteout; uninstall now copies the original script instead.

Final released hashes:

- mini-stock shairport-sync: `e6192ac6073f8b5055673c5f603a3f6456a57373450a31520dc5a33c16265e2c`
- capsula-2019 shairport-sync: `35476866f03da0f9dcd2ca3fcb6151e38996d6b95ae9c1e4ab9ce5bb73542605`
- shared capsula-ui: `c8d73d7b7884d182ae7141dd7bb429e7564fd29f90cbb72eb455499ac8c0ecc0`
- capsula-led-media: `e1dd9b165138d8ae59f050c6b6abe98e075107b39dc7929021e29b06f1996df8`
