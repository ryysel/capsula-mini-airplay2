package main

import "testing"

func TestPanelSanitize(t *testing.T) {
	c := defaultPanel()
	c.Mode = "weird"
	c.Brightness = 9
	c.Gain = [3]float64{0, 2, 1}
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
	if c.Gain[0] != .5 || c.Gain[1] != 1.5 || c.Gain[2] != 1 {
		t.Fatalf("gain %v", c.Gain)
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
	c.sanitize()
	if c.Mode != "test" {
		t.Fatal("test mode must survive sanitize")
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
