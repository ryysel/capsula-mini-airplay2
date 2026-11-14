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

type panelConfig struct {
	Mode       string     `json:"mode"` // "auto" or "test"
	Brightness float64    `json:"brightness"`
	Gain       [3]float64 `json:"gain"`
	Saturation float64    `json:"saturation"`
	Pulse      float64    `json:"pulse"`
	FadeMS     int        `json:"fadeMs"`
	Pixels     [][3]int   `json:"pixels"`
}

var (
	panelMu      sync.Mutex
	panelCfg     = defaultPanel()
	panelLive    [12][3]int
	panelActive  bool
	panelPalette [][3]int
	panelLevel   float64
	panelDirty   bool
)

func defaultPanel() panelConfig {
	p := panelConfig{Mode: "auto", Brightness: 1, Gain: [3]float64{1, 1, 1},
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
	for k := 0; k < 3; k++ {
		p.Gain[k] = clampf(p.Gain[k], .5, 1.5)
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
	if data, err := os.ReadFile(panelPath); err == nil {
		var c panelConfig
		if json.Unmarshal(data, &c) == nil {
			panelMu.Lock()
			panelCfg = c
			panelMu.Unlock()
		}
	}
	panelMu.Lock()
	panelCfg.sanitize()
	panelCfg.Mode = "auto"
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
	if os.WriteFile(tmp, b, 0644) == nil {
		os.Rename(tmp, panelPath)
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
		r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
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
