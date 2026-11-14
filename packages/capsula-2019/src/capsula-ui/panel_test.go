package main

import (
	"math"
	"testing"
)

func closeRGB(a, b rgb) bool {
	return math.Abs(a[0]-b[0]) < 1e-9 && math.Abs(a[1]-b[1]) < 1e-9 && math.Abs(a[2]-b[2]) < 1e-9
}

func TestPanelSanitize(t *testing.T) {
	c := defaultPanel()
	c.Mode = "weird"
	c.Brightness = 9
	c.LUT = [27][3]float64{}
	c.Saturation = -1
	c.Pulse = 4
	c.FadeMS = 5000
	c.Pixels = c.Pixels[:3]
	c.Pixels[0] = [3]int{-5, 300, 128}
	c.sanitize()
	if c.Mode != "auto" {
		t.Fatalf("mode %q", c.Mode)
	}
	if c.Brightness != 1 {
		t.Fatalf("brightness %v", c.Brightness)
	}
	if c.LUT != defaultLUT() {
		t.Fatal("zero table must become identity")
	}
	if c.Saturation != 0 || c.Pulse != 1 || c.FadeMS != 1000 {
		t.Fatalf("limits %+v", c)
	}
	if len(c.Pixels) != 12 {
		t.Fatalf("pixels %d", len(c.Pixels))
	}
	if c.Pixels[0] != [3]int{0, 255, 128} {
		t.Fatalf("pixel %v", c.Pixels[0])
	}
	if c.Pixels[11] != [3]int{255, 255, 255} {
		t.Fatalf("pad %v", c.Pixels[11])
	}

	c.Mode = "test"
	c.LUT[18] = [3]float64{2, -.5, 0}
	c.sanitize()
	if c.Mode != "test" {
		t.Fatal("test mode must survive sanitize")
	}
	if c.LUT[18][0] != 1 || c.LUT[18][1] != 0 {
		t.Fatalf("clamp %v", c.LUT[18])
	}
}

func TestLUTIdentity(t *testing.T) {
	m := [3][3]float64{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
	lut := lutFromMatrix(m)
	for _, c := range []rgb{{0, 0, 0}, {1, 1, 1}, {.2, .4, .6}, {1, .5, 0}, {.25, .75, .5}} {
		if got := applyLUT(c, &lut); !closeRGB(got, c) {
			t.Fatalf("identity %v -> %v", c, got)
		}
	}
}

func TestStockCalibration(t *testing.T) {
	mini := defaultLUTFor(true)
	if got := applyLUT(rgb{0, 0, 0}, &mini); !closeRGB(got, rgb{.03137, .01176, .02745}) {
		t.Fatalf("mini black %v", got)
	}
	if got := applyLUT(rgb{1, .5, 0}, &mini); !closeRGB(got, rgb{1, .2, 0}) {
		t.Fatalf("mini orange %v", got)
	}
	big := defaultLUTFor(false)
	if got := applyLUT(rgb{0, 0, 0}, &big); !closeRGB(got, rgb{.02745, 0, .03529}) {
		t.Fatalf("2019 black %v", got)
	}
	if got := applyLUT(rgb{1, 1, 0}, &big); !closeRGB(got, rgb{1, .74510, 0}) {
		t.Fatalf("2019 yellow %v", got)
	}
	// The black point is still editable.
	big[lutIndex(0, 0, 0)] = [3]float64{.18, 0, .28}
	if got := applyLUT(rgb{0, 0, 0}, &big); !closeRGB(got, rgb{.18, 0, .28}) {
		t.Fatalf("purple black point %v", got)
	}
}

func TestLUTNodeIsExact(t *testing.T) {
	lut := defaultLUT()
	lut[lutIndex(2, 1, 0)] = [3]float64{1, .4, 0} // orange
	if got := applyLUT(rgb{1, .5, 0}, &lut); !closeRGB(got, rgb{1, .4, 0}) {
		t.Fatalf("orange node %v", got)
	}
	lut[lutIndex(2, 2, 2)] = [3]float64{.9, .9, .8} // white
	if got := applyLUT(rgb{1, 1, 1}, &lut); !closeRGB(got, rgb{.9, .9, .8}) {
		t.Fatalf("white node %v", got)
	}
}

func TestLUTInterpolatesArtwork(t *testing.T) {
	lut := defaultLUT()
	lut[lutIndex(2, 0, 0)] = [3]float64{1, 0, 0}  // red
	lut[lutIndex(2, 1, 0)] = [3]float64{1, .4, 0} // orange
	// Halfway between red and orange in the green axis.
	if got := applyLUT(rgb{1, .25, 0}, &lut); !closeRGB(got, rgb{1, .2, 0}) {
		t.Fatalf("edge interpolation %v", got)
	}
	// A colour outside the edited cell keeps the identity mapping.
	if got := applyLUT(rgb{0, 0, 1}, &lut); !closeRGB(got, rgb{0, 0, 1}) {
		t.Fatalf("blue untouched %v", got)
	}
}

func TestLUTFromMatrixMigration(t *testing.T) {
	m := [3][3]float64{{1, 0, 0}, {1, .302, 0}, {0, 0, 1}}
	lut := lutFromMatrix(m)
	if got := applyLUT(rgb{0, 1, 0}, &lut); !closeRGB(got, rgb{1, .302, 0}) {
		t.Fatalf("migrated green %v", got)
	}
	// The old matrix moved green towards red, so white also turns magenta:
	// this is exactly why the per-node table is better for calibration.
	if got := applyLUT(rgb{1, 1, 1}, &lut); !closeRGB(got, rgb{1, .302, 1}) {
		t.Fatalf("migrated white %v", got)
	}
}

func TestPanelRecordClamps(t *testing.T) {
	cols := [12]rgb{}
	cols[0] = rgb{2, 0, 0}
	cols[11] = rgb{.5, .5, .5}
	panelRecord(cols, 1)
	if panelLive[0] != [3]int{255, 0, 0} {
		t.Fatalf("live[0] %v", panelLive[0])
	}
	if panelLive[11] != [3]int{128, 128, 128} {
		t.Fatalf("live[11] %v", panelLive[11])
	}
	panelRecord(cols, .5)
	if panelLive[11] != [3]int{64, 64, 64} {
		t.Fatalf("scaled %v", panelLive[11])
	}
}

func TestSaturateColour(t *testing.T) {
	c := saturateColour(rgb{1, 0, 0}, 0)
	l := .2126
	if c[0] != l || c[1] != l || c[2] != l {
		t.Fatalf("grey %v", c)
	}
	c = saturateColour(rgb{1, 0, 0}, 1.5)
	if c[0] > 1 || c[1] < 0 || c[2] < 0 {
		t.Fatalf("clamp %v", c)
	}
}
