# Receiver source overlay

Modified Shairport Sync 5.6.2 source files (upstream MIT licence retained).
Build with the existing Buildroot/sysroot builder (Debian bullseye gcc-10).
Overlay these files AFTER the dependency/configuration steps of
`build/build-2019.sh`, then compile them. `build-2019.sh` appends
`remote/remote.c` and `capsula-media-control.c` to `shairport_sync_SOURCES`.

The complete changed files are supplied rather than a patch against an
unrecorded intermediate binary. `CAPSULA_PA_SELFTEST=1 shairport-sync -c CONF`
exercises the real backend with silence for 3 seconds and exits. A pass needs
over 2 seconds of PCM consumption and an uncorked stream; it does not prove
AirPlay negotiation or acoustic synchronization.

Normal startup creates the control endpoint; the backend uses a startup
threshold below the player's queue budget, ignores phantom server latency
while corked, and publishes an RMS/peak envelope in tmpfs. Both models use
native stereoctl volume; config MUST specify volume_control_profile="flat".

## Stock build notes (2026-11-14)

- Configure with `--with-metadata`; verify `CONFIG_METADATA`,
  `CONFIG_METADATA_HUB` and `CONFIG_METADATA_PIPE` in `config.h` before
  building, otherwise cover art is never written and the ring has no palette.
- `make` picks up `remote/remote.c` and `capsula-media-control.c` from
  `Makefile.am`; do not link those objects by hand.
- The PulseAudio backend pumps freshly decoded PCM into the stream as soon as
  the server has room, uses a 5 ms `minreq`, and keeps the startup threshold
  below the player queue budget.
- Both stock models run the fast profile: buffer 0.15 s, latency offset -1.7 s,
  `volume_control_profile = "flat"`.
- `CAPSULA_PA_SELFTEST=1` deinitialises the backend once and exits before the
  normal atexit path: metadata/RTSP threads are not started on that path.
