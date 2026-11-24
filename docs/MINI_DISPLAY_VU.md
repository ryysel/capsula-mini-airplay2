# Stock Mini display VU (experimental)

Released in v1.6.0-rc.2 as an optional stock-Mini feature.
See [installation, disabling and validation limits](RELEASE_1_6_0_RC2.md).

The UI consumes real PCM-envelope values with 0/100/200/300 ms delays,
interpolated history, 45 ms attack, 320 ms release and ±0.025 hysteresis.
Five height steps on seven-segment digits; 25 Hz renderer. Not an FFT.
Only stock Mini is addressed; no audio capture or receiver modification.

Startup creates the runtime marker only when `etc/mini-display-vu.enabled`
exists. `--display-vu` enables, `--clock` disables, ordinary install/upgrade
preserves the preference. The renderer yields on native speech/volume
markers and restores clock on pause/stale PCM/normal exit.
Full priority behaviour and cold boot remain unqualified.

Physical channel mapping is checked against a read-only live clock frame.
Owner confirmed moving columns and clock restoration, then accepted the
smooth revision for persistent local installation. Source and archive
tests are not a substitute for broader hardware acceptance.
