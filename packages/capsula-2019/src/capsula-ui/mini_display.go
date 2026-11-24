// SPDX-License-Identifier: MIT
package main

// Experimental Mini display VU: four delayed level columns, not an FFT.
// The stock display is four seven-segment cells, with two colon channels.
// Opt in for this boot only: /tmp/capsula-mini-display-vu.
import (
	"context"
	"fmt"
	"math"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// Logical a,b,c,d,e,f,g for the first two cells, colon, last two cells.
// Independently checked against the live stock 22:23 frame.
var miniClockMap = [30]int{1, 28, 21, 17, 22, 29, 24, 26, 25, 19, 18, 23, 27, 20, 16, 15, 0, 2, 7, 5, 6, 4, 3, 10, 12, 11, 14, 13, 8, 9}
var miniDigitStart = [4]int{0, 7, 16, 23}
var miniNumerals = [10]byte{0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f}

func miniSegmentFrame(glyphs [4]byte, colon [2]byte) (out [30]byte) {
	for digit, start := range miniDigitStart {
		for segment := 0; segment < 7; segment++ {
			out[miniClockMap[start+segment]] = (glyphs[digit] >> segment) & 1
		}
	}
	out[miniClockMap[14]], out[miniClockMap[15]] = colon[0]&1, colon[1]&1
	return
}

func miniClockFrame(text string, colon [2]byte) ([30]byte, bool) {
	var glyphs [4]byte
	if len(text) != 4 {
		return [30]byte{}, false
	}
	for i := range glyphs {
		if text[i] < '0' || text[i] > '9' {
			return [30]byte{}, false
		}
		glyphs[i] = miniNumerals[text[i]-'0']
	}
	return miniSegmentFrame(glyphs, colon), true
}

func miniVUCell(level float64) byte {
	if math.IsNaN(level) || math.IsInf(level, 0) || level < .035 {
		return 0
	}
	switch {
	case level < .2:
		return 0x08 // bottom
	case level < .4:
		return 0x1c // lower sides and bottom
	case level < .6:
		return 0x5c // lower half
	case level < .8:
		return 0x7c // both sides, middle and bottom
	default:
		return 0x7f // full height
	}
}

type miniLevelSample struct {
	at    time.Time
	level float64
}
type miniVUHistory struct {
	samples [12]miniLevelSample
	next    int
}

func (h *miniVUHistory) frame(now time.Time, level float64) [30]byte {
	h.samples[h.next] = miniLevelSample{now, level}
	h.next = (h.next + 1) % len(h.samples)
	var glyphs [4]byte
	for i := range glyphs {
		target := now.Add(-time.Duration(i) * 80 * time.Millisecond)
		var best miniLevelSample
		for _, sample := range h.samples {
			if !sample.at.IsZero() && !sample.at.After(target) && sample.at.After(best.at) {
				best = sample
			}
		}
		if !best.at.IsZero() && now.Sub(best.at) <= 500*time.Millisecond {
			glyphs[i] = miniVUCell(best.level)
		}
	}
	return miniSegmentFrame(glyphs, [2]byte{})
}

type miniDisplayVU struct {
	files   [30]*os.File
	last    [30]byte
	colon   [2]byte
	history miniVUHistory
	open    bool
	failed  bool
	next    time.Time
}

var displayVU miniDisplayVU

func stockClockText() (string, error) {
	// Stock's date respects its own timezone configuration (not Go's UTC
	// fallback on Buildroot). Fixed arguments; no account/config data read.
	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()
	out, err := exec.CommandContext(ctx, "date", "+%H%M").Output()
	return strings.TrimSpace(string(out)), err
}

func (d *miniDisplayVU) acquire() error {
	var snapshot [30]byte
	for i := range snapshot {
		path := fmt.Sprintf("/sys/class/leds/clock-led%d/brightness", i+1)
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		n, err := strconv.Atoi(strings.TrimSpace(string(b)))
		if err != nil || n < 0 || n > 1 {
			return fmt.Errorf("unrecognised display state")
		}
		snapshot[i] = byte(n)
	}
	d.colon = [2]byte{snapshot[miniClockMap[14]], snapshot[miniClockMap[15]]}
	text, err := stockClockText()
	if err != nil {
		return err
	}
	expected, ok := miniClockFrame(text, d.colon)
	if !ok || expected != snapshot {
		return fmt.Errorf("display not showing the expected stock clock; yield")
	}
	for i := range d.files {
		f, err := os.OpenFile(fmt.Sprintf("/sys/class/leds/clock-led%d/brightness", i+1), os.O_WRONLY, 0)
		if err != nil {
			d.close()
			return err
		}
		d.files[i] = f
	}
	d.last, d.open = snapshot, true
	return nil
}

func (d *miniDisplayVU) close() {
	for i, f := range d.files {
		if f != nil {
			f.Close()
			d.files[i] = nil
		}
	}
	d.open = false
	d.history = miniVUHistory{}
}

func (d *miniDisplayVU) write(frame [30]byte, force bool) error {
	for i, f := range d.files {
		if f == nil {
			return fmt.Errorf("display closed")
		}
		if !force && frame[i] == d.last[i] {
			continue
		}
		if _, err := f.WriteAt([]byte{'0' + frame[i]}, 0); err != nil {
			return err
		}
	}
	d.last = frame
	return nil
}

func (d *miniDisplayVU) release(restore bool) {
	if !d.open {
		return
	}
	if restore {
		if text, err := stockClockText(); err == nil {
			if frame, ok := miniClockFrame(text, d.colon); ok {
				_ = d.write(frame, true)
			}
		}
	}
	d.close()
}

func (d *miniDisplayVU) tick(now time.Time, active bool) {
	if !miniHardware {
		return
	}
	if now.Before(d.next) {
		return
	}
	d.next = now.Add(80 * time.Millisecond) // at most 12.5 Hz; no PCM or receiver changes
	_, enabled := os.Stat("/tmp/capsula-mini-display-vu")
	if enabled != nil {
		d.release(!miniBusy())
		d.failed = false
		return
	}
	if miniBusy() {
		// Do not restore a clock over native volume/assistant animation.
		d.release(false)
		return
	}
	fresh := false
	if st, err := os.Stat("/tmp/capsula-airplay-level"); err == nil {
		fresh = now.Sub(st.ModTime()) >= -time.Second && now.Sub(st.ModTime()) < 350*time.Millisecond
	}
	if !active || !fresh {
		d.release(true)
		return
	}
	if d.failed {
		return
	}
	if !d.open {
		if err := d.acquire(); err != nil {
			// Retry a clock transition or native animation with low overhead.
			d.next = now.Add(time.Second)
			return
		}
	}
	if err := d.write(d.history.frame(now, beatEnvelope), true); err != nil {
		d.release(true)
		d.failed = true // fail closed until opt-in is removed
	}
}
