/* Capsula 2019 fast-audio startup gate. SPDX-License-Identifier: MIT */
#ifndef CAPSULA_STARTUP_GATE_H
#define CAPSULA_STARTUP_GATE_H
#include <math.h>
#include <stdint.h>

typedef struct {
  int prepared;
  uint32_t ssrc;
} capsula_startup_preparation;

static int capsula_startup_gate_enabled(int ap2, int pulseaudio, double offset) {
  return ap2 && pulseaudio && isfinite(offset) && offset < 0;
}

/* Bound cold-start silence by PA's 100 ms tlength and the player's budget.
 * Requiring the whole budget could starve a low-latency realtime stream.
 * This does not alter the negotiated anchor/offset. */
static uint64_t capsula_startup_lead_ns(double desired) {
  if (!isfinite(desired) || desired <= 0)
    return 0;
  if (desired > 0.100)
    desired = 0.100;
  return (uint64_t)ceil(desired * 1000000000.0);
}

static int capsula_startup_needs_preparation(capsula_startup_preparation *state,
                                            uint32_t ssrc) {
  return !state->prepared || state->ssrc != ssrc;
}

static void capsula_startup_mark_prepared(capsula_startup_preparation *state,
                                         uint32_t ssrc) {
  state->prepared = 1;
  state->ssrc = ssrc;
}
#endif
