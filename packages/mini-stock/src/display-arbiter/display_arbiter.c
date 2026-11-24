/* SPDX-License-Identifier: MIT
 * Stock Mini ONLY. One serialized owner of segment state and native brightness.
 * No audio, account, network server or general device interception.
 */
#define _GNU_SOURCE
#include "display_arbiter_policy.h"
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <unistd.h>

#define CDA_SET 0xc0106b01UL
#ifndef CDA_SOCKET
#define CDA_SOCKET "/tmp/capsula-mini-display-arbiter.sock"
#endif
#ifndef CDA_STATUS
#define CDA_STATUS "/tmp/capsula-mini-display-arbiter.status"
#endif
struct cda_request { uint32_t start,count; unsigned char *data; };
_Static_assert(sizeof(struct cda_request)==16,"64-bit request ABI required");
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t once=PTHREAD_ONCE_INIT;
static struct cda_policy state;
static int enabled, device_fd=-1, socket_fd=-1, thread_started, stopping;
static pthread_t thread;
static unsigned long replacements,native_priority,writes,errors;

#ifdef CDA_TEST
extern int cda_mock_ioctl(int,unsigned long,void*);
static int raw_ioctl(int fd,unsigned long req,void *arg) {return cda_mock_ioctl(fd,req,arg);}
#else
static int raw_ioctl(int fd,unsigned long req,void *arg) {
  return (int)syscall(SYS_ioctl,fd,req,arg);
}
#endif
static uint64_t mono(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC,&t);
  return (uint64_t)t.tv_sec*1000000000ULL+(uint64_t)t.tv_nsec;
}
static void init_enabled(void) {
  const char *value=getenv("CAPSULA_DISPLAY_ARBITER");
  if (!value || strcmp(value,"1")) return;
#ifdef CDA_TEST
  enabled=1;
#else
  char path[256];
  ssize_t n=readlink("/proc/self/exe",path,sizeof(path)-1);
  if (n<=0 || getuid()!=0) return;
  path[n]=0;
  const char *name=strrchr(path,'/');
  enabled=name && !strcmp(name+1,"voice-agent");
#endif
}
static int correct_device(int fd) {
#ifdef CDA_TEST
  return fd==42;
#else
  struct stat a,b;
  return !fstat(fd,&a) && S_ISCHR(a.st_mode) &&
         !stat("/dev/is31fl32xx",&b) && a.st_rdev==b.st_rdev;
#endif
}
static int native_clock(const unsigned char bytes[60]) {
  time_t now=time(NULL);
  struct tm tm;
  for (int delta=-1;delta<=1;delta++) {
    time_t at=now+delta;
    if (localtime_r(&at,&tm) && cda_clock_at(bytes,&tm)) return 1;
  }
  return 0;
}
static int send_frame(const unsigned char frame[60]) {
  struct cda_request req={0,30,(unsigned char*)frame};
  int result=raw_ioctl(device_fd,CDA_SET,&req);
  if (result<0) errors++; else writes++;
  return result;
}
static void status_write(uint64_t now) {
  char text[256],stage[256];
  snprintf(stage,sizeof(stage),"%s.new",CDA_STATUS);
  int fd=open(stage,O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC|O_NOFOLLOW,0600);
  if (fd<0) return;
  int n=snprintf(text,sizeof(text),
    "CDV1 ready=1 active=%d overrides=%lu native_priority=%lu writes=%lu errors=%lu\n",
    cda_active(&state,now),replacements,native_priority,writes,errors);
  if (write(fd,text,(size_t)n)==n && rename(stage,CDA_STATUS)==0) {
#ifndef CDA_TEST
    /* A verified native frame reached the real driver and the worker is up.
     * A failed early launch leaves this guard, bypassing preload next boot. */
    if (!errors) (void)unlink("/data/local/capsula-airplay/etc/mini-display-arbiter.pending");
#endif
  }
  close(fd);
}
static void *worker(void *unused) {
  (void)unused;
  uint64_t next_status=0;
  for (;;) {
    pthread_mutex_lock(&lock);
    if (stopping) {pthread_mutex_unlock(&lock);return NULL;}
    uint64_t now=mono();
    unsigned char packet[CDA_PACKET_SIZE+1];
    for (int i=0;i<32;i++) {
      ssize_t n=recv(socket_fd,packet,sizeof(packet),MSG_DONTWAIT);
      if (n<0) break;
      (void)cda_receive(&state,packet,(unsigned)n,now);
    }
    if (state.have_native && (cda_active(&state,now) || state.painted)) {
      unsigned char output[60];
      cda_output(&state,output,now);
      if (send_frame(output)<0) state.leased=0;
    }
    if (now>=next_status) {status_write(now);next_status=now+1000000000ULL;}
    pthread_mutex_unlock(&lock);
    struct timespec delay={0,40000000};
    while (nanosleep(&delay,&delay)<0 && errno==EINTR) {}
  }
}
static int start_worker(int fd) {
  if (thread_started) return 1;
  struct sockaddr_un address={.sun_family=AF_UNIX};
  if (strlen(CDA_SOCKET)>=sizeof(address.sun_path)) return 0;
  strcpy(address.sun_path,CDA_SOCKET);
  struct stat st;
  if (!lstat(CDA_SOCKET,&st)) {
    if (!S_ISSOCK(st.st_mode) || st.st_uid!=getuid()) return 0;
    if (unlink(CDA_SOCKET)<0) return 0;
  }
  socket_fd=socket(AF_UNIX,SOCK_DGRAM|SOCK_CLOEXEC|SOCK_NONBLOCK,0);
  if (socket_fd<0) return 0;
  if (bind(socket_fd,(struct sockaddr*)&address,sizeof(address))<0 ||
      chmod(CDA_SOCKET,0600)<0) goto fail;
#ifdef CDA_TEST
  device_fd=fd;
#else
  device_fd=fcntl(fd,F_DUPFD_CLOEXEC,3);
  if (device_fd<0) goto fail;
#endif
  if (pthread_create(&thread,NULL,worker,NULL)!=0) goto fail;
  thread_started=1;
  return 1;
fail:
  if (device_fd>=0) {
#ifndef CDA_TEST
    close(device_fd);
#endif
    device_fd=-1;
  }
  close(socket_fd);socket_fd=-1;
  (void)unlink(CDA_SOCKET);
  return 0;
}

int ioctl(int fd,unsigned long request,...) {
  va_list ap;
  va_start(ap,request);
  void *argument=va_arg(ap,void*);
  va_end(ap);
  pthread_once(&once,init_enabled);
  if (!enabled || request!=CDA_SET || !argument || !correct_device(fd))
    return raw_ioctl(fd,request,argument);
  struct cda_request *input=argument;
  if (input->start || input->count!=30 || !input->data)
    return raw_ioctl(fd,request,argument);
  unsigned char saved[60],output[60];
  memcpy(saved,input->data,60);
  pthread_mutex_lock(&lock);
  uint64_t now=mono();
  int clock=native_clock(saved);
  if (!clock) {state.priority_until=now+CDA_PRIORITY_NS;native_priority++;}
  memcpy(state.native,saved,60);
  state.have_native=1;
  cda_output(&state,output,now);
  struct cda_request replacement={0,30,output};
  int result=raw_ioctl(fd,request,&replacement);
  int saved_errno=errno;
  if (!result) {
    if (cda_active(&state,now)) replacements++;
    (void)start_worker(fd);
  } else {errors++;state.leased=0;}
  pthread_mutex_unlock(&lock);
  errno=saved_errno;
  return result;
}

__attribute__((destructor)) static void finish(void) {
  if (!thread_started) return;
  pthread_mutex_lock(&lock);
  stopping=1;
  if (state.have_native && state.painted) (void)send_frame(state.native);
  pthread_mutex_unlock(&lock);
  pthread_join(thread,NULL);
  close(socket_fd);
#ifndef CDA_TEST
  close(device_fd);
#endif
  (void)unlink(CDA_SOCKET);
  (void)unlink(CDA_STATUS);
}
