# Stock Mini native display arbiter (local candidate)

Fixes the architectural race between direct sysfs VU rendering and stock
clock redraws triggered by automatic brightness changes.

The UI no longer opens clock sysfs files: it publishes 40-byte versioned
Unix datagrams to a root-only socket, with a 400 ms lease. Missing arbiter,
stale sender, disabled VU and pause all fail back to native display.
There is deliberately no direct-write fallback.

A stock-Mini-only preload adapter serializes native display ioctl calls
and a 25 Hz leased-frame worker. It preserves every native brightness/
control byte, substitutes only the 30 segment-enable bytes during VU,
and caches the latest actual native frame for expiry/restore.
Other requests/devices/processes pass through. No audio APIs are hooked.
The exact firmware/packed-overlay hashes are checked by the local deployer.

Exact current HH:MM frames (including optional blank leading zero) are
clock redraws; other native frames immediately receive 1.8 s priority,
in addition to existing speech/volume hints in the UI. Clock classification,
ambient-light transitions and complete native-priority behaviour require
live acceptance; they must not be inferred from host mocks.

The startup wrapper loads the adapter only for the overlay voice-agent,
not globally. An early-launch pending flag causes preload to be bypassed
on the next launch until checked. The existing clean stock startup fallback
is preserved. Do not stop/re-exec voice-agent on the running speaker.

Checks: ASan/UBSan mock driver, 30 native brightness changes while leased,
native priority, pause, lease expiry/UI crash, invalid packets, unmodified
native input buffer and unrelated ioctl passthrough; repeated runs passed.
Go race tests/vet and ARM64 UI build passed. Adapter requires GLIBC_2.17.
Launcher disabled/enabled/pending/missing-library cases were executed in
a fake filesystem. These are not a substitute for the flashlight test.

Owner explicitly authorised one controlled Mini reboot. Adapter loaded,
ready status and zero errors verified after that reboot. Palette correction,
saved calibration and audio configuration remain unchanged.
Visual flashlight/pause acceptance is pending. No public release yet.
