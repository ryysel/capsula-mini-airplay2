/* SPDX-License-Identifier: MIT */
#include <assert.h>
#include <stdio.h>
#include "big_startup_slew.h"

int main(void) {
  int stuff = 0;
  assert(big_startup_slew(1000000000, 51000000, 51000000, 352, 20, &stuff));
  assert(stuff == -7);
  assert(big_startup_slew(1000000000, 51000000, 0, 352, 20, &stuff) && stuff == 0);
  assert(big_startup_slew(1000000000, 51000000, 51000000, 1024, 9, &stuff) && stuff == -9);
  assert(!big_startup_slew(8000000000ULL, 51000000, 51000000, 352, 20, &stuff));
  assert(!big_startup_slew(1000000000, -51000000, -51000000, 352, 20, &stuff));
  assert(!big_startup_slew(1000000000, 121000000, 121000000, 352, 20, &stuff));
  assert(!big_startup_slew(1000000000, 52000000, -20000000, 352, 20, &stuff));
  assert(!big_startup_slew(1000000000, 52000000, 51000000, 80, 20, &stuff));
  /* Idealized 44.1 kHz replay: observed 51 ms timing error is shortened
   * across contiguous packets, without discarding any entire packet. */
  int64_t error = 51000000;
  unsigned packets = 0;
  while (error >= 20000000) {
    assert(packets++ < 500);
    assert(big_startup_slew(1000000000ULL + packets * 7981859ULL, error, error, 352, 20, &stuff));
    assert(stuff < 0 && stuff > -352);
    error += (int64_t)stuff * 1000000000 / 44100;
  }
  printf("PASS timing policy and nominal replay (%u contiguous packets)\n", packets);
}
