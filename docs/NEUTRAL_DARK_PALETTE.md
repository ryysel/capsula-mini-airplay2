# Neutral backgrounds and dark cover colours (local candidate)

The prior chroma-only palette ignored neutral area, so a mostly grey cover
with a dark burgundy subject could become a bright red ring.

This candidate counts neutral/shadow area and gives chroma at most 25%
extra weight. Related shades share hue-family bins, whose source
brightness is averaged before saturation correction. No forced 55%
minimum brightness remains. Neutrals retain the dim-grey rendering;
saved device calibration is not changed.

The Hybrid Theory reproduction changed from ten RGB(140,0,0) stops
plus two warm stops to two RGB(43,0,0) and ten RGB(76,76,76) stops.
These are logical palette values, NOT photometric measurements.
The copyrighted cover image is outside Git and not part of the tests.
Optional private-cover probe uses CAPSULA_PRIVATE_COVER environment path.

Regression checks: dominant red with small pale highlights; grey/black
background and burgundy subject; no forced dark-red lift; balanced hues,
primaries, deterministic sampling, existing neutral and accent tests.
Go race/vet and ARM64 build passed.

Installed only on owner's stock Mini by permission; smooth display VU,
receiver, calibration and boot opt-in unchanged. Big was not updated.
No new release/tag/public push is authorised by this fix request.
Steady-state audio acceptance and colour appearance remain separate checks.
