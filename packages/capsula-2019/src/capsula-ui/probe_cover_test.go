package main

import (
	"fmt"
	"math"
	"os"
	"testing"
)

func TestPrivateCoverProbe(t *testing.T) {
	path := os.Getenv("CAPSULA_PRIVATE_COVER")
	if path == "" {
		t.Skip("private cover not supplied")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	p, err := palette(data)
	if err != nil {
		t.Fatal(err)
	}
	neutral := 0
	for _, c := range p {
		fmt.Printf("cover stop RGB %d %d %d\n", int(c[0]*255), int(c[1]*255), int(c[2]*255))
		if math.Abs(c[0]-c[1]) < .001 && math.Abs(c[1]-c[2]) < .001 {
			neutral++
		}
	}
	fmt.Printf("neutral stops=%d total=%d\n", neutral, len(p))
}
