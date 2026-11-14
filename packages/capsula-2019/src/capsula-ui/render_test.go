package main

import (
	"math"
	"testing"
)

func TestEnvelopeRespondsToPCM(t *testing.T) {
	ref, env := .1, 0.0
	ref, env = envelopeStep(.1, ref, env, .04)
	if env < .8 {
		t.Fatalf("attack too slow %g", env)
	}
	for i := 0; i < 30; i++ {
		ref, env = envelopeStep(0, ref, env, .04)
	}
	if env > .001 {
		t.Fatalf("pause did not fade: %g", env)
	}
	if math.IsNaN(env) {
		t.Fatal("invalid envelope")
	}
}

func TestMiniRequestPointerIsGCTracked(t *testing.T) {
	var data [36]byte
	r := miniLedRequest{0, 36, &data[0]}
	*r.Data = 91
	if data[0] != 91 || r.Count != 36 {
		t.Fatal("bad ioctl request")
	}
}
