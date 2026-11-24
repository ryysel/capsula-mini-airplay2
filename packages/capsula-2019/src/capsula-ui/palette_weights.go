// SPDX-License-Identifier: MIT
package main

import "math"

// clusterMass retains the chroma-weighted image area which previously got
// discarded after choosing three representatives.
type clusterMass struct {
	colour rgb
	weight float64
}

func colourDirection(c rgb) rgb {
	peak := max(c[0], max(c[1], c[2]))
	if peak > 0 {
		for i := range c {
			c[i] /= peak
		}
	}
	return c
}

// weightedPaletteStops keeps the existing cyclic-gradient renderer but gives
// colours proportional arc lengths. Repeated stops are intentional: a red
// background must not share equal thirds with two small pale highlights.
// Distance ignores brightness so dark-red pixels support the red family too.
func weightedPaletteStops(representatives []rgb, clusters []clusterMass) []rgb {
	if len(representatives) <= 1 {
		return representatives
	}
	weights := make([]float64, len(representatives))
	for _, cluster := range clusters {
		if cluster.weight <= 0 {
			continue
		}
		c := colourDirection(cluster.colour)
		nearest, distance := 0, math.Inf(1)
		for i, representative := range representatives {
			r := colourDirection(representative)
			d := 0.0
			for k := 0; k < 3; k++ {
				delta := c[k] - r[k]
				d += delta * delta
			}
			if d < distance {
				nearest, distance = i, d
			}
		}
		weights[nearest] += cluster.weight
	}
	total := 0.0
	for _, weight := range weights {
		total += weight
	}
	if total <= 0 {
		return representatives
	}
	const stops = 12
	counts := make([]int, len(weights))
	remainders := make([]float64, len(weights))
	allocated := 0
	for i, weight := range weights {
		exact := weight * stops / total
		counts[i] = int(math.Floor(exact))
		remainders[i] = exact - float64(counts[i])
		allocated += counts[i]
	}
	for allocated < stops {
		best := 0
		for i := 1; i < len(remainders); i++ {
			if remainders[i] > remainders[best] {
				best = i
			}
		}
		counts[best]++
		remainders[best] = -1
		allocated++
	}
	used, only := 0, 0
	for i, count := range counts {
		if count > 0 {
			used++
			only = i
		}
	}
	if used == 1 {
		return []rgb{representatives[only]}
	}
	out := make([]rgb, 0, stops)
	for i, count := range counts {
		for j := 0; j < count; j++ {
			out = append(out, representatives[i])
		}
	}
	return out
}
