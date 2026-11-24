# Stock Mini music VU

Optional feature: `sh install.sh --upgrade --display-vu` from mini-stock.
See [rc.3 installation/reboot/disable instructions](RELEASE_1_6_0_RC3.md).

Four delayed real PCM-envelope levels (0/100/200/300 ms), interpolated
history, 45 ms attack, 320 ms release, hysteresis and five seven-segment
height steps. Not a frequency FFT. Ring calibration is independent.

Native display arbitration is mandatory: no direct hardware fallback.
No loaded adapter means stock clock until the manual reboot.
Ordinary upgrades preserve the display preference; --clock disables.
Owner accepted waveform, clock restoration and flashlight auto-brightness.
