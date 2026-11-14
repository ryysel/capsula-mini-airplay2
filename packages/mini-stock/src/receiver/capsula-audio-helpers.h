/* Capsula PulseAudio startup and native volume helpers. SPDX-License-Identifier: MIT */
#ifndef CAPSULA_AUDIO_HELPERS_H
#define CAPSULA_AUDIO_HELPERS_H
#include <math.h>
#include <stddef.h>
#include <stdint.h>
/* Never require more queued data to uncork than the player is willing to queue.
 * A corked PA stream's server latency is not presentation delay of real audio. */
static size_t capsula_start_bytes(unsigned rate, unsigned channels, unsigned width,
                                  double desired) {
  double seconds = fmin(0.020, fmax(0.001, desired * 0.5));
  return (size_t)fmax(1, ceil(seconds * rate)) * channels * width;
}
static int capsula_db_percent(double db) {
  if (!isfinite(db) || db <= -30) return 0;
  if (db >= 0) return 100;
  return (int)lround(100.0 * (1.0 + db / 30.0));
}
static void capsula_meter(const void *buf, int samples, unsigned channels,
                           unsigned width) {
  static uint64_t last;
  static double square, peak;
  static size_t count;
  unsigned n = samples * channels;
  /* The backend requests native-endian PCM. Unsupported formats stay dark. */
  if (width != 2 && width != 4) return;
  for (unsigned i=0; i<n; ++i) {
    double v=width==4 ? ((const int32_t *)buf)[i]/2147483648.0 :
                        ((const int16_t *)buf)[i]/32768.0;
    square+=v*v; peak=fmax(peak,fabs(v)); ++count;
  }
  uint64_t now=get_absolute_time_in_ns();
  if (now-last < 30000000ULL) return;
  double rms=count ? sqrt(square/count) : 0;
  FILE *f=fopen("/tmp/capsula-airplay-level.new","w");
  if (f) {
    fprintf(f,"%.7f %.7f\n",rms,peak);
    fclose(f);
    rename("/tmp/capsula-airplay-level.new","/tmp/capsula-airplay-level");
  }
  last=now; square=peak=0; count=0;
}
#endif
