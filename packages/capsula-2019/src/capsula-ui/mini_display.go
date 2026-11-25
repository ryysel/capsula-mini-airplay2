// SPDX-License-Identifier: MIT
package main

// Experimental Mini display VU: a centre-out wave of horizontal strokes, not an FFT.
// The stock display is four seven-segment cells, with two colon channels.
// Opt in for this boot only: /tmp/capsula-mini-display-vu.
import (
	"fmt"
	"math"
	"net"
	"os"
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

type miniLevelSample struct {
	at    time.Time
	level float64
}
type miniVUHistory struct {
	samples [64]miniLevelSample
	next    int
	lastAt  time.Time
	columns [4]float64
	bands   [4]int
}

func (h *miniVUHistory) delayedLevel(now, target time.Time) float64 {
	var before, after miniLevelSample
	for _, sample := range h.samples {
		if sample.at.IsZero() || now.Sub(sample.at) > 500*time.Millisecond || sample.at.After(now) {
			continue
		}
		if !sample.at.After(target) && sample.at.After(before.at) {
			before = sample
		}
		if !sample.at.Before(target) && (after.at.IsZero() || sample.at.Before(after.at)) {
			after = sample
		}
	}
	if before.at.IsZero() {
		return 0
	}
	if after.at.IsZero() || !after.at.After(before.at) {
		return before.level
	}
	t := float64(target.Sub(before.at)) / float64(after.at.Sub(before.at))
	return before.level + t*(after.level-before.level)
}

var miniVUMasks = [3]byte{0, 0x40, 0x49} // blank, middle, top+middle+bottom
var miniVUThresholds = [2]float64{.035, .48}

// Hysteresis avoids rapid on/off flicker when music sits near a segment step.
func miniVUBand(previous int, level float64) int {
	if math.IsNaN(level) || math.IsInf(level, 0) {
		return 0
	}
	if previous < 0 || previous >= len(miniVUMasks) {
		previous = 0
	}
	for previous < len(miniVUThresholds) && level >= miniVUThresholds[previous]+.025 {
		previous++
	}
	for previous > 0 && level < miniVUThresholds[previous-1]-.025 {
		previous--
	}
	return previous
}

func (h *miniVUHistory) frame(now time.Time, level float64) [30]byte {
	if math.IsNaN(level) || math.IsInf(level, 0) {
		level = 0
	}
	// The ring envelope tends to stay near full-scale on mastered tracks.
	// Expand its useful movement range instead of leaving all cells full.
	level = math.Pow(math.Max(0, math.Min(1, level)), 2.2)
	dt := now.Sub(h.lastAt).Seconds()
	if h.lastAt.IsZero() || dt <= 0 || dt > .5 {
		*h = miniVUHistory{}
		dt = .04
	}
	h.lastAt = now
	h.samples[h.next] = miniLevelSample{now, level}
	h.next = (h.next + 1) % len(h.samples)
	var glyphs [4]byte
	for i := range glyphs {
		// The inner pair responds first. Outer accents follow the same real
		// envelope with a small delay, not an independent animation clock.
		target := level
		if i == 0 || i == len(glyphs)-1 {
			target = .83 * h.delayedLevel(now, now.Add(-80*time.Millisecond))
		}
		tau := .22 // relaxed falling tail; quick but not instant attack
		if target > h.columns[i] {
			tau = .045
		}
		h.columns[i] += (target - h.columns[i]) * (1 - math.Exp(-dt/tau))
		h.bands[i] = miniVUBand(h.bands[i], h.columns[i])
		glyphs[i] = miniVUMasks[h.bands[i]]
	}
	return miniSegmentFrame(glyphs, [2]byte{})
}

// The native process is the only hardware writer. We publish leased frames;
// there is deliberately NO sysfs fallback when the arbiter is unavailable.
type miniDisplayVU struct {
	conn    *net.UnixConn
	history miniVUHistory
	open    bool
	next    time.Time
}

var displayVU miniDisplayVU

const miniArbiterSocket = "/tmp/capsula-mini-display-arbiter.sock"
const miniArbiterStatus = "/tmp/capsula-mini-display-arbiter.status"

func (d *miniDisplayVU) acquire() error {
	status, err := os.Stat(miniArbiterStatus)
	if err != nil {
		return err
	}
	age := time.Since(status.ModTime())
	if age < -time.Second || age > 3*time.Second {
		return fmt.Errorf("native display arbiter heartbeat stale")
	}
	conn, err := net.DialUnix("unixgram", nil, &net.UnixAddr{Name: miniArbiterSocket, Net: "unixgram"})
	if err != nil {
		return err
	}
	d.conn, d.open = conn, true
	return nil
}

func miniArbiterPacket(frame [30]byte, active bool) ([40]byte, error) {
	var out [40]byte
	copy(out[:4], "CDV1")
	if active {
		out[4] = 1
	}
	for i, on := range frame {
		if on > 1 {
			return [40]byte{}, fmt.Errorf("invalid display segment")
		}
		out[8+i] = on
	}
	return out, nil
}

func (d *miniDisplayVU) send(frame [30]byte, active bool) error {
	if d.conn == nil {
		return fmt.Errorf("native display arbiter disconnected")
	}
	packet, err := miniArbiterPacket(frame, active)
	if err != nil {
		return err
	}
	if err = d.conn.SetWriteDeadline(time.Now().Add(5 * time.Millisecond)); err != nil {
		return err
	}
	_, err = d.conn.Write(packet[:])
	return err
}

func (d *miniDisplayVU) release(_ bool) {
	if d.conn != nil {
		_ = d.send([30]byte{}, false)
		d.conn.Close()
		d.conn = nil
	}
	d.open = false
	d.history = miniVUHistory{}
}

func (d *miniDisplayVU) tick(now time.Time, active bool) {
	if !miniHardware || now.Before(d.next) {
		return
	}
	d.next = now.Add(35 * time.Millisecond)
	_, enabled := os.Stat("/tmp/capsula-mini-display-vu")
	if enabled != nil || miniBusy() || !active {
		d.release(false)
		return
	}
	fresh := false
	if st, err := os.Stat("/tmp/capsula-airplay-level"); err == nil {
		age := now.Sub(st.ModTime())
		fresh = age >= -time.Second && age < 350*time.Millisecond
	}
	if !fresh {
		d.release(false)
		return
	}
	if !d.open {
		if err := d.acquire(); err != nil {
			d.next = now.Add(time.Second)
			return
		}
	}
	if err := d.send(d.history.frame(now, beatEnvelope), true); err != nil {
		d.release(false)
		d.next = now.Add(time.Second)
	}
}
