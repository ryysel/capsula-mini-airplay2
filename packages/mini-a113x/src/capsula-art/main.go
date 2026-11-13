// Album-art colours on the VK Capsula Mini ring while an AirPlay session is
// live. The stock capsule-tweaker stays the ring owner: this daemon paints
// only when a cover is known, yields to the assistant and to the volume
// overlay, and stops as soon as the session ends.
// SPDX-License-Identifier: MIT
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"log"
	"math"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	_ "golang.org/x/image/tiff"
)

type rgb [3]float64

const (
	ringCount = 12

	bridgeStatePath = "/run/ap2-bridge.state"
	phoneVolumePath = "/run/ap2-volume.phone"
	tweakerConfPath = "/etc/capsule-tweaker.conf"
	ringledPath     = "/usr/local/bin/ringled"
	brokerStateURL  = "http://127.0.0.1:8100/api/ring/state"

	defaultCoverDir = "/tmp/shairport-sync-covers"
	defaultBright   = 50
)

// A new cover must survive 200 ms before it is painted, which drops the mixed
// PICT items some senders push while the artwork is being negotiated.
const coverAdoptDelay = 200 * time.Millisecond
const coverMaxAge = 10 * time.Minute

// Painting cadence: a static frame costs about 50 ms of SPI work, so 400 ms is
// fast enough to follow a track change and cheap enough to leave the CPU free.
const paintInterval = 400 * time.Millisecond
const fadeDuration = 300 * time.Millisecond

// The stock volume overlay must be readable, so artwork waits after a change.
const volumeQuiet = 2 * time.Second

type artwork struct {
	mu      sync.Mutex
	palette []rgb
	cover   string
}

func (a *artwork) snapshot() []rgb {
	a.mu.Lock()
	defer a.mu.Unlock()
	return append([]rgb(nil), a.palette...)
}

func main() {
	coverDir := envOr("CAPSULA_ART_COVERS", defaultCoverDir)
	brightness := ringBrightness(envOr("CAPSULA_ART_CONF", tweakerConfPath))
	switch {
	case len(os.Args) == 3 && os.Args[1] == "--palette":
		data, err := os.ReadFile(os.Args[2])
		if err != nil {
			log.Fatal(err)
		}
		p, err := palette(data)
		if err != nil {
			log.Fatal(err)
		}
		for _, c := range p {
			fmt.Printf("%02X%02X%02X\n", int(c[0]*255), int(c[1]*255), int(c[2]*255))
		}
		return
	case len(os.Args) == 3 && os.Args[1] == "--paint":
		colors, err := parseColours(os.Args[2])
		if err != nil {
			log.Fatal(err)
		}
		if err := paint(colors, brightness); err != nil {
			log.Fatal(err)
		}
		fmt.Println("painted")
		return
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	log.SetPrefix("capsula-art: ")

	a := &artwork{}
	go a.covers(ctx, coverDir)
	go drainPipe(ctx, envOr("CAPSULA_ART_PIPE", "/tmp/shairport-sync-metadata"))
	run(ctx, a, brightness)
}

// drainPipe keeps shairport's metadata queue empty. Covers are read from the
// cache directory, but a full pipe would eventually stall the metadata thread.
// O_RDWR keeps a reader present and blocks in Read instead of spinning.
func drainPipe(ctx context.Context, path string) {
	buf := make([]byte, 32<<10)
	for ctx.Err() == nil {
		f, err := os.OpenFile(path, os.O_RDWR, 0)
		if err != nil {
			time.Sleep(time.Second)
			continue
		}
		for ctx.Err() == nil {
			if _, err := f.Read(buf); err != nil {
				break
			}
		}
		f.Close()
	}
}

func run(ctx context.Context, a *artwork, brightness int) {
	var shown, old, target [12]rgb
	var signature string
	var fade time.Time
	var lastPaint time.Time
	var quietUntil time.Time
	var lastMaster, lastPhone string
	assistantBusy := false
	painted := false
	initialized := false
	wasActive := false

	tick := time.NewTicker(100 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-tick.C:
			active, master := session()
			if !active {
				if wasActive && painted {
					// The bridge repaints the stock idle state, but a frame of
					// ours may land right after it. Ask for one more repaint so
					// the ring never stays tinted by a finished session.
					exec.Command("/usr/local/bin/capsule-ipc", "AP2 0").Run()
				}
				wasActive, painted = false, false
				signature = ""
				lastPaint = time.Time{}
				continue
			}
			wasActive = true
			phone := phoneMark()
			switch {
			case !initialized:
				// The first tick must not look like a volume change, otherwise
				// the artwork waits two seconds every time the daemon starts.
				lastMaster, lastPhone, initialized = master, phone, true
			case master != lastMaster || phone != lastPhone:
				quietUntil = now.Add(volumeQuiet)
				lastMaster, lastPhone = master, phone
			}
			busy := !assistantIdle()
			if busy != assistantBusy {
				log.Printf("assistant %s", map[bool]string{true: "busy, art paused", false: "idle"}[busy])
				assistantBusy = busy
			}
			if busy || now.Before(quietUntil) {
				continue
			}
			p := a.snapshot()
			if len(p) == 0 {
				continue
			}
			key := fmt.Sprint(p)
			if key != signature {
				old = shown
				for i := range target {
					target[i] = sampleGradient(p, float64(i)*float64(len(p))/ringCount)
				}
				fade, signature = now, key
			}
			t := math.Min(1, now.Sub(fade).Seconds()/fadeDuration.Seconds())
			t = t * t * (3 - 2*t)
			for i := range shown {
				for k := 0; k < 3; k++ {
					shown[i][k] = old[i][k] + (target[i][k]-old[i][k])*t
				}
			}
			if now.Sub(lastPaint) < paintInterval {
				continue
			}
			if err := paint(shown, brightness); err != nil {
				log.Print(err)
				continue
			}
			lastPaint = now
			if !painted {
				log.Printf("artwork on the ring (%s %s %s ...)", hex(target[0]), hex(target[ringCount/3]), hex(target[2*ringCount/3]))
				painted = true
			}
		}
	}
}

// session reports whether a sender is connected and returns the speaker's own
// level, which the stock bridge rewrites on every volume change.
func session() (bool, string) {
	data, err := os.ReadFile(bridgeStatePath)
	if err != nil {
		return false, ""
	}
	fields := strings.Fields(string(data))
	if len(fields) < 2 {
		return false, ""
	}
	return fields[0] == "1", fields[1]
}

// assistantIdle is true while the stock ring shows nothing of its own. The
// broker's HTTP state is preferred; the file is a fallback for a busy broker.
func assistantIdle() bool {
	client := http.Client{Timeout: 400 * time.Millisecond}
	resp, err := client.Get(brokerStateURL)
	if err == nil {
		defer resp.Body.Close()
		var v struct {
			State string `json:"state"`
		}
		if json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&v) == nil {
			switch v.State {
			case "", "idle", "error", "disconnected":
				return true
			default:
				return false
			}
		}
	}
	return true
}

// phoneMark changes when the sender pushes a new volume, so the artwork can
// step aside for the stock overlay.
func phoneMark() string {
	st, err := os.Stat(phoneVolumePath)
	if err != nil {
		return "0"
	}
	return strconv.FormatInt(st.ModTime().UnixNano(), 10)
}

func paint(colors [12]rgb, brightness int) error {
	args := []string{"-b", strconv.Itoa(brightness), "raw"}
	args = append(args, colourHex(colors, ringCount)...)
	cmd := exec.Command(ringledPath, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("ringled: %v: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}

func colourHex(colors [12]rgb, n int) []string {
	out := make([]string, 0, n)
	for _, c := range colors {
		out = append(out, hex(c))
	}
	return out
}

func hex(c rgb) string {
	return fmt.Sprintf("%02X%02X%02X", clamp8(c[0]*255), clamp8(c[1]*255), clamp8(c[2]*255))
}

func clamp8(v float64) int {
	if v <= 0 {
		return 0
	}
	if v >= 255 {
		return 255
	}
	return int(v)
}

func parseColours(text string) ([12]rgb, error) {
	var colors [12]rgb
	parts := strings.Split(text, ",")
	for i := range colors {
		field := strings.TrimPrefix(strings.TrimSpace(parts[i%len(parts)]), "#")
		if len(field) != 6 {
			return colors, fmt.Errorf("colour %q is not RRGGBB", field)
		}
		v, err := strconv.ParseUint(field, 16, 32)
		if err != nil {
			return colors, fmt.Errorf("colour %q: %w", field, err)
		}
		colors[i] = rgb{
			float64(v>>16&0xFF) / 255,
			float64(v>>8&0xFF) / 255,
			float64(v&0xFF) / 255,
		}
	}
	return colors, nil
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

// ringBrightness follows the stock ring setting so artwork does not jump out
// brighter than the indication around it.
func ringBrightness(path string) int {
	data, err := os.ReadFile(path)
	if err != nil {
		return defaultBright
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "ring_brightness=") {
			continue
		}
		n, err := strconv.Atoi(strings.TrimPrefix(line, "ring_brightness="))
		if err == nil && n > 0 && n <= 100 {
			return n
		}
	}
	return defaultBright
}

func (a *artwork) covers(ctx context.Context, dir string) {
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
			newest, newestAt := newestCover(dir)
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
			a.mu.Lock()
			seen := a.cover == newest
			a.mu.Unlock()
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
			a.mu.Lock()
			a.cover, a.palette = newest, p
			a.mu.Unlock()
			log.Printf("artwork: %d colours (%s)", len(p), filepath.Base(newest))
		}
	}
}

func newestCover(dir string) (string, time.Time) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return "", time.Time{}
	}
	type candidate struct {
		path string
		mod  time.Time
	}
	var found []candidate
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		found = append(found, candidate{filepath.Join(dir, e.Name()), info.ModTime()})
	}
	if len(found) == 0 {
		return "", time.Time{}
	}
	sort.Slice(found, func(i, j int) bool { return found[i].mod.After(found[j].mod) })
	return found[0].path, found[0].mod
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
