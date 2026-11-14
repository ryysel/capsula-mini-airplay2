// Ring driver for the AirPlay receiver on VK Capsula Mini stock.
//
// The ring is 12 RGB pixels. The stock ws2812b driver takes 36 channel bytes
// through LEDS_WS2812B_IOCTL_MULTI_SET and applies a fixed channel map; the
// map below is the one used by voice-agent. Artwork colours come from the
// shairport cover cache, decoded by the helper binary (capsula-art --palette).
// The daemon yields the ring to stock voice-agent animations.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define NPIX 12
#define NCH 36
#define ART_BIN "/data/local/capsula-airplay/bin/capsula-art"
#define COVER_DIR "/tmp/capsula-airplay-covers"
#define VOLUME_FILE "/tmp/capsula-airplay-volume"
#define CONTROL_SOCK "/tmp/capsula-airplay-control.sock"
#define MAX_PAL 16

struct led_req {
  uint32_t start;
  uint32_t count;
  uint8_t *data;
};

#define LEDS_MULTI_SET _IOW('z', 1, struct led_req)
#define LEDS_GET_COUNT _IOW('z', 2, int)

/* Source channel index -> physical channel offset (from voice-agent). */
static const int chan_map[NCH] = {
    1,  0,  2,  34, 33, 35, 31, 30, 32, 28, 27, 29, 25, 24, 26, 22, 21, 23,
    19, 18, 20, 16, 15, 17, 13, 12, 14, 10, 9,  11, 7,  6,  8,  4,  3,  5};

typedef struct {
  uint8_t r, g, b;
} rgb_t;

static int leds_fd = -1;
static rgb_t frame[NPIX];
static rgb_t palette[MAX_PAL];
static int palette_n = 0;
static char cover_id[512];
static volatile sig_atomic_t stop_flag = 0;

static double now_s(void) {
  struct timespec ts;
  clock_gettime(CLOCK_BOOTTIME, &ts);
  return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void on_signal(int sig) {
  (void)sig;
  stop_flag = 1;
}

static void flush_frame_flat(void) {
  uint8_t src[NCH];
  for (int p = 0; p < NPIX; p++) {
    src[p * 3 + 0] = frame[p].r;
    src[p * 3 + 1] = frame[p].g;
    src[p * 3 + 2] = frame[p].b;
  }
  uint8_t buf[NCH];
  for (int i = 0; i < NCH; i++)
    buf[chan_map[i]] = src[i];
  struct led_req req = {0, NCH, buf};
  if (leds_fd >= 0) {
    errno = 0;
    int rc = ioctl(leds_fd, LEDS_MULTI_SET, &req);
    if (rc != 0)
      fprintf(stderr, "capsula-airplay-ring: SET rc=%d errno=%d\n", rc, errno);
  }
}

static void fill_all(uint8_t r, uint8_t g, uint8_t b) {
  for (int i = 0; i < NPIX; i++) {
    frame[i].r = r;
    frame[i].g = g;
    frame[i].b = b;
  }
}

static void fill_arc(int percent) {
  int lit = (percent * NPIX + 50) / 100;
  if (lit > NPIX)
    lit = NPIX;
  for (int i = 0; i < NPIX; i++) {
    uint8_t v = i < lit ? 80 : 0;
    frame[i].r = v;
    frame[i].g = v;
    frame[i].b = v;
  }
}

static void paint_palette(void) {
  if (palette_n <= 0)
    return;
  for (int i = 0; i < NPIX; i++) {
    double t = (double)i * palette_n / NPIX;
    int idx = (int)t;
    double f = t - idx;
    if (idx >= palette_n)
      idx = palette_n - 1;
    int nxt = (idx + 1) % palette_n;
    double r = palette[idx].r * (1.0 - f) + palette[nxt].r * f;
    double g = palette[idx].g * (1.0 - f) + palette[nxt].g * f;
    double b = palette[idx].b * (1.0 - f) + palette[nxt].b * f;
    frame[i].r = (uint8_t)(r * 0.65);
    frame[i].g = (uint8_t)(g * 0.65);
    frame[i].b = (uint8_t)(b * 0.65);
  }
}

static int airplay_active(void) {
  int fd = socket(AF_UNIX, SOCK_SEQPACKET, 0);
  if (fd < 0)
    return 0;
  struct sockaddr_un sa;
  memset(&sa, 0, sizeof(sa));
  sa.sun_family = AF_UNIX;
  strncpy(sa.sun_path, CONTROL_SOCK, sizeof(sa.sun_path) - 1);
  int active = 0;
  if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) == 0) {
    char reply[32] = {0};
    if (send(fd, "state", 5, 0) == 5 &&
        recv(fd, reply, sizeof(reply) - 1, 0) > 0)
      active = strcmp(reply, "active") == 0;
  }
  close(fd);
  return active;
}

static int read_volume(int *value) {
  FILE *f = fopen(VOLUME_FILE, "r");
  if (f == NULL)
    return 0;
  int v = -1;
  int ok = fscanf(f, "%d", &v) == 1 && v >= 0 && v <= 100;
  fclose(f);
  if (ok)
    *value = v;
  return ok;
}

static int color_from_hex(const char *s, rgb_t *out) {
  unsigned r, g, b;
  if (sscanf(s, "%2x%2x%2x", &r, &g, &b) != 3)
    return 0;
  out->r = (uint8_t)r;
  out->g = (uint8_t)g;
  out->b = (uint8_t)b;
  return 1;
}

static void load_palette(const char *path) {
  char cmd[1024];
  snprintf(cmd, sizeof(cmd), "%s --palette '%s' 2>/dev/null", ART_BIN, path);
  FILE *p = popen(cmd, "r");
  palette_n = 0;
  if (p == NULL)
    return;
  char line[64];
  while (palette_n < MAX_PAL && fgets(line, sizeof(line), p) != NULL) {
    rgb_t c;
    if (color_from_hex(line, &c))
      palette[palette_n++] = c;
  }
  pclose(p);
}

static void scan_cover(void) {
  DIR *d = opendir(COVER_DIR);
  if (d == NULL) {
    palette_n = 0;
    return;
  }
  struct dirent *de;
  char best[256] = "";
  time_t best_mtime = 0;
  while ((de = readdir(d)) != NULL) {
    if (de->d_name[0] == '.')
      continue;
    char path[512];
    snprintf(path, sizeof(path), "%s/%s", COVER_DIR, de->d_name);
    struct stat st;
    if (stat(path, &st) != 0 || !S_ISREG(st.st_mode))
      continue;
    if (st.st_mtime > best_mtime ||
        (st.st_mtime == best_mtime && strcmp(de->d_name, best) > 0)) {
      best_mtime = st.st_mtime;
      snprintf(best, sizeof(best), "%s", de->d_name);
    }
  }
  closedir(d);
  if (best[0] == '\0') {
    palette_n = 0;
    cover_id[0] = '\0';
    return;
  }
  char id[300];
  snprintf(id, sizeof(id), "%s:%ld", best, (long)best_mtime);
  if (strcmp(id, cover_id) == 0)
    return;
  snprintf(cover_id, sizeof(cover_id), "%s", id);
  char path[512];
  snprintf(path, sizeof(path), "%s/%s", COVER_DIR, best);
  load_palette(path);
}

static double stock_until = 0;
static int last_log_count = -1;

static int stock_line(const char *line) {
  return strstr(line, "led animation loaded") != NULL ||
         strstr(line, "setVolume") != NULL ||
         strstr(line, "PHRASE_IN_PROGRESS") != NULL ||
         strstr(line, "SPEECH: start") != NULL;
}

static void poll_stock_log(void) {
  FILE *f = popen("logread", "r");
  if (f == NULL)
    return;
  char line[2048];
  int count = 0;
  while (fgets(line, sizeof(line), f) != NULL) {
    if (stock_line(line))
      count++;
  }
  pclose(f);
  if (last_log_count >= 0 && count > last_log_count)
    stock_until = now_s() + 3.0;
  last_log_count = count;
}

int main(int argc, char **argv) {
  signal(SIGTERM, on_signal);
  signal(SIGINT, on_signal);

  leds_fd = open("/dev/topleds", O_RDWR);
  if (leds_fd < 0) {
    fprintf(stderr, "capsula-airplay-ring: open /dev/topleds: %s\n",
            strerror(errno));
    return 1;
  }
  int count = 0;
  if (ioctl(leds_fd, LEDS_GET_COUNT, &count) != 0 || count != NCH)
    fprintf(stderr, "capsula-airplay-ring: LED channel count %d\n", count);

  if (argc > 1 && strcmp(argv[1], "--test") == 0) {
    /* Four red, four green, four blue: verifies colour order and map. */
    for (int i = 0; i < NPIX; i++) {
      frame[i].r = i < 4 ? 80 : 0;
      frame[i].g = (i >= 4 && i < 8) ? 80 : 0;
      frame[i].b = i >= 8 ? 80 : 0;
    }
    flush_frame_flat();
    sleep(5);
    fill_all(0, 0, 0);
    flush_frame_flat();
    close(leds_fd);
    return 0;
  }

  double next_state = 0, next_log = 0, next_cover = 0, volume_until = 0;
  int active = 0, painted = 0, last_volume = -1;

  while (!stop_flag) {
    double t = now_s();

    if (t >= next_state) {
      int was_active = active;
      active = airplay_active();
      if (active && !was_active) {
        last_log_count = -1;
        cover_id[0] = '\0';
        palette_n = 0;
      }
      next_state = t + 0.25;
    }
    if (t >= next_log && active) {
      poll_stock_log();
      next_log = t + 1.0;
    }
    if (t >= next_cover && active) {
      scan_cover();
      next_cover = t + 2.0;
    }

    if (!active) {
      if (painted) {
        fill_all(0, 0, 0);
        flush_frame_flat();
        painted = 0;
      }
      usleep(100000);
      continue;
    }

    if (t < stock_until) {
      painted = 0;
      usleep(100000);
      continue;
    }

    int volume = -1;
    if (read_volume(&volume) && volume != last_volume) {
      last_volume = volume;
      volume_until = t + 1.5;
    }

    if (t < volume_until && last_volume >= 0) {
      fill_arc(last_volume);
    } else if (palette_n > 0) {
      paint_palette();
    } else {
      int level = 16 + (int)(16 * (0.5 + 0.5 * sin(t * 2.0 * M_PI / 3.0)));
      fill_all(level, level, level);
    }
    flush_frame_flat();
    painted = 1;
    usleep(100000);
  }

  if (painted) {
    fill_all(0, 0, 0);
    flush_frame_flat();
  }
  close(leds_fd);
  return 0;
}
