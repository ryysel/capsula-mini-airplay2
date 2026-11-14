// Experimental Capsula 2019 companion. Artwork comes only from the sender.
// SPDX-License-Identifier: MIT
package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"fmt"
	_ "golang.org/x/image/tiff"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"log"
	"math"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const controlSocket = "/tmp/capsula-airplay-control.sock"
const framePath = "/tmp/capsula-airplay-frame"
const metadataPath = "/tmp/capsula-airplay-metadata"
const coverDir = "/tmp/capsula-airplay-covers"

// A new cover must survive 200 ms before it is painted, which drops the mixed
// PICT items some senders push while the artwork is being negotiated.
const coverAdoptDelay = 200 * time.Millisecond
const coverMaxAge = 10 * time.Minute

type rgb [3]float64
type companion struct {
	sync.Mutex
	palette     []rgb
	cover       string
	touch       bool
	released    time.Time
	latched     bool
	speechUntil time.Time
	active      bool
}

func control(cmd string) string {
	d := net.Dialer{Timeout: 250 * time.Millisecond}
	conn, err := d.Dial("unixpacket", controlSocket)
	if err != nil {
		return "idle"
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(500 * time.Millisecond))
	if _, err = conn.Write([]byte(cmd)); err != nil {
		return "idle"
	}
	b := make([]byte, 32)
	n, err := conn.Read(b)
	if err != nil {
		return "idle"
	}
	return string(b[:n])
}

// Artwork colours are chosen by chroma, never by area alone: a pale sky or a
// black logo must not outvote the actual palette of the cover. Thresholds
// mirror the Alice receiver (neutral below 15% saturation, dark below 6%).
const (
	coverMinSaturation  = .15
	coverSaturationGain = 1.3
	coverMinPeak        = .55
	coverMaxPeak        = .95
)

// Quantized RGB clusters preserve distinct colours, unlike averaging a whole
// cover into a muddy hue.
func palette(data []byte) ([]rgb, error) {
	if len(data) == 0 || len(data) > 4<<20 {
		return nil, fmt.Errorf("artwork size")
	}
	cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	if cfg.Width <= 0 || cfg.Height <= 0 || int64(cfg.Width)*int64(cfg.Height) > 4<<20 {
		return nil, fmt.Errorf("artwork dimensions")
	}
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	type bin struct {
		sum    rgb
		weight float64
	}
	bins := map[int]*bin{}
	var mean rgb
	var samples, chroma int
	dx, dy := max(1, cfg.Width/64), max(1, cfg.Height/64)
	for y := 0; y < cfg.Height; y += dy {
		for x := 0; x < cfg.Width; x += dx {
			r, g, b, _ := img.At(img.Bounds().Min.X+x, img.Bounds().Min.Y+y).RGBA()
			c := rgb{float64(r) / 65535, float64(g) / 65535, float64(b) / 65535}
			hi := max(c[0], max(c[1], c[2]))
			if hi < .06 {
				continue // shadows and letterbox bars carry no hue
			}
			samples++
			for k := 0; k < 3; k++ {
				mean[k] += c[k]
			}
			s := (hi - min(c[0], min(c[1], c[2]))) / hi
			if s < coverMinSaturation {
				continue
			}
			chroma++
			key := (int(c[0]*7) << 6) | (int(c[1]*7) << 3) | int(c[2]*7)
			if bins[key] == nil {
				bins[key] = &bin{}
			}
			w := s * s * hi
			v := bins[key]
			v.weight += w
			for k := 0; k < 3; k++ {
				v.sum[k] += c[k] * w
			}
		}
	}
	if samples == 0 {
		return []rgb{{.03, .03, .03}}, nil
	}
	// A monochrome cover has no hue to paint; show its mean as dim grey so the
	// ring still follows the cover's light level without pretending it is white.
	if len(bins) == 0 || float64(chroma)/float64(samples) < .03 {
		v := (mean[0] + mean[1] + mean[2]) / float64(3*samples)
		v = min(.30, max(.04, v*.6))
		return []rgb{{v, v, v}}, nil
	}
	var out []rgb
	for len(out) < 3 {
		best, top := -1, -1.0
		for key, v := range bins {
			if v.weight > top || (v.weight == top && key < best) {
				best, top = key, v.weight
			}
		}
		if best < 0 {
			break
		}
		v := bins[best]
		c := v.sum
		for k := 0; k < 3; k++ {
			c[k] /= v.weight
		}
		delete(bins, best)
		// Compare what is actually painted: two different mid-tones can boost
		// and normalise into the same colour, and a repeated band wastes a slot.
		c = coverColour(c)
		distinct := true
		for _, a := range out {
			d := 0.0
			for k := 0; k < 3; k++ {
				d += (a[k] - c[k]) * (a[k] - c[k])
			}
			if d < .10 {
				distinct = false
			}
		}
		if !distinct {
			continue
		}
		out = append(out, c)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("artwork has no colour")
	}
	return out, nil
}

// coverColour raises saturation with the HSV value fixed, then lifts only what
// is too dark to read on the ring. A bright cover keeps its own light level, so
// the palette stays faithful instead of turning every colour equally neon.
func coverColour(c rgb) rgb {
	hi := max(c[0], max(c[1], c[2]))
	if hi <= 0 {
		return c
	}
	if (hi-min(c[0], min(c[1], c[2])))/hi >= coverMinSaturation {
		for k := 0; k < 3; k++ {
			c[k] = max(0, hi-(hi-c[k])*coverSaturationGain)
		}
	}
	peak := max(c[0], max(c[1], c[2]))
	target := min(coverMaxPeak, max(coverMinPeak, peak))
	if peak > 0 && peak != target {
		for k := 0; k < 3; k++ {
			c[k] *= target / peak
		}
	}
	return c
}

// sampleGradient walks the palette cyclically so several colours blend around
// the ring instead of meeting in hard seams.
func sampleGradient(p []rgb, pos float64) rgb {
	i, f := int(pos)%len(p), pos-math.Floor(pos)
	var out rgb
	for k := 0; k < 3; k++ {
		out[k] = p[i][k] + (p[(i+1)%len(p)][k]-p[i][k])*f
	}
	return out
}

// drain keeps the metadata FIFO empty: shairport blocks on a full pipe, and a
// partial PICT is not worth decoding when the same cover is already cached.
func (c *companion) drain(ctx context.Context) {
	if err := syscall.Mkfifo(metadataPath, 0600); err != nil && err != syscall.EEXIST {
		log.Print("metadata FIFO: ", err)
		return
	}
	st, err := os.Lstat(metadataPath)
	if err != nil || st.Mode()&os.ModeNamedPipe == 0 {
		log.Print("metadata path is not a FIFO")
		return
	}
	f, err := os.OpenFile(metadataPath, os.O_RDWR, 0)
	if err != nil {
		log.Print(err)
		return
	}
	defer f.Close()
	go func() { <-ctx.Done(); f.Close() }()
	buf := make([]byte, 64<<10)
	for {
		if _, err := f.Read(buf); err != nil {
			return
		}
	}
}

// covers adopts the newest cached artwork once it has been stable for a moment.
// Some senders push several PICT items per track and some are clipped, so the
// file shairport actually decoded is the honest source.
// covers adopts the newest cached artwork once it has been stable for a moment.
// Some senders push several PICT items per track and some are clipped, so the
// file shairport actually decoded is the honest source.
func (c *companion) covers(ctx context.Context) {
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	var pending string
	var since time.Time
	var rejected string
	var rejectedAt time.Time
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-ticker.C:
			newest, newestAt := newestCover()
			if newest == "" || now.Sub(newestAt) > coverMaxAge {
				continue
			}
			if newest == rejected && newestAt.Equal(rejectedAt) {
				continue
			}
			if newest != pending {
				pending, since = newest, now
				continue
			}
			if now.Sub(since) < coverAdoptDelay {
				continue
			}
			c.Lock()
			seen := c.cover == newest
			c.Unlock()
			if seen {
				continue
			}
			data, err := readCover(newest)
			var p []rgb
			if err == nil {
				p, err = palette(data)
			}
			if err != nil {
				log.Print("artwork rejected: ", err)
				rejected, rejectedAt = newest, newestAt
				continue
			}
			c.Lock()
			c.cover, c.palette = newest, p
			c.Unlock()
			log.Printf("artwork: %d colours (%s)", len(p), filepath.Base(newest))
		}
	}
}

func newestCover() (string, time.Time) {
	entries, err := os.ReadDir(coverDir)
	if err != nil {
		return "", time.Time{}
	}
	var newest string
	var newestAt time.Time
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		if info.ModTime().After(newestAt) {
			newest, newestAt = filepath.Join(coverDir, e.Name()), info.ModTime()
		}
	}
	return newest, newestAt
}

func readCover(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, (4<<20)+1))
	if err != nil {
		return nil, err
	}
	if len(data) > 4<<20 {
		return nil, fmt.Errorf("artwork too large")
	}
	return data, nil
}
func (c *companion) input(ctx context.Context) {
	f, err := os.Open("/dev/input/event0")
	if err != nil {
		log.Print(err)
		return
	}
	defer f.Close()
	go func() { <-ctx.Done(); f.Close() }()
	b := make([]byte, 24)
	for {
		if _, err := io.ReadFull(f, b); err != nil {
			return
		}
		typ, code, value := binary.LittleEndian.Uint16(b[16:]), binary.LittleEndian.Uint16(b[18:]), int32(binary.LittleEndian.Uint32(b[20:]))
		if typ == 1 && code == 330 {
			c.Lock()
			c.touch = value != 0
			if !c.touch {
				c.released = time.Now()
			}
			c.Unlock()
		}
		if typ == 0 && code == 3 { // SYN_DROPPED: wait for a fresh release, do not trigger.
			c.Lock()
			c.latched = true
			c.touch = true
			c.Unlock()
		}
	}
}
func (c *companion) logs(ctx context.Context) {
	followStock(ctx, func(line string) {
		c.Lock()
		if strings.Contains(line, "=> PHRASE_IN_PROGRESS") ||
			strings.Contains(line, "SPEECH: start") {
			c.speechUntil = time.Now().Add(2 * time.Second)
		}
		if strings.Contains(line, "onSpeechPlaybackFinished") ||
			strings.Contains(line, "SPEECH: stop") ||
			strings.Contains(line, "=> WAITING_FOR_KEYWORD") {
			c.speechUntil = time.Time{}
		}
		toggle := strings.Contains(line, "[purr.cpp:") &&
			strings.Contains(line, "PURR:") && c.active && !c.latched &&
			time.Now().After(c.speechUntil)
		if toggle {
			c.latched = true
		}
		c.Unlock()
		if toggle {
			log.Print("palm toggle: ", control("toggle"))
		}
	})
}

// The stock purr confirms the palm gesture. While AirPlay is playing the same
// gesture is pause/resume, so the purr must not talk over the music.
func purrMute(mute bool) error {
	target := "0"
	if mute {
		target = "1"
	}
	out, err := exec.Command("/usr/bin/pactl", "set-sink-mute", "purr", target).CombinedOutput()
	if err != nil {
		return fmt.Errorf("purr mute: %v %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}
func uptime() float64 {
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return 0
	}
	fields := strings.Fields(string(data))
	if len(fields) == 0 {
		return 0
	}
	v, _ := strconv.ParseFloat(fields[0], 64)
	return v
}
func brightness(hour int) float64 {
	if hour >= 8 && hour < 20 {
		return 1
	}
	if hour >= 20 && hour < 23 {
		return .7
	}
	return .3
}
func writeBrokerFrame(colors [12]rgb, scale float64) {
	var b strings.Builder
	fmt.Fprintf(&b, "%.3f\n", uptime()+1.5)
	for _, color := range colors {
		fmt.Fprintf(&b, "%d %d %d\n", int(color[0]*200*scale), int(color[1]*200*scale), int(color[2]*200*scale))
	}
	if os.WriteFile(framePath+".new", []byte(b.String()), 0600) == nil {
		os.Rename(framePath+".new", framePath)
	}
}
func main() {
	if len(os.Args) == 3 && os.Args[1] == "--control" {
		fmt.Println(control(os.Args[2]))
		return
	}
	if len(os.Args) == 3 && os.Args[1] == "--purr-mute" {
		if err := purrMute(os.Args[2] == "on"); err != nil {
			log.Fatal(err)
		}
		fmt.Println("purr", os.Args[2])
		return
	}
	if len(os.Args) == 3 && os.Args[1] == "--palette" {
		data, err := os.ReadFile(os.Args[2])
		if err != nil {
			log.Fatal(err)
		}
		p, err := palette(data)
		if err != nil {
			log.Fatal(err)
		}
		for _, c := range p {
			fmt.Printf("%d %d %d\n", int(c[0]*255), int(c[1]*255), int(c[2]*255))
		}
		return
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	log.SetPrefix("capsula-ui: ")
	c := &companion{}
	panelRestore()
	go servePanel()
	go panelSaveLoop(ctx)
	go c.drain(ctx)
	go c.covers(ctx)
	if !miniHardware {
		go c.input(ctx)
	} else {
		go c.miniLogs(ctx)
	}
	if !miniHardware {
		go c.logs(ctx)
	}
	defer os.Remove(framePath)
	defer closeMini()
	defer panelFlush()
	tick := time.NewTicker(40 * time.Millisecond)
	defer tick.Stop()
	var shown [12]rgb
	var old [12]rgb
	var target [12]rgb
	var fade time.Time
	signature := ""
	active := false
	poll := time.Time{}
	purrSilent := false
	if !miniHardware {
		if err := purrMute(false); err != nil {
			log.Print(err)
		}
	}
	if !miniHardware {
		defer purrMute(false)
	}
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-tick.C:
			cfg := panelSnapshot()
			// A 250 ms tick matches the measured station profile: the palm gesture and
			// the session state trail Alice by at most one tick instead of two.
			if now.Sub(poll) >= 250*time.Millisecond {
				active = control("state") == "active"
				// The purr announces the stock gesture; during a session the gesture is
				// pause/resume, so the purr must stay silent until the session ends.
				if !miniHardware && active != purrSilent {
					if err := purrMute(active); err != nil {
						log.Print(err)
					} else {
						purrSilent = active
					}
				}
				poll = now
			}
			c.Lock()
			c.active = active
			if !c.touch && now.Sub(c.released) > 1200*time.Millisecond {
				c.latched = false
			}
			p := append([]rgb(nil), c.palette...)
			c.Unlock()
			panelSetStatus(active, p)

			// Manual test ignores session state and beat so the edited colours are
			// exactly what the ring shows; saved channel gain still applies.
			if cfg.Mode == "test" {
				var cols [12]rgb
				scale := cfg.Brightness
				if !cfg.Blank {
					for i := range cols {
						for k := 0; k < 3; k++ {
							cols[i][k] = float64(cfg.Pixels[i][k]) / 255
						}
					}
				} else {
					scale = 0 // true off, not the calibrated black point
				}
				outputFrame(cols, scale)
				signature = ""
				continue
			}
			if !active {
				os.Remove(framePath)
				if miniHardware {
					clearMini()
				}
				panelRecord([12]rgb{}, 1)
				signature = ""
				continue
			}
			if len(p) == 0 {
				// No artwork (a black cover or none): the black point of the
				// correction table decides what the ring shows.
				p = []rgb{{0, 0, 0}}
			}
			s := fmt.Sprint(p)
			if s != signature {
				old = shown
				fade = now
				signature = s
			}
			for i := range target {
				target[i] = saturateColour(
					sampleGradient(p, float64(i)*float64(len(p))/12),
					cfg.Saturation)
			}
			fadeSeconds := math.Max(.05, float64(cfg.FadeMS)/1000)
			t := math.Min(1, now.Sub(fade).Seconds()/fadeSeconds)
			t = t * t * (3 - 2*t)
			for i := range shown {
				for k := 0; k < 3; k++ {
					shown[i][k] = old[i][k] + (target[i][k]-old[i][k])*t
				}
			}
			scale := brightness(now.Hour()) * beatScale(now, cfg.Pulse) * cfg.Brightness
			outputFrame(shown, scale)
		}
	}
}
