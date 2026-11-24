// SPDX-License-Identifier: MIT
package main

import (
	"math"
	"testing"
	"time"
)

func TestMiniClockMapping(t *testing.T) {
	var seen [30]bool
	for _, n := range miniClockMap {
		if n < 0 || n >= 30 || seen[n] {
			t.Fatal("invalid channel map")
		}
		seen[n] = true
	}
	frame, ok := miniClockFrame("2223", [2]byte{1, 1})
	if !ok {
		t.Fatal("clock rejected")
	}
	// Read-only observation of the stock device, 22:23, no test writes.
	want := [30]byte{1, 1, 1, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0}
	if frame != want {
		t.Fatalf("mapping differs from stock: %v", frame)
	}
	for _, s := range []string{"", "123", "12345", "12x4", "1:34"} {
		if _, ok := miniClockFrame(s, [2]byte{}); ok {
			t.Fatal("invalid clock accepted")
		}
	}
}

func TestMiniVUCells(t *testing.T) {
	for _, v := range []float64{0, -1, math.NaN(), math.Inf(1), math.Inf(-1)} {
		if miniVUCell(v) != 0 {
			t.Fatal("invalid/silent audio lit display")
		}
	}
	previous := byte(0)
	for _, v := range []float64{.1, .3, .5, .7, 1} {
		mask := miniVUCell(v)
		if mask&previous != previous {
			t.Fatal("column shrank as level increased")
		}
		previous = mask
	}
	if previous != 0x7f {
		t.Fatal("full height missing")
	}
}

func TestMiniVUHistory(t *testing.T) {
	now := time.Unix(100, 0)
	var h miniVUHistory
	if got := h.frame(now, 0); got != [30]byte{} {
		t.Fatal("silent frame")
	}
	h.frame(now.Add(40*time.Millisecond), 1)
	if level := h.delayedLevel(now.Add(40*time.Millisecond), now.Add(20*time.Millisecond)); math.Abs(level-.5) > 1e-9 {
		t.Fatal("history does not interpolate real samples", level)
	}
	if got := h.frame(now.Add(2*time.Second), 0); got != [30]byte{} {
		t.Fatal("stale level lit display")
	}
}

func TestMiniVUSmoothWave(t *testing.T) {
	now := time.Unix(100, 0)
	var h miniVUHistory
	h.frame(now, 0)
	h.frame(now.Add(40*time.Millisecond), 1)
	peak := h.columns[0]
	if peak <= .4 || peak >= 1 || h.columns[1] != 0 {
		t.Fatal("attack or real travelling delay", h.columns)
	}
	h.frame(now.Add(80*time.Millisecond), 0)
	if h.columns[0] <= peak*.8 || h.columns[0] >= peak {
		t.Fatal("falling tail is not smooth", h.columns[0])
	}
	h.frame(now.Add(120*time.Millisecond), 0)
	if h.columns[1] <= 0 || h.columns[2] != 0 {
		t.Fatal("pulse did not travel through real history", h.columns)
	}
	for i := 4; i < 90; i++ {
		frame := h.frame(now.Add(time.Duration(i)*40*time.Millisecond), 0)
		if i == 89 && frame != [30]byte{} {
			t.Fatal("tail did not settle to silence")
		}
	}
}

func TestMiniVUHysteresis(t *testing.T) {
	if got := miniVUBand(2, .405); got != 2 {
		t.Fatal("threshold chatter on rise", got)
	}
	if got := miniVUBand(3, .395); got != 3 {
		t.Fatal("threshold chatter on fall", got)
	}
	if miniVUBand(2, .45) != 3 || miniVUBand(3, .35) != 2 {
		t.Fatal("real transition suppressed")
	}
	if miniVUBand(5, math.NaN()) != 0 || miniVUBand(5, 0) != 0 {
		t.Fatal("invalid or silent level not cleared")
	}
}

func TestMiniArbiterPacket(t *testing.T) {
	frame := miniSegmentFrame([4]byte{8, 28, 92, 127}, [2]byte{})
	p, err := miniArbiterPacket(frame, true)
	if err != nil || string(p[:4]) != "CDV1" || p[4] != 1 {
		t.Fatal("bad arbiter packet")
	}
	for i, on := range frame {
		if p[8+i] != on {
			t.Fatal("segment order changed")
		}
	}
	p, err = miniArbiterPacket([30]byte{}, false)
	if err != nil || p[4] != 0 {
		t.Fatal("native release lost")
	}
	frame[0] = 2
	if _, err = miniArbiterPacket(frame, true); err == nil {
		t.Fatal("invalid segment accepted")
	}
}
