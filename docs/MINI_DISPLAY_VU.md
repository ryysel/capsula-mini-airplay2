# Stock Mini music VU

Optional feature: `sh install.sh --upgrade --display-vu` from mini-stock.
See [rc.3 installation/reboot/disable instructions](RELEASE_1_6_0_RC3.md).

The rc.4 pattern uses four horizontal middle strokes. Music accents add top
and bottom strokes in mirrored pairs, inner first, outer 80 ms later.
The real PCM envelope is smoothed with a 45 ms attack, a 220 ms release
and hysteresis. Not an FFT. Ring calibration is independent.

Native display arbitration is mandatory: no direct hardware fallback.
No loaded adapter means stock clock until the manual reboot.
Ordinary upgrades preserve the display preference; --clock disables.
Owner accepted waveform, clock restoration and flashlight auto-brightness.
