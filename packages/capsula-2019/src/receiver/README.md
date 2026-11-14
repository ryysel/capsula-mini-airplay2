# Receiver source overlay

Modified Shairport Sync 5.6.2 source files (upstream MIT licence retained).
Build with the existing Buildroot/sysroot builder (Debian bullseye gcc-10).
Overlay these files AFTER the dependency/configuration steps of
`build/build-2019.sh`, then compile them. Link `remote/remote.o` and
`capsula-media-control.o` explicitly; both are required.

The complete changed files are supplied rather than a patch against an
unrecorded intermediate binary. `CAPSULA_PA_SELFTEST=1 shairport-sync -c CONF`
exercises the real backend with silence for 3 seconds and exits. A pass needs
over 2 seconds of PCM consumption and an uncorked stream; it does not prove
AirPlay negotiation or acoustic synchronization.

Normal startup creates the control endpoint; the backend uses a startup
threshold below the player's queue budget, ignores phantom server latency
while corked, and publishes an RMS/peak envelope in tmpfs. Both models use
native stereoctl volume; config MUST specify volume_control_profile="flat".
