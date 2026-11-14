// SPDX-License-Identifier: MIT
package main

import (
	"bufio"
	"context"
	"fmt"
	"math"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var miniHardware = func() bool { _, err := os.Stat("/dev/topleds"); return err == nil }()

// Envelope is calculated from outgoing PCM by the receiver, before volume.
// Ignore stale samples on pause; there is no fabricated periodic "beat".
var beatReference = 0.06
var beatEnvelope float64
var beatLast time.Time

func envelopeStep(rms, reference, envelope, dt float64) (float64, float64) {
	reference = math.Max(.025, math.Max(rms, reference*math.Exp(-dt/6)))
	target := math.Pow(math.Min(1, math.Max(0, rms)/reference), .65)
	tau := .16
	if target > envelope {
		tau = .015
	}
	envelope += (target - envelope) * (1 - math.Exp(-dt/tau))
	return reference, envelope
}
func beatScale(now time.Time, depth float64) float64 {
	dt := now.Sub(beatLast).Seconds()
	if beatLast.IsZero() || dt > 1 {
		dt = .04
	}
	beatLast = now
	rms := 0.0
	if st, err := os.Stat("/tmp/capsula-airplay-level"); err == nil && now.Sub(st.ModTime()) < 350*time.Millisecond {
		if b, err := os.ReadFile("/tmp/capsula-airplay-level"); err == nil {
			fmt.Sscanf(string(b), "%f", &rms)
		}
	}
	if math.IsNaN(rms) || math.IsInf(rms, 0) {
		rms = 0
	}
	beatReference, beatEnvelope = envelopeStep(rms, beatReference, beatEnvelope, dt)
	panelSetLevel(beatEnvelope)
	return (1 - depth) + depth*beatEnvelope
}

var miniFile *os.File
var miniPainted bool
var miniLock sync.Mutex
var miniQuiet time.Time
var miniSpeaking bool
var miniSpeechAt time.Time

type miniLedRequest struct {
	Start uint32
	Count uint32
	Data  *byte
}

func miniBusy() bool {
	miniLock.Lock()
	defer miniLock.Unlock()
	return (miniSpeaking && time.Since(miniSpeechAt) < 45*time.Second) || time.Now().Before(miniQuiet)
}
func paintMini(colors [12]rgb, scale float64) {
	if miniBusy() {
		miniPainted = false
		return
	}
	if miniFile == nil {
		f, err := os.OpenFile("/dev/topleds", os.O_RDWR, 0)
		if err != nil {
			return
		}
		miniFile = f
	}
	mapping := [36]int{1, 0, 2, 34, 33, 35, 31, 30, 32, 28, 27, 29, 25, 24, 26, 22, 21, 23, 19, 18, 20, 16, 15, 17, 13, 12, 14, 10, 9, 11, 7, 6, 8, 4, 3, 5}
	var data [36]byte
	for i := 0; i < 12; i++ {
		for k := 0; k < 3; k++ {
			data[mapping[i*3+k]] = byte(math.Min(255, math.Max(0, colors[i][k]*160*scale)))
		}
	}
	req := miniLedRequest{0, 36, &data[0]}
	syscall.Syscall(syscall.SYS_IOCTL, miniFile.Fd(), 0x40107a01, uintptr(unsafe.Pointer(&req)))
	runtime.KeepAlive(data)
	miniPainted = true
}
func applyGain(colors [12]rgb, cfg panelConfig) [12]rgb {
	out := colors
	for i := range out {
		for k := 0; k < 3; k++ {
			out[i][k] = math.Min(1, math.Max(0, out[i][k]*cfg.Gain[k]))
		}
	}
	return out
}

func saturateColour(c rgb, s float64) rgb {
	if s == 1 {
		return c
	}
	l := .2126*c[0] + .7152*c[1] + .0722*c[2]
	for k := 0; k < 3; k++ {
		c[k] = math.Min(1, math.Max(0, l+(c[k]-l)*s))
	}
	return c
}

// outputFrame applies the saved channel calibration, writes the ring and
// records the visible colours for the panel preview.
func outputFrame(colors [12]rgb, scale float64) {
	cfg := panelSnapshot()
	cols := applyGain(colors, cfg)
	if miniHardware {
		paintMini(cols, scale)
	} else {
		writeBrokerFrame(cols, scale)
	}
	panelRecord(cols, scale)
}

func clearMini() {
	if !miniPainted || miniBusy() {
		return
	}
	paintMini([12]rgb{}, 0)
	miniPainted = false
}
func closeMini() {
	if !miniHardware {
		return
	}
	clearMini()
	if miniFile != nil {
		miniFile.Close()
		miniFile = nil
	}
}

// Leave native volume/numeric-display animations alone, and yield during speech.
// Parse only state markers; never copy stock logs (which can contain tokens).
// One bounded streaming reader replaces two repeated 4-MiB log snapshots.
// Never print stock lines: they may contain credentials.
func (c *companion) miniLogs(ctx context.Context) {
	for ctx.Err() == nil {
		cmd := exec.CommandContext(ctx, "logread", "-f")
		out, err := cmd.StdoutPipe()
		if err != nil {
			return
		}
		if err = cmd.Start(); err != nil {
			return
		}
		scan := bufio.NewScanner(out)
		scan.Buffer(make([]byte, 4096), 65536)
		for scan.Scan() {
			line := scan.Text()
			volume := strings.Contains(line, "OnVolumeChangedEvent:")
			start := strings.Contains(line, "=> PHRASE_IN_PROGRESS") || strings.Contains(line, "SPEECH: start")
			done := strings.Contains(line, "onSpeechPlaybackFinished") || strings.Contains(line, "=> WAITING_FOR_KEYWORD")
			if !volume && !start && !done {
				continue
			}
			miniLock.Lock()
			if volume {
				miniQuiet = time.Now().Add(1800 * time.Millisecond)
			}
			if start {
				miniSpeaking = true
				miniSpeechAt = time.Now()
			}
			if done {
				miniSpeaking = false
			}
			miniLock.Unlock()
		}
		if ctx.Err() == nil && cmd.Process != nil {
			cmd.Process.Kill()
		}
		cmd.Wait()
		select {
		case <-ctx.Done():
			return
		case <-time.After(time.Second):
		}
	}
}
