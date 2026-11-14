// SPDX-License-Identifier: MIT
package main

import (
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
func beatScale(now time.Time) float64 {
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
	return .25 + .75*beatEnvelope
}

var miniFile *os.File
var miniPainted bool
var miniLock sync.Mutex
var miniQuiet time.Time
var miniSpeaking bool

func miniBusy() bool {
	miniLock.Lock()
	defer miniLock.Unlock()
	return miniSpeaking || time.Now().Before(miniQuiet)
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
	req := struct {
		Start uint32
		Count uint32
		Data  uintptr
	}{0, 36, uintptr(unsafe.Pointer(&data[0]))}
	syscall.Syscall(syscall.SYS_IOCTL, miniFile.Fd(), 0x40107a01, uintptr(unsafe.Pointer(&req)))
	runtime.KeepAlive(data)
	miniPainted = true
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
func (c *companion) miniLogs(ctx context.Context) {
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	var last string
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		c.Lock()
		active := c.active
		c.Unlock()
		if !active {
			last = ""
			continue
		}
		raw, err := exec.CommandContext(ctx, "logread").Output()
		if err != nil {
			continue
		}
		newest := ""
		busy := false
		for _, line := range strings.Split(string(raw), "\n") {
			if strings.Contains(line, "OnVolumeChangedEvent:") {
				newest = line
			}
			if strings.Contains(line, "=> PHRASE_IN_PROGRESS") || strings.Contains(line, "SPEECH: start") {
				busy = true
			}
			if strings.Contains(line, "onSpeechPlaybackFinished") || strings.Contains(line, "=> WAITING_FOR_KEYWORD") {
				busy = false
			}
		}
		miniLock.Lock()
		miniSpeaking = busy
		if last != "" && newest != "" && newest != last {
			miniQuiet = time.Now().Add(1800 * time.Millisecond)
		}
		miniLock.Unlock()
		last = newest
	}
}
