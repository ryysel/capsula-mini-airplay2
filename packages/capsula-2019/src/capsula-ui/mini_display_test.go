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
	h.frame(now.Add(80*time.Millisecond), 1)
	got := h.frame(now.Add(160*time.Millisecond), 0)
	want := miniSegmentFrame([4]byte{0, 0x7f, 0, 0}, [2]byte{})
	if got != want {
		t.Fatal("columns are not delayed real levels")
	}
	if got := h.frame(now.Add(2*time.Second), 0); got != [30]byte{} {
		t.Fatal("stale level lit display")
	}
}
