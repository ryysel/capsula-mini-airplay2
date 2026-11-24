# Experimental stock Mini display VU

Opt-in only for this boot: create `/tmp/capsula-mini-display-vu`.
Remove the marker to disable for the current run. This is NOT enabled by
the public installer. On the owner's Mini, a local persistent opt-in
`etc/mini-display-vu.enabled` and the existing data-local S99airplay hook
recreate the marker before UI startup (approved permanent deployment).
The four seven-segment cells show five height steps, driven by four
delayed (0/100/200/300 ms) PCM-envelope values. This is a level animation,
NOT four independent frequency bands. No raw audio is captured.

Only stock Mini is addressed. Big, receiver, audio settings, ring
calibration, vendor binaries and account settings are unchanged.
Clock frames are restored on stop/pause/stale PCM and normal exit.
Volume/speech markers suppress display writes; no clock is restored on
top of native animations. Existing stock brightness/PWM settings are
not changed. A preflight compares all 30 segment states with the current
stock clock before opening write handles. Rendering runs on the existing 25 Hz UI tick. Interpolated level history,
45 ms attack / 320 ms release and hysteresis suppress abrupt transitions
and threshold chatter. A power curve expands movement on loud mastered
tracks instead of keeping every cell full. No synthetic oscillator or
random beat is used; seven-segment geometry still limits visible height.

## Validation limits

Mapping is checked against a read-only stock 22:23 observation.
Pure mapping/level/history tests run on host; this does NOT establish
physical flicker-free operation. Stock voice-agent still owns the clock:
its periodic updates may compete with custom rendering. No vendor
patch/restart, clock setting changes or reboot are allowed as a shortcut.
The owner confirmed the first bounded test moved with music and restored
the clock, but requested smoother/more interesting motion. The revised
wave candidate also completed a 40-second bounded test; the owner accepted it for permanent local installation.
The exact tested binary was installed on Mini only. Receiver/audio settings
and calibration stayed unchanged. Startup wiring was checked without reboot;
cold boot and the full speech/volume-priority tour remain untested. Do not publish a release without separate permission.
