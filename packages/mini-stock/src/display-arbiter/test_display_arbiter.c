/* SPDX-License-Identifier: MIT */
#define CDA_TEST 1
#include "display_arbiter.c"
#include <assert.h>
#include <stdatomic.h>
/* Lease time is deterministic; a busy build host must not turn a scheduled
 * test pause into an artificial sender crash. Production uses CLOCK_MONOTONIC. */
static atomic_uint_fast64_t test_now=10000000000ULL;
uint64_t cda_mock_mono(void) {return atomic_load(&test_now);}
static void advance(uint64_t ns) {atomic_fetch_add(&test_now,ns);}
static pthread_mutex_t mock_lock=PTHREAD_MUTEX_INITIALIZER;
static unsigned char physical[60];
static unsigned long physical_writes;
static const char *phase="initial";
int cda_mock_ioctl(int fd,unsigned long req,void *argument) {
  if (fd!=42 || req!=CDA_SET) return 123;
  struct cda_request *r=argument;
  assert(r->start==0 && r->count==30);
  pthread_mutex_lock(&mock_lock);
  memcpy(physical,r->data,60);physical_writes++;
  pthread_mutex_unlock(&mock_lock);
  return 0;
}
static void clock_frame(unsigned char frame[60],unsigned char brightness) {
  memset(frame,0,60);
  time_t now=time(NULL);struct tm tm;localtime_r(&now,&tm);
  int digits[4]={tm.tm_hour/10,tm.tm_hour%10,tm.tm_min/10,tm.tm_min%10};
  /* Real capture: low byte is the lit-segment intensity (1..19 under
   * flashlight), NOT an enable bit with brightness in the adjacent byte.
   * Nonzero opaque adjacent bytes here exercise strict preservation too. */
  for (unsigned i=0;i<30;i++) frame[2*i+1]=(unsigned char)(i%3);
  for (unsigned digit=0;digit<4;digit++)
    for (unsigned bit=0;bit<7;bit++)
      frame[cda_map[cda_starts[digit]+bit]*2]=((cda_digits[digits[digit]]>>bit)&1) ? brightness : 0;
  frame[cda_map[14]*2]=frame[cda_map[15]*2]=brightness;
}
static void expect_flags(const unsigned char flags[30],unsigned char brightness) {
  pthread_mutex_lock(&mock_lock);
  for (unsigned i=0;i<30;i++) {
    unsigned char expected=flags[i] ? brightness : 0;
    if (physical[i*2]!=expected) {
      fprintf(stderr,"phase=%s channel=%u got=%u expected=%u priority=%llu now=%llu leased=%d painted=%d\n",
        phase,i,physical[i*2],expected,(unsigned long long)state.priority_until,
        (unsigned long long)mono(),state.leased,state.painted);
      abort();
    }
    assert(physical[i*2+1]==(unsigned char)(i%3));
  }
  pthread_mutex_unlock(&mock_lock);
}
static void expect_native(const unsigned char frame[60]) {
  pthread_mutex_lock(&mock_lock);
  assert(!memcmp(physical,frame,60));
  pthread_mutex_unlock(&mock_lock);
}
static void packet_send(int fd,int active,const unsigned char flags[30]) {
  unsigned char p[40]={0};
  memcpy(p,"CDV1",4);p[4]=(unsigned char)active;memcpy(p+8,flags,30);
  assert(send(fd,p,40,0)==40);
}
static void await_flags(int client,const unsigned char flags[30],unsigned char brightness) {
  for (int attempt=0;attempt<100;attempt++) {
    int matches=1;
    pthread_mutex_lock(&mock_lock);
    for (unsigned i=0;i<30;i++)
      if (physical[2*i]!=(flags[i] ? brightness : 0) || physical[2*i+1]!=(unsigned char)(i%3)) matches=0;
    pthread_mutex_unlock(&mock_lock);
    if (matches) return;
    packet_send(client,1,flags);
    usleep(20000);
  }
  expect_flags(flags,brightness);
}
static void recorded_flashlight_regression(void) {
  const unsigned char glyphs[4]={0x5b,0x4f,0x06,0x6f}; /* captured 23:19 */
  const unsigned char ramp[]={1,2,3,4,5,6,7,8,9,10,11,13,14,15,16,17,18,19,18,17,16,15,14,12,11,10,9,8,7,6,4,3,2,1};
  struct tm reference={.tm_hour=23,.tm_min=19};
  for (unsigned step=0;step<sizeof(ramp);step++) {
    struct cda_policy test={.received=1000,.leased=1,.have_native=1};
    for (unsigned digit=0;digit<4;digit++)
      for (unsigned bit=0;bit<7;bit++)
        test.native[cda_map[cda_starts[digit]+bit]*2]=((glyphs[digit]>>bit)&1)?ramp[step]:0;
    test.native[cda_map[14]*2]=test.native[cda_map[15]*2]=ramp[step];
    for(unsigned i=0;i<30;i++)test.frame[i]=(unsigned char)(i%2);
    assert(cda_clock_at(test.native,&reference));
    unsigned char output[60];
    cda_output(&test,output,1001);
    for(unsigned i=0;i<30;i++){
      assert(output[2*i]==(test.frame[i]?ramp[step]:0));
      assert(output[2*i+1]==0);
    }
    test.leased=0;cda_output(&test,output,1002);
    assert(!memcmp(output,test.native,60));
  }
}
int main(void) {
  recorded_flashlight_regression();
  setenv("CAPSULA_DISPLAY_ARBITER","1",1);
  unsigned char native[60],vu[30];
  clock_frame(native,75);
  assert(native_clock(native));
  struct cda_policy test={0};
  unsigned char bad[41]={0};
  assert(!cda_receive(&test,bad,41,10));
  memcpy(bad,"CDV1",4);bad[4]=1;bad[8]=2;
  assert(!cda_receive(&test,bad,40,10));
  bad[8]=1;assert(cda_receive(&test,bad,40,1000));
  assert(cda_active(&test,1000));assert(!cda_active(&test,999));
  assert(!cda_active(&test,1000+CDA_LEASE_NS));
  struct cda_request req={0,30,native};
  assert(ioctl(42,CDA_SET,&req)==0);
  assert(ioctl(17,0x1234UL,(void*)0)==123);
  int client=socket(AF_UNIX,SOCK_DGRAM|SOCK_CLOEXEC,0);
  assert(client>=0);
  struct sockaddr_un addr={.sun_family=AF_UNIX};
  strcpy(addr.sun_path,CDA_SOCKET);
  assert(connect(client,(struct sockaddr*)&addr,sizeof(addr))==0);
  for (unsigned i=0;i<30;i++) vu[i]=(unsigned char)(i%2);
  phase="first lease";
  packet_send(client,1,vu);
  await_flags(client,vu,75);
  for (unsigned step=0;step<255;step++) {
    phase="brightness changes";
    clock_frame(native,(unsigned char)(step+1));
    assert(native_clock(native));
    unsigned char original[60];memcpy(original,native,60);
    assert(ioctl(42,CDA_SET,&req)==0);
    assert(!memcmp(original,native,60)); /* don't mutate native cached state */
    expect_flags(vu,(unsigned char)(step+1));
    packet_send(client,1,vu);
    usleep(10000);
  }
  /* A native non-clock frame immediately wins, regardless of stale UI hints. */
  memset(native,0,60);
  for (unsigned i=0;i<30;i++) native[i*2+1]=(unsigned char)(i%3);
  native[cda_map[23]*2]=31;
  assert(!native_clock(native));
  assert(ioctl(42,CDA_SET,&req)==0);expect_native(native);
  for (int i=0;i<5;i++) {advance(100000000);packet_send(client,1,vu);usleep(100000);expect_native(native);}
  for (int i=0;i<16;i++) {advance(100000000);packet_send(client,1,vu);usleep(100000);}
  phase="native priority expired";
  await_flags(client,vu,31);
  clock_frame(native,88);
  phase="brightness after priority";
  assert(ioctl(42,CDA_SET,&req)==0);expect_flags(vu,88);
  packet_send(client,0,vu);usleep(100000);expect_native(native);
  packet_send(client,1,vu);await_flags(client,vu,88);
  /* Crashed UI / vanished sender returns to the last actual native frame. */
  advance(CDA_LEASE_NS+1);usleep(100000);expect_native(native);
  close(client);
  assert(physical_writes>255 && replacements>=255 && native_priority>0);
  puts("ARBITER_PASS: actual intensity encoding 1..255; opaque bytes preserved; no mixed clock/VU; native priority; release; crash expiry; input preserved");
  return 0;
}
