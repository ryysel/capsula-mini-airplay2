/* Host-only startup scheduling tests; no device or audio output. */
#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include "../packages/capsula-2019/src/receiver/capsula-startup-gate.h"

int main(void) {
  assert(capsula_startup_gate_enabled(1, 1, -1.7));
  assert(!capsula_startup_gate_enabled(0, 1, -1.7));
  assert(!capsula_startup_gate_enabled(1, 0, -1.7));
  assert(!capsula_startup_gate_enabled(1, 1, 0.0));
  assert(!capsula_startup_gate_enabled(1, 1, 0.1));
  assert(!capsula_startup_gate_enabled(1, 1, NAN));
  assert(capsula_startup_lead_ns(.150) == 100000000);
  assert(capsula_startup_lead_ns(.010) == 10000000);
  assert(capsula_startup_lead_ns(.350) == 100000000);
  assert(capsula_startup_lead_ns(-.1) == 0);
  assert(capsula_startup_lead_ns(NAN) == 0);
  capsula_startup_preparation state = {0};
  assert(capsula_startup_needs_preparation(&state, 44100));
  capsula_startup_mark_prepared(&state, 44100);
  assert(!capsula_startup_needs_preparation(&state, 44100));
  assert(capsula_startup_needs_preparation(&state, 48000));

  /* Recorded cold start: -144.527 ms, 352-frame packets at 44.1 kHz.
   * Re-selection after preparing PA must reach future presentation time,
   * not play stale packets and then audible resync/drop bursts. */
  const int64_t initial = -144527000;
  const uint64_t margin = capsula_startup_lead_ns(.150);
  unsigned first = 0;
  while (first < 64) {
    int64_t lead = initial + (int64_t)first * 352 * 1000000000LL / 44100;
    if (lead >= (int64_t)margin)
      break;
    ++first;
  }
  assert(first == 31);
  int64_t selected = initial + (int64_t)first * 352 * 1000000000LL / 44100;
  assert(selected >= (int64_t)margin);
  assert(selected < (int64_t)margin + 8000000);
  puts("PASS startup gating, bounded lead, prepared format and recorded -144 ms selection");
  return 0;
}
