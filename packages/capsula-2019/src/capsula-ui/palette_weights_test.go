// SPDX-License-Identifier: MIT
package main

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"testing"
)

func TestWeightedPalettePreservesDominance(t *testing.T) {
	red, orange, cream := rgb{.65, 0, 0}, rgb{.81, .39, .20}, rgb{.94, .73, .57}
	reps := []rgb{red, orange, cream}
	clusters := []clusterMass{{red, 80}, {orange, 10}, {cream, 10}}
	p := weightedPaletteStops(reps, clusters)
	counts := map[rgb]int{}
	for _, c := range p {
		counts[c]++
	}
	if len(p) != 12 || counts[red] != 10 || counts[orange] != 1 || counts[cream] != 1 {
		t.Fatalf("small highlights got equal arcs: %v", counts)
	}
}

func TestWeightedPaletteGroupsDarkRedWithRed(t *testing.T) {
	red, cream := rgb{.7, 0, 0}, rgb{.9, .7, .55}
	clusters := []clusterMass{{rgb{.15, 0, 0}, 99}, {cream, 1}}
	p := weightedPaletteStops([]rgb{red, cream}, clusters)
	if len(p) != 1 || p[0] != red {
		t.Fatalf("shadows must support the dominant hue: %v", p)
	}
}

func TestWeightedPaletteBalancedArtworkKeepsBothColours(t *testing.T) {
	red, blue := rgb{1, 0, 0}, rgb{0, 0, 1}
	p := weightedPaletteStops([]rgb{red, blue}, []clusterMass{{red, 1}, {blue, 1}})
	counts := map[rgb]int{}
	for _, c := range p {
		counts[c]++
	}
	if counts[red] != 6 || counts[blue] != 6 {
		t.Fatalf("balanced cover must not collapse to the first colour: %v", counts)
	}
}

func TestRedRoomWithPaleSandDoesNotGetWhiteHalfRing(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	for y := 0; y < 100; y++ {
		for x := 0; x < 100; x++ {
			c := color.RGBA{160, 10, 3, 255}
			if x >= 75 && x < 85 {
				c = color.RGBA{206, 110, 70, 255}
			} else if x >= 85 {
				c = color.RGBA{240, 195, 160, 255}
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
	red, pale := 0, 0
	for i := 0; i < 12; i++ {
		c := sampleGradient(p, float64(i)*float64(len(p))/12)
		if c[1] < c[0]*.25 && c[2] < c[0]*.25 {
			red++
		}
		if c[2] > c[0]*.45 {
			pale++
		}
	}
	if red < 8 || pale > 2 {
		t.Fatalf("dominant red lost to pale accents: red=%d pale=%d palette=%v", red, pale, p)
	}
}
