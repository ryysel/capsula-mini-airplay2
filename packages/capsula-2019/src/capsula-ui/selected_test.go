package main

import (
	"testing"
	"time"
)

func TestSelectedBeforePCM(t *testing.T) {
	var s selectedOutput
	now := time.Now()
	s.update("selected:7", now, now.Add(-time.Second))
	if s.started || s.id == "" {
		t.Fatal("old meter on selection")
	}
	s.update("selected:7", now.Add(time.Second), now.Add(time.Millisecond))
	if !s.started {
		t.Fatal("new PCM ignored")
	}
	s.update("selected:8", now.Add(2*time.Second), now.Add(time.Millisecond))
	if s.started {
		t.Fatal("inherited old track")
	}
	s.update("idle", now.Add(3*time.Second), time.Time{})
	if s.id != "" {
		t.Fatal("not released")
	}
}
