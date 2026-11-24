# Mini stock renderer

`capsula-ui` is built from `packages/capsula-2019/src/capsula-ui` for BOTH
stock models. On Mini it detects `/dev/topleds`, renders the 12 RGB pixels via
ioctl, and supports an optional native-arbitrated music VU on the numeric display.
The VU client never writes numeric-display sysfs directly. On 2019 it writes frames
to the single LED broker. The old C ring source is historical, not installed.
Both renderers use the same tested palette and a PCM RMS/peak envelope.
Native numeric volume display is provided by the exact-hash voice-agent guard
patch, not a competing clock writer. One reboot is needed after first install.

## Receiver flags

`build/build-2019.sh` already passes `--with-metadata`. Confirm the three
`CONFIG_METADATA*` defines in `config.h` after `configure`; a tree configured
earlier with `--without-metadata` silently disables the cover cache. The fast
profile is buffer 0.15 s with latency offset -1.7 s.

## Native display arbitration (rc.3)

Build on a PC using `sh build/build-mini-display-arbiter.sh` from repository
root with an aarch64-linux-gnu GCC toolchain (tested GCC-10; GLIBC_2.17).
Source/test protocol: `src/display-arbiter/`. The installed adapter is the
exact revision-2 binary accepted by the owner after flashlight testing.
The original boolean-intensity prototype is not shipped.
For host tests compile `test_display_arbiter.c` with gcc, -pthread,
-fsanitize=address,undefined and test-only CDA_SOCKET/CDA_STATUS paths.

Enable via stock-Mini installer --display-vu; first activation needs one
manual reboot. Never stop/restart voice-agent. Unknown firmware/wrappers
are rejected before update. Missing adapter leaves the native clock.
See docs/RELEASE_1_6_0_RC3.md for disabling and acceptance limits.
