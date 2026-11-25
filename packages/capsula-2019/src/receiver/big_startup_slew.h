/* SPDX-License-Identifier: MIT */
#ifndef BIG_STARTUP_SLEW_H
#define BIG_STARTUP_SLEW_H
#include <stdint.h>

/* During initial lock, distribute a moderate positive timing error over
 * packets rather than cutting audible 8 ms blocks out of the music. */
static inline int big_startup_slew(uint64_t elapsed_ns, int64_t centered_ns,
                                  int64_t current_ns, int samples, int limit,
                                  int *stuff) {
  if (elapsed_ns >= 8000000000ULL || centered_ns < 20000000 ||
      centered_ns > 120000000 || current_ns > 120000000 ||
      current_ns <= -20000000 || samples < 100 || limit <= 0)
    return 0;
  /* A stale history can still look late after the actual error subsides.
   * Don't cut another packet based on that history alone. */
  *stuff = 0;
  if (current_ns >= 10000000) {
    int trim = samples / 50;
    if (trim > limit)
      trim = limit;
    *stuff = -trim;
  }
  return 1;
}
#endif
