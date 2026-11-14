package main

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"math"
	"testing"
)

func picture(c color.RGBA) []byte {
	m := image.NewRGBA(image.Rect(0, 0, 64, 64))
	for y := 0; y < 64; y++ {
		for x := 0; x < 64; x++ {
			m.SetRGBA(x, y, c)
		}
	}
	var b bytes.Buffer
	png.Encode(&b, m)
	return b.Bytes()
}

// blob is a mostly uniform cover with a saturated square in one corner, which
// is what a dark or letterboxed sleeve looks like in practice.
func blob(base, accent color.RGBA) []byte {
	m := image.NewRGBA(image.Rect(0, 0, 64, 64))
	for y := 0; y < 64; y++ {
		for x := 0; x < 64; x++ {
			c := base
			if x >= 40 && y >= 40 {
				c = accent
			}
			m.SetRGBA(x, y, c)
		}
	}
	var b bytes.Buffer
	png.Encode(&b, m)
	return b.Bytes()
}

func TestPaletteRed(t *testing.T) {
	p, e := palette(picture(color.RGBA{255, 0, 0, 255}))
	if e != nil || len(p) != 1 || p[0][0] < .8 || p[0][1] > .1 || p[0][2] > .1 {
		t.Fatalf("%v %v", p, e)
	}
}

func TestPaletteNeutral(t *testing.T) {
	for _, v := range []uint8{0, 80, 255} {
		p, e := palette(picture(color.RGBA{v, v, v, 255}))
		if e != nil || len(p) != 1 || math.Abs(p[0][0]-p[0][1]) > .001 || math.Abs(p[0][1]-p[0][2]) > .001 {
			t.Fatalf("%v %v", p, e)
		}
		if p[0][0] > .32 {
			t.Fatalf("neutral grey is too bright: %v", p)
		}
	}
}

// A dark sleeve with a small warm subject must yield that warm colour, not the
// average grey: this is the "dark theme, white ring" regression.
func TestPaletteDarkCoverKeepsAccent(t *testing.T) {
	p, e := palette(blob(color.RGBA{12, 12, 16, 255}, color.RGBA{235, 110, 20, 255}))
	if e != nil || len(p) == 0 {
		t.Fatalf("%v %v", p, e)
	}
	c := p[0]
	if c[0]-c[2] < .15 || c[0] < .5 {
		t.Fatalf("accent lost in a dark cover: %v", p)
	}
}

// A pale washed-out sky is low saturation, so it must not outvote a saturated
// subject the way brightness weighting used to.
func TestPalettePaleSkyDoesNotWin(t *testing.T) {
	p, e := palette(blob(color.RGBA{205, 220, 238, 255}, color.RGBA{30, 90, 200, 255}))
	if e != nil || len(p) == 0 {
		t.Fatalf("%v %v", p, e)
	}
	c := p[0]
	if c[2]-c[0] < .15 || c[2] < .5 {
		t.Fatalf("blue subject lost to pale sky: %v", p)
	}
}

// Two clusters a hair apart must collapse to one, otherwise the ring repeats
// the same hue and loses a real colour.
func TestPaletteDeduplicates(t *testing.T) {
	p, e := palette(blob(color.RGBA{40, 90, 170, 255}, color.RGBA{50, 100, 180, 255}))
	if e != nil || len(p) != 1 {
		t.Fatalf("%v %v", p, e)
	}
}

func TestPaletteRejects(t *testing.T) {
	for _, b := range [][]byte{nil, []byte("not an image"), make([]byte, (4<<20)+1)} {
		if _, e := palette(b); e == nil {
			t.Fatal("accepted bad artwork")
		}
	}
}

func TestGradientWraps(t *testing.T) {
	p := []rgb{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
	if got := sampleGradient(p, 0); got != (rgb{1, 0, 0}) {
		t.Fatalf("start %v", got)
	}
	if got := sampleGradient(p, 2.5); math.Abs(got[0]-.5) > .001 || math.Abs(got[2]-.5) > .001 || got[1] > .001 {
		t.Fatalf("wrap %v", got)
	}
}

func TestSchedule(t *testing.T) {
	for _, v := range []struct {
		hour int
		want float64
	}{{7, .3}, {8, 1}, {19, 1}, {20, .7}, {22, .7}, {23, .3}} {
		if brightness(v.hour) != v.want {
			t.Fatal(v)
		}
	}
}

func TestPalettePrimariesStayInOwnChannel(t *testing.T) {
 for k:=0;k<3;k++ {
   c:=color.RGBA{A:255}
   if k==0 {c.R=255}; if k==1 {c.G=255}; if k==2 {c.B=255}
   p,err:=palette(picture(c))
   if err!=nil||len(p)!=1 {t.Fatalf("%v %v",p,err)}
   for channel,v:=range p[0] {
     if channel==k&&v<.8 {t.Fatalf("primary lost %v",p)}
     if channel!=k&&v>.01 {t.Fatalf("primary channel swapped %v",p)}
   }
 }
}
