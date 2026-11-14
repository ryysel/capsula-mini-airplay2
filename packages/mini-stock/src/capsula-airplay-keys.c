// Play/pause key bridge for the AirPlay receiver on VK Capsula Mini stock.
// The csk05t touch controller exposes a dedicated KEY_PLAYPAUSE that the
// stock voice-agent does not use for AirPlay. Read it passively (evdev allows
// several readers) and forward a toggle to shairport's control socket.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

static int open_device(void) {
  for (int i = 0; i < 8; i++) {
    char path[32];
    snprintf(path, sizeof(path), "/dev/input/event%d", i);
    int fd = open(path, O_RDONLY | O_NONBLOCK);
    if (fd < 0)
      continue;
    char name[64] = {0};
    if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) < 0) {
      close(fd);
      continue;
    }
    if (strcmp(name, "csk05t") == 0)
      return fd;
    close(fd);
  }
  return -1;
}

static void send_toggle(void) {
  int fd = socket(AF_UNIX, SOCK_SEQPACKET, 0);
  if (fd < 0)
    return;
  struct sockaddr_un sa;
  memset(&sa, 0, sizeof(sa));
  sa.sun_family = AF_UNIX;
  strncpy(sa.sun_path, "/tmp/capsula-airplay-control.sock",
          sizeof(sa.sun_path) - 1);
  if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) == 0) {
    char reply[32] = {0};
    if (send(fd, "toggle", 6, 0) == 6) {
      ssize_t n = recv(fd, reply, sizeof(reply) - 1, 0);
      if (n > 0)
        syslog(LOG_INFO, "capsula-airplay-keys: toggle -> %.*s", (int)n,
               reply);
    }
  }
  close(fd);
}

int main(void) {
  openlog("capsula-airplay-keys", LOG_PID, LOG_DAEMON);
  int fd = open_device();
  if (fd < 0) {
    syslog(LOG_ERR, "capsula-airplay-keys: csk05t input device not found");
    return 1;
  }
  struct input_event ev;
  long last_ms = 0;
  for (;;) {
    ssize_t n = read(fd, &ev, sizeof(ev));
    if (n == (ssize_t)sizeof(ev)) {
      if (ev.type == EV_KEY && ev.code == KEY_PLAYPAUSE && ev.value == 1) {
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        long ms = ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
        if (ms - last_ms > 300) {
          last_ms = ms;
          send_toggle();
        }
      }
    } else if (n < 0 && errno != EAGAIN && errno != EINTR) {
      usleep(200000);
    } else {
      usleep(50000);
    }
  }
}
