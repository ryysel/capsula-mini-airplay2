
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
static uint64_t get_absolute_time_in_ns(void) { return 0; }
#include "capsula-audio-helpers.h"
int main(void) {
  const double desired[]={.010,.020,.050,.100,.200,.350};
  for (unsigned i=0;i<sizeof(desired)/sizeof(*desired);++i) {
    size_t threshold=capsula_start_bytes(44100,2,4,desired[i]);
    assert(threshold<=ceil(44100*desired[i])*8);
    assert(threshold<=44100*.021*8);
  }
  for (int p=0;p<=100;++p) assert(capsula_db_percent((p/100.0-1)*30)==p);
  assert(capsula_db_percent(-144)==0);
  puts("PASS startup thresholds and 101 volume round-trips");
}
