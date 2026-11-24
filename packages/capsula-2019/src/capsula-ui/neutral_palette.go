// SPDX-License-Identifier: MIT
package main

import (
	"image"
	"math"
	"sort"
)

// Keep visible area, including neutral backgrounds and shadows. Chroma gets
// at most a 25% preference, not the old unbounded advantage over grey (zero).
// Brightness is averaged within a hue family BEFORE any output correction.
func coverImagePalette(img image.Image, width, height int) []rgb {
	type family struct {
		sum  rgb
		mass float64
	}
	bins := map[int]*family{}
	var neutralSum, neutralMass float64
	dx, dy := max(1, width/64), max(1, height/64)
	for y := 0; y < height; y += dy {
		for x := 0; x < width; x += dx {
			r, g, b, a := img.At(img.Bounds().Min.X+x, img.Bounds().Min.Y+y).RGBA()
			if a == 0 {
				continue
			}
			// RGBA returns premultiplied channels: transparent padding has no area.
			c := rgb{float64(r) / float64(a), float64(g) / float64(a), float64(b) / float64(a)}
			area := float64(a) / 65535
			hi, lo := max(c[0], max(c[1], c[2])), min(c[0], min(c[1], c[2]))
			saturation := 0.0
			if hi > 0 {
				saturation = (hi - lo) / hi
			}
			if saturation < coverMinSaturation || hi-lo < .035 {
				neutralMass += area
				neutralSum += (c[0] + c[1] + c[2]) / 3 * area
				continue
			}
			direction := colourDirection(c)
			key := (int(direction[0]*7) << 6) | (int(direction[1]*7) << 3) | int(direction[2]*7)
			if bins[key] == nil {
				bins[key] = &family{}
			}
			v := bins[key]
			mass := area * (1 + .25*saturation)
			v.mass += mass
			for k := range c {
				v.sum[k] += c[k] * mass
			}
		}
	}
	keys := make([]int, 0, len(bins))
	for key := range bins {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		a, b := bins[keys[i]].mass, bins[keys[j]].mass
		if a == b {
			return keys[i] < keys[j]
		}
		return a > b
	})
	var clusters []clusterMass
	var representatives []rgb
	var chromaMass float64
	for _, key := range keys {
		v := bins[key]
		c := v.sum
		for k := range c {
			c[k] /= v.mass
		}
		c = coverColour(c)
		clusters = append(clusters, clusterMass{c, v.mass})
		chromaMass += v.mass
		distinct := true
		for _, other := range representatives {
			a, b := colourDirection(c), colourDirection(other)
			d := 0.0
			for k := range a {
				d += (a[k] - b[k]) * (a[k] - b[k])
			}
			if d < .10 {
				distinct = false
			}
		}
		if distinct && len(representatives) < 3 {
			representatives = append(representatives, c)
		}
	}
	neutral := rgb{}
	if neutralMass > 0 {
		// Retain the deliberately dim neutral rendering, without turning black
		// into white or normalising a charcoal sleeve to full brightness.
		v := math.Min(.30, neutralSum/neutralMass*.6)
		neutral = rgb{v, v, v}
	}
	if chromaMass == 0 {
		return []rgb{neutral}
	}
	colours := weightedPaletteStops(representatives, clusters)
	if neutralMass == 0 {
		return colours
	}
	const stops = 12
	neutralCount := int(math.Round(stops * neutralMass / (neutralMass + chromaMass)))
	if neutralCount == stops {
		return []rgb{neutral}
	}
	if neutralCount == 0 {
		return colours
	}
	out := make([]rgb, 0, stops)
	for i := 0; i < stops-neutralCount; i++ {
		out = append(out, sampleGradient(colours, float64(i)*float64(len(colours))/float64(stops-neutralCount)))
	}
	for i := 0; i < neutralCount; i++ {
		out = append(out, neutral)
	}
	return out
}
