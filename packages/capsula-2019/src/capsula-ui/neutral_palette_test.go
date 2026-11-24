// SPDX-License-Identifier: MIT
package main

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"math"
	"testing"
)

func TestDarkBurgundyIsNotLiftedToBrightRed(t *testing.T) {
	for _, v := range []uint8{20, 35, 60, 100} {
		p, err := palette(picture(color.RGBA{v, 0, 0, 255}))
		if err != nil || len(p) != 1 {
			t.Fatalf("%v %v", p, err)
		}
		if p[0][0] > float64(v)/255+.002 || p[0][1] > .001 || p[0][2] > .001 {
			t.Fatalf("dark red artificially lifted: input=%d palette=%v", v, p)
		}
	}
}

func TestNeutralSleeveKeepsAreaAgainstBurgundySubject(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	for y := 0; y < 100; y++ {
		for x := 0; x < 100; x++ {
			c := color.RGBA{140, 140, 140, 255}
			if x < 25 {
				c = color.RGBA{50, 3, 1, 255}
			}
			if y < 15 {
				c = color.RGBA{8, 8, 8, 255}
			}
			img.SetRGBA(x, y, c)
		}
	}
	var data bytes.Buffer
	if err := png.Encode(&data, img); err != nil {
		t.Fatal(err)
	}
	p, err := palette(data.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	neutral, red := 0, 0
	for _, c := range p {
		if math.Abs(c[0]-c[1]) < .001 && math.Abs(c[1]-c[2]) < .001 {
			neutral++
		}
		if c[0] > c[1]*2 && c[0] > c[2]*2 {
			red++
			if c[0] > .21 {
				t.Fatalf("burgundy was boosted: %v", p)
			}
		}
	}
	if len(p) != 12 || neutral < 8 || red > 4 || red == 0 {
		t.Fatalf("neutral area lost: %v", p)
	}
}

func TestSmallPaleAccentDoesNotGetHalfRing(t *testing.T) {
	p, err := palette(blob(color.RGBA{140, 0, 0, 255}, color.RGBA{210, 210, 210, 255}))
	if err != nil {
		t.Fatal(err)
	}
	neutral := 0
	for _, c := range p {
		if math.Abs(c[0]-c[1]) < .001 && math.Abs(c[1]-c[2]) < .001 {
			neutral++
		}
	}
	if neutral > 2 {
		t.Fatalf("small grey accent got excessive area: %v", p)
	}
}

func TestNeutralPaletteDeterministic(t *testing.T) {
	data := blob(color.RGBA{100, 100, 100, 255}, color.RGBA{60, 5, 0, 255})
	first, _ := palette(data)
	for i := 0; i < 20; i++ {
		next, _ := palette(data)
		if len(first) != len(next) {
			t.Fatal("unstable palette")
		}
		for k := range first {
			if first[k] != next[k] {
				t.Fatal("unstable palette")
			}
		}
	}
}
