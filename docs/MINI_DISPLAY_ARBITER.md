# Stock Mini display arbiter

Included in v1.6.0-rc.3; see [installation and limits](RELEASE_1_6_0_RC3.md).

The Mini UI sends versioned 40-byte datagrams with a 400 ms lease, and
never falls back to direct sysfs rendering. The native adapter serializes
its worker and stock display ioctls for the verified is31fl32xx device.
Clock geometry is recognised from nonzero intensities, not boolean values:
actual flashlight capture was 1..19, not flags with a separate brightness
byte. Leased VU patterns use the latest native peak intensity. Adjacent
opaque bytes are preserved, and cached native frames restore on pause/
expiry. Non-clock native frames get 1.8 s priority.

Adapter activation is per-process, not global preload. A pending startup
guard bypasses an unsuccessful preload on the next launch; the existing
stock startup fallback remains. Do not stop/re-exec voice-agent manually.

Owner accepted revision 2 after a controlled reboot and flashlight/pause
test. Status capture showed active VU through brightness ramps, increasing
clock overrides, unchanged native-priority count and zero driver errors.
Full voice/volume tour, long-duration behaviour and clean-device install
still require qualification. The earlier boolean-intensity revision failed
live testing and is NOT the shipped adapter.
