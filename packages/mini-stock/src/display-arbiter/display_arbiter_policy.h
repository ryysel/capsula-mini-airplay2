/* SPDX-License-Identifier: MIT */
#ifndef CAPSULA_DISPLAY_ARBITER_POLICY_H
#define CAPSULA_DISPLAY_ARBITER_POLICY_H
#include <stdint.h>
#include <string.h>
#include <time.h>

#define CDA_COUNT 30
#define CDA_PACKET_SIZE 40
#define CDA_LEASE_NS 400000000ULL
#define CDA_PRIORITY_NS 1800000000ULL
static const unsigned char cda_map[30] = {
  1,28,21,17,22,29,24,26,25,19,18,23,27,20,16,15,0,2,7,5,6,4,3,10,12,11,14,13,8,9
};
static const unsigned char cda_digits[10] = {
  0x3f,0x06,0x5b,0x4f,0x66,0x6d,0x7d,0x07,0x7f,0x6f
};
static const unsigned cda_starts[4] = {0,7,16,23};

struct cda_policy {
  unsigned char native[60], frame[30];
  uint64_t received, priority_until;
  int have_native, leased, painted;
};

static int cda_receive(struct cda_policy *s, const unsigned char *p,
                       unsigned length, uint64_t now) {
  if (length != CDA_PACKET_SIZE || memcmp(p,"CDV1",4) ||
      p[4] > 1 || p[5] || p[6] || p[7] || p[38] || p[39])
    return 0;
  for (unsigned i=0;i<30;i++) if (p[8+i]>1) return 0;
  memcpy(s->frame,p+8,30);
  s->received=now;
  s->leased=p[4];
  return 1;
}

static int cda_active(const struct cda_policy *s, uint64_t now) {
  return s->leased && now >= s->received &&
         now-s->received<CDA_LEASE_NS && now>=s->priority_until;
}

/* Exact native HH:MM, optionally a blank leading zero. Other native frames
 * (volume, assistant, diagnostics) have priority, not just the UI log hints.
 * Brightness bytes are deliberately not part of this classification. */
static int cda_clock_at(const unsigned char native[60], const struct tm *tm) {
  int values[4]={tm->tm_hour/10,tm->tm_hour%10,tm->tm_min/10,tm->tm_min%10};
  for (unsigned digit=0;digit<4;digit++) {
    unsigned mask=0;
    for (unsigned bit=0;bit<7;bit++) {
      unsigned char on=native[cda_map[cda_starts[digit]+bit]*2];
      if (on>1) return 0;
      mask|=(unsigned)on<<bit;
    }
    if (mask!=cda_digits[values[digit]] &&
        !(digit==0 && values[0]==0 && mask==0)) return 0;
  }
  return native[cda_map[14]*2]<=1 && native[cda_map[15]*2]<=1;
}

static void cda_output(struct cda_policy *s, unsigned char out[60], uint64_t now) {
  memcpy(out,s->native,60);
  int active=cda_active(s,now);
  if (active) for (unsigned i=0;i<30;i++) out[i*2]=s->frame[i];
  s->painted=active;
}
#endif
