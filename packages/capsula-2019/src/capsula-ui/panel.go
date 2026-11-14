// SPDX-License-Identifier: MIT
package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"log"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// The panel is served by the renderer itself: it already owns the LED output,
// so edits appear on the ring without a second writer. No credentials, no
// filesystem access; only ring colours and renderer tuning.

//go:embed panel.html
var panelPage []byte

const (
	panelPath = "/data/local/capsula-airplay/panel.json"
	panelAddr = ":8088"
)

// A 3x3x3 colour table: each axis has 0, 0.5 and 1. Every node stores the
// colour actually sent to the LEDs for that input. The eight basic points
// edited in the panel — R, G, B, Y, C, M, orange, W — are nodes of this table,
// and artwork colours are interpolated between them.
type panelConfig struct {
	Mode       string         `json:"mode"` // "auto" or "test"
	Brightness float64        `json:"brightness"`
	LUT        [27][3]float64 `json:"lut"`
	Saturation float64        `json:"saturation"`
	Pulse      float64        `json:"pulse"`
	FadeMS     int            `json:"fadeMs"`
	Pixels     [][3]int       `json:"pixels"`
	Blank      bool           `json:"blank"` // panel "off": bypass the table
}

var (
	panelMu      sync.Mutex
	panelCfg     = defaultPanel()
	panelLive    [12][3]int
	panelActive  bool
	panelPalette [][3]int
	panelLevel   float64
	panelDirty   bool
	panelSavedAt int64
)

func lutIndex(i, j, k int) int { return (i*3+j)*3 + k }

// defaultLUT is the identity table with a faint baseline at black: a black
// cover must still glow a little unless the owner tunes that point. The panel
// "off" action bypasses the table instead of relying on black.
func defaultLUT() [27][3]float64 {
	var l [27][3]float64
	for i := 0; i < 3; i++ {
		for j := 0; j < 3; j++ {
			for k := 0; k < 3; k++ {
				l[lutIndex(i, j, k)] = [3]float64{float64(i) / 2, float64(j) / 2, float64(k) / 2}
			}
		}
	}
	l[lutIndex(0, 0, 0)] = [3]float64{.06, .06, .06}
	return l
}

func defaultPanel() panelConfig {
	p := panelConfig{Mode: "auto", Brightness: 1, LUT: defaultLUT(),
		Saturation: 1, Pulse: .75, FadeMS: 300}
	p.Pixels = make([][3]int, 12)
	for i := range p.Pixels {
		p.Pixels[i] = [3]int{255, 255, 255}
	}
	return p
}

func clampf(v, lo, hi float64) float64 {
	if math.IsNaN(v) {
		return lo
	}
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func (p *panelConfig) sanitize() {
	if p.Mode != "test" {
		p.Mode = "auto"
	}
	p.Brightness = clampf(p.Brightness, .05, 1)
	zero := true
	for i := range p.LUT {
		for k := 0; k < 3; k++ {
			p.LUT[i][k] = clampf(p.LUT[i][k], 0, 1)
			if p.LUT[i][k] != 0 {
				zero = false
			}
		}
	}
	if zero { // a missing or empty table means identity
		p.LUT = defaultLUT()
	}
	p.Saturation = clampf(p.Saturation, 0, 1.5)
	p.Pulse = clampf(p.Pulse, 0, 1)
	if p.FadeMS < 0 {
		p.FadeMS = 0
	}
	if p.FadeMS > 1000 {
		p.FadeMS = 1000
	}
	if len(p.Pixels) != 12 {
		def := defaultPanel().Pixels
		for len(p.Pixels) < 12 {
			p.Pixels = append(p.Pixels, def[0])
		}
		p.Pixels = p.Pixels[:12]
	}
	for i := range p.Pixels {
		for k := 0; k < 3; k++ {
			if p.Pixels[i][k] < 0 {
				p.Pixels[i][k] = 0
			}
			if p.Pixels[i][k] > 255 {
				p.Pixels[i][k] = 255
			}
		}
	}
}

// lutFromMatrix migrates the earlier 3x3 primary matrix into node values.
func lutFromMatrix(m [3][3]float64) [27][3]float64 {
	var l [27][3]float64
	for i := 0; i < 3; i++ {
		for j := 0; j < 3; j++ {
			for k := 0; k < 3; k++ {
				in := [3]float64{float64(i) / 2, float64(j) / 2, float64(k) / 2}
				var out [3]float64
				for ch := 0; ch < 3; ch++ {
					out[ch] = m[0][ch]*in[0] + m[1][ch]*in[1] + m[2][ch]*in[2]
				}
				l[lutIndex(i, j, k)] = out
			}
		}
	}
	return l
}

func panelSnapshot() panelConfig {
	panelMu.Lock()
	defer panelMu.Unlock()
	c := panelCfg
	c.Pixels = append([][3]int(nil), panelCfg.Pixels...)
	return c
}

// panelRestore keeps the tuning but never boots into a manual frame: a stale
// test colour must not hide artwork after a reboot.
func panelRestore() {
	def := defaultPanel()
	c := def
	if raw, err := os.ReadFile(panelPath); err == nil {
		var in struct {
			Brightness *float64        `json:"brightness"`
			Saturation *float64        `json:"saturation"`
			Pulse      *float64        `json:"pulse"`
			FadeMS     *int            `json:"fadeMs"`
			Pixels     [][3]int        `json:"pixels"`
			LUT        *[27][3]float64 `json:"lut"`
			Primaries  *[3][3]float64  `json:"primaries"` // v1.5.2-dev panel files
			Gain       *[3]float64     `json:"gain"`      // v1.5.2-dev.1 file
		}
		if json.Unmarshal(raw, &in) == nil {
			if in.Brightness != nil {
				c.Brightness = *in.Brightness
			}
			if in.Saturation != nil {
				c.Saturation = *in.Saturation
			}
			if in.Pulse != nil {
				c.Pulse = *in.Pulse
			}
			if in.FadeMS != nil {
				c.FadeMS = *in.FadeMS
			}
			if len(in.Pixels) == 12 {
				c.Pixels = in.Pixels
			}
			switch {
			case in.LUT != nil:
				c.LUT = *in.LUT
			case in.Primaries != nil:
				c.LUT = lutFromMatrix(*in.Primaries)
			case in.Gain != nil:
				var m [3][3]float64
				for i := 0; i < 3; i++ {
					m[i][i] = in.Gain[i]
				}
				c.LUT = lutFromMatrix(m)
			}
		}
	}
	c.Mode = "auto"
	c.sanitize()
	panelMu.Lock()
	panelCfg = c
	panelMu.Unlock()
}

// Panel edits arrive continuously while a slider is dragged. Keep them in
// memory and write /data at most every two seconds to spare the flash.
func panelMarkDirty() {
	panelMu.Lock()
	panelDirty = true
	panelMu.Unlock()
}

func panelFlush() {
	panelMu.Lock()
	dirty := panelDirty
	panelDirty = false
	panelMu.Unlock()
	if dirty {
		panelSave()
	}
}

func panelSaveLoop(ctx context.Context) {
	t := time.NewTicker(2 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			panelFlush()
			return
		case <-t.C:
			panelFlush()
		}
	}
}

func panelSave() {
	c := panelSnapshot()
	b, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return
	}
	if os.MkdirAll(filepath.Dir(panelPath), 0755) != nil {
		return
	}
	tmp := panelPath + ".new"
	if os.WriteFile(tmp, b, 0644) == nil && os.Rename(tmp, panelPath) == nil {
		panelMu.Lock()
		panelSavedAt = time.Now().Unix()
		panelMu.Unlock()
	}
}

func panelSetLevel(v float64) {
	panelMu.Lock()
	panelLevel = clampf(v, 0, 1)
	panelMu.Unlock()
}

func panelSetStatus(active bool, palette []rgb) {
	list := make([][3]int, 0, len(palette))
	for _, c := range palette {
		list = append(list, [3]int{
			int(clampf(c[0], 0, 1)*255 + .5),
			int(clampf(c[1], 0, 1)*255 + .5),
			int(clampf(c[2], 0, 1)*255 + .5),
		})
	}
	panelMu.Lock()
	panelActive = active
	panelPalette = list
	panelMu.Unlock()
}

func panelRecord(cols [12]rgb, scale float64) {
	var live [12][3]int
	for i := range cols {
		for k := 0; k < 3; k++ {
			live[i][k] = int(clampf(cols[i][k]*scale, 0, 1)*255 + .5)
		}
	}
	panelMu.Lock()
	panelLive = live
	panelMu.Unlock()
}

type panelView struct {
	Config   panelConfig `json:"config"`
	Live     [12][3]int  `json:"live"`
	Active   bool        `json:"active"`
	Palette  [][3]int    `json:"palette"`
	Level    float64     `json:"level"`
	Hardware string      `json:"hardware"`
	SavedAt  int64       `json:"savedAt"`
}

func panelViewNow() panelView {
	v := panelView{Config: panelSnapshot(), Hardware: "2019"}
	if miniHardware {
		v.Hardware = "mini"
	}
	panelMu.Lock()
	v.Live = panelLive
	v.Active = panelActive
	v.Palette = append([][3]int(nil), panelPalette...)
	v.Level = panelLevel
	v.SavedAt = panelSavedAt
	panelMu.Unlock()
	return v
}

func panelWriteJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func panelHandleState(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		panelWriteJSON(w, 200, panelViewNow())
	case http.MethodPost:
		r.Body = http.MaxBytesReader(w, r.Body, 256<<10)
		var in panelConfig
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			panelWriteJSON(w, 400, map[string]string{"error": "bad json"})
			return
		}
		panelMu.Lock()
		if len(in.Pixels) == 0 {
			in.Pixels = append([][3]int(nil), panelCfg.Pixels...)
		}
		in.sanitize()
		panelCfg = in
		panelMu.Unlock()
		panelMarkDirty()
		panelWriteJSON(w, 200, panelViewNow())
	default:
		w.Header().Set("Allow", "GET, POST")
		panelWriteJSON(w, 405, map[string]string{"error": "method"})
	}
}

// panelHandleSave flushes the debounced write immediately, so the panel can
// show a definite "saved" moment even though edits also persist by themselves.
func panelHandleSave(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		panelWriteJSON(w, 405, map[string]string{"error": "method"})
		return
	}
	panelFlush()
	panelWriteJSON(w, 200, panelViewNow())
}

func panelHandleReset(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		panelWriteJSON(w, 405, map[string]string{"error": "method"})
		return
	}
	c := defaultPanel()
	panelMu.Lock()
	panelCfg = c
	panelMu.Unlock()
	panelMarkDirty()
	panelWriteJSON(w, 200, panelViewNow())
}

func panelHandlePage(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Write(panelPage)
}

// servePanel binds the LAN address. Port 80 is owned by the stock voice-agent
// on both capsules, so the panel uses 8088.
func servePanel() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", panelHandlePage)
	mux.HandleFunc("/api/state", panelHandleState)
	mux.HandleFunc("/api/reset", panelHandleReset)
	mux.HandleFunc("/api/save", panelHandleSave)
	srv := &http.Server{
		Addr:              panelAddr,
		Handler:           mux,
		ReadHeaderTimeout: 2 * time.Second,
		ReadTimeout:       3 * time.Second,
		WriteTimeout:      3 * time.Second,
		IdleTimeout:       30 * time.Second,
	}
	log.Printf("panel: http://0.0.0.0%s/", panelAddr)
	if err := srv.ListenAndServe(); err != nil {
		log.Print("panel: ", err)
	}
}
