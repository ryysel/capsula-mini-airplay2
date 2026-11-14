# Capsula stock fixes candidate ??? 2026-11-14

## Implemented and deployed

- Both models keep offset **-1.7 s**, desired backend buffer **0.10 s**.
- Fixed PA startup: a fixed 250 ms uncork threshold conflicted with the
  player's 100/200 ms queue budget. Threshold is now min(20 ms, half budget),
  and delay() ignores phantom server latency while corked.
- Mini native volume: exact-hash 8-byte guard patch for stock 44.90, activated
  by one owner-approved reboot. Stock `/rom` binary is unchanged.
- Both models forward phone volume to stereoctl and native voice-agent.
  `volume_control_profile="flat"` removes Shairport's extra taper; percent
  and dB round-trip tests cover all 101 integer percentages. Native buttons
  update idle advertised volume and the receiver's saved session volume as well as notifying the phone.
- Unified Go renderer: same palette extraction, JPEG/PNG/TIFF, 300 ms fade,
  RGB channel mapping on Mini and single LED broker on 2019.
- Brightness follows real outgoing PCM RMS/peak, with fast attack and smooth
  release; stale samples decay on pause. It is not a timer pretending to beat.
- Mini drains its metadata FIFO; no second C ring daemon competes for LEDs.
  Native numeric volume display remains owned by voice-agent.
- 2019 UI and LED broker are now included in its persistent boot hook.

## Instrumentally checked

- Exact final binaries passed the real PA-backend selftest on both devices:
  approximately 1 MB consumed over 3 s; corked=0. No crash on diagnostic exit.
- Mini native requests 30 -> 45 -> 35 changed master-sink gain after patch;
  2019 did the same. No direct sink-volume workaround is used now.
- Mini boot after the approved patch: root, native voice-agent hash, avahi,
  nqptp, shairport, keys and renderer checked. Final renderer additions were
  subsequently installed without another reboot.
- Shared renderer race tests: palette/primary channels/gradient/envelope PASS.
- Hardware/glibc requirements inspected: receiver requires no newer than
  GLIBC_2.29 (target is 2.33).

## Still requires the owner

These checks do NOT establish end-to-end AirPlay music, acoustic alignment
with Alice, perceived beat alignment, actual colour order, or phone/button
round-trip UX. Re-test both speakers with real tracks. No new final release
tag should be published on the basis of backend tests alone.

## Retractions

Earlier claims that -1.7 was physically impossible, that 98% of frames were
dropped, and that Audio-Latency=15000 fixed the problem were unproven or wrong.
The 2816-byte debug line was a first packet, not a steady-state rate.
The experimental Audio-Latency change is removed.

## Rollback

Receiver/UI pre-change binaries are retained on RAID in the
capsula-finish-20261114 workspace, outside git. Mini vendor binary is NEVER
redistributed: uninstall restores stock bytes from /rom, then requires a
manual reboot. Merely unlinking S50 through overlayfs would create a
whiteout; uninstall now copies the original script instead.

Final candidate hashes and real backend test:

- mini: `104b48f1dbbcd14fc96d232a5a9553bd51fe9b04f798de3130f43db4072a9718`; `CAPSULA_BACKEND_TEST submitted=1064448 consumed=1061632 queued=2816 corked=0`.
- big: `a0957a666482fbc5fe06b835fcf8ae34834dd23d798fc3a96de7784ed0a5ae2c`; `CAPSULA_BACKEND_TEST submitted=1002496 consumed=999680 queued=2816 corked=0`.
