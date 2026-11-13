#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

struct led_ctrl_data {
    uint32_t trigger;
    uint32_t delayed_trigger_ms;
    uint32_t brightness;
    uint32_t delay_on;
    uint32_t delay_off;
} __attribute__((packed));

#define LEDS_MULTI_CTRL_IOCTL_MULTI_SET \
    _IOW('z', 0x01, struct led_ctrl_data *)
#define LEDS_MULTI_CTRL_IOCTL_GET_LED_NUMBER \
    _IOR('z', 0x02, int)

static int fd = -1;
static int nleds = 0;
static struct led_ctrl_data *buf = NULL;

static int clamp255(int v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return v;
}

static int open_dev(void) {
    fd = open("/dev/led_multi_ctrl", O_RDWR);
    if (fd < 0) {
        perror("open /dev/led_multi_ctrl");
        return -1;
    }
    int n = 0;
    if (ioctl(fd, LEDS_MULTI_CTRL_IOCTL_GET_LED_NUMBER, &n) == 0)
        nleds = n;
    else
        perror("GET_LED_NUMBER");
    if (nleds <= 0 || nleds > 256) nleds = 39;
    buf = calloc((size_t)nleds, sizeof(*buf));
    if (!buf) {
        perror("calloc");
        return -1;
    }
    return 0;
}

static int apply(void) {
    unsigned long cmds[] = {
        (unsigned long)LEDS_MULTI_CTRL_IOCTL_MULTI_SET,
        (unsigned long)_IOW('z', 0x01, struct led_ctrl_data),
        0
    };
    for (int i = 0; cmds[i]; i++) {
        if (ioctl(fd, cmds[i], buf) == 0)
            return 0;
    }
    perror("MULTI_SET");
    return -1;
}

static void clear_buf(void) {
    memset(buf, 0, (size_t)nleds * sizeof(*buf));
    for (int i = 0; i < nleds; i++)
        buf[i].trigger = 1; /* TRIG_DEF_ON */
}

static void set_ch(int i, int v) {
    if (i >= 0 && i < nleds) {
        buf[i].trigger = 1; /* TRIG_DEF_ON */
        buf[i].brightness = (uint32_t)clamp255(v);
    }
}

/* Channel map learned on the 2019 Capsule:
 *   0,1,2      = top activity LED, R,G,B
 *   3+3*i      = ring pixel i, green
 *   4+3*i      = ring pixel i, red
 *   5+3*i      = ring pixel i, blue
 */
static void set_top(int r, int g, int b) {
    set_ch(0, r);
    set_ch(1, g);
    set_ch(2, b);
}

static void set_ring(int p, int r, int g, int b) {
    if (p < 0 || p > 11) return;
    set_ch(3 + 3 * p, g);
    set_ch(4 + 3 * p, r);
    set_ch(5 + 3 * p, b);
}

static void fill_ring(int r, int g, int b) {
    for (int p = 0; p < 12; p++)
        set_ring(p, r, g, b);
}

static void off(void) {
    clear_buf();
    apply();
}

static void fill(int r, int g, int b) {
    clear_buf();
    fill_ring(r, g, b);
    apply();
}

static int parse_color(const char *s, int *r, int *g, int *b) {
    if (sscanf(s, "%d,%d,%d", r, g, b) == 3)
        return 0;
    if (s[0] == '#' && strlen(s) == 7) {
        unsigned v = (unsigned)strtoul(s + 1, NULL, 16);
        *r = (v >> 16) & 0xff;
        *g = (v >> 8) & 0xff;
        *b = v & 0xff;
        return 0;
    }
    return -1;
}

/* Read the BH1750 raw count. Returns -1 when the node is missing. */
static int als_raw(void) {
    FILE *f = fopen("/sys/bus/iio/devices/iio:device1/in_illuminance_raw", "r");
    if (!f) return -1;
    int v = -1;
    if (fscanf(f, "%d", &v) != 1) v = -1;
    fclose(f);
    return v;
}

/* Brightness schedule: used as a fallback when the ALS gives no signal. */
static int schedule_pct(int hour) {
    if (hour >= 8 && hour < 20) return 100;  /* day */
    if (hour >= 20 && hour < 23) return 70;  /* evening */
    return 30;                               /* night */
}

static void clock_frame(void) {
    time_t now = time(NULL);
    struct tm tm;
    localtime_r(&now, &tm);
    int hour = tm.tm_hour % 12;
    int minutes = tm.tm_min;
    int fill_full = minutes / 5;   /* completed 5-minute segments */
    int fill_frac = minutes % 5;   /* fraction of the leading segment */
    /* Physical ring: pixel 0 is at 9 o'clock, index grows clockwise,
     * so 12 o'clock is pixel 3. */
    int hour_ring = (hour + 3) % 12;
    int pct = schedule_pct(tm.tm_hour);
    int als = als_raw(); /* diagnostics: 0 in a lit room on this board */

    clear_buf();
    /* minute progress: turquoise -> blue gradient, clockwise from 12 */
    const int max_level = 140;
    for (int pos = 0; pos < 12; pos++) {
        int ring = (pos + 3) % 12;
        int level = 0;
        if (pos < fill_full)
            level = max_level;
        else if (pos == fill_full)
            level = (fill_frac * max_level) / 5;
        if (level > 0) {
            double t = pos / 11.0;
            int r = 0;
            int g = (int)(200.0 - 140.0 * t);
            int b = (int)(170.0 + 50.0 * t);
            r = r * level / max_level * pct / 100;
            g = g * level / max_level * pct / 100;
            b = b * level / max_level * pct / 100;
            set_ring(ring, r, g, b);
        }
    }
    /* hour marker: warm amber, always visible on top of the fill */
    set_ring(hour_ring, 255 * pct / 100, 110 * pct / 100, 0);
    /* top indicator: AM cool blue, PM warm amber */
    if (tm.tm_hour < 12)
        set_top(0, 0, 60 * pct / 100);
    else
        set_top(90 * pct / 100, 35 * pct / 100, 0);

    apply();
    printf("%02d:%02d fill=%d+%d/5 hour_ring=%d pct=%d als=%d\n", tm.tm_hour, tm.tm_min,
           fill_full, fill_frac, hour_ring, pct, als);
}

enum { ST_UNKNOWN, ST_BUSY, ST_DONE };

/* voice-agent logs a small state machine; the last such line in the syslog
 * buffer tells us whether the ring is being animated:
 *   WAITING_FOR_KEYWORD -> PHRASE_IN_PROGRESS -> PHRASE_RESULT_PENDING
 *   SPEECH: start / onSpeechPlaybackFinished / "SPEECH: stop"
 * Note: the device clock jumps (ntpd), so timestamps are not reliable for
 * ordering; the buffer order is. */
static double monotonic_seconds(void) {
    struct timespec t;
    clock_gettime(CLOCK_BOOTTIME, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

/* A short-lived, atomically replaced frame from the local artwork companion.
 * Expiry is boot-relative, so NTP changes cannot leave a stuck colour ring.
 * The LED broker remains the only writer to /dev/led_multi_ctrl. */
static int artwork_frame(void) {
    FILE *f = fopen("/tmp/capsula-airplay-frame", "r");
    if (!f) return 0;
    double expiry, now = monotonic_seconds();
    int pixels[12][3], ok = fscanf(f, "%lf", &expiry) == 1;
    if (!(expiry > now && expiry <= now + 3.0)) ok = 0;
    for (int i = 0; ok && i < 12; i++) {
        if (fscanf(f, "%d%d%d", &pixels[i][0], &pixels[i][1], &pixels[i][2]) != 3) ok = 0;
        for (int k = 0; ok && k < 3; k++)
            if (pixels[i][k] < 0 || pixels[i][k] > 255) ok = 0;
    }
    fclose(f);
    if (!ok) return 0;
    clear_buf();
    for (int i = 0; i < 12; i++) set_ring((i+3)%12, pixels[i][0], pixels[i][1], pixels[i][2]);
    apply();
    return 1;
}

static void daemon_loop(void) {
    char last_line[600] = "", last_volume[600] = "";
    int last_count = 0, state = ST_UNKNOWN, first = 1, shown = -1;
    double started = monotonic_seconds(), changed = started, next_log = 0;
    double last_render = 0, volume_until = 0;
    int grace = 1;
    syslog(LOG_INFO, "capsula-led: media broker started");
    for (;;) {
        double now = monotonic_seconds();
        if (now >= next_log) {
            char found[600] = "", volume[600] = "";
            int count = 0, found_grace = 1;
            FILE *f = popen("logread", "r");
            if (f) {
                char line[2048];
                while (fgets(line, sizeof(line), f)) {
                    int busy = 0, done = 0, g = 1;
                    if (strstr(line, "voice-agent:") && strstr(line, "] setVolume"))
                        snprintf(volume, sizeof(volume), "%s", line);
                    if (strstr(line, "led animation loaded")) {
                        if (strstr(line, "ready.json")) done = 1;
                        else { busy = 1; g = 4; }
                    } else if (strstr(line, "=> PHRASE_IN_PROGRESS") ||
                               strstr(line, "=> PHRASE_RESULT_PENDING") ||
                               strstr(line, "SPEECH: start")) busy = 1;
                    else if (strstr(line, "onSpeechPlaybackFinished") ||
                             strstr(line, "SPEECH: stop") ||
                             strstr(line, "=> WAITING_FOR_KEYWORD")) done = 1;
                    if (!busy && !done) continue;
                    count++;
                    snprintf(found, sizeof(found), "%c%s", busy ? 'B' : 'D', line);
                    found_grace = g;
                }
                pclose(f);
            }
            if (!first && volume[0] && strcmp(volume, last_volume)) volume_until = now + 1.5;
            snprintf(last_volume, sizeof(last_volume), "%s", volume);
            if (!first && found[0] && (strcmp(found, last_line) || count > last_count)) {
                state = found[0] == 'B' ? ST_BUSY : ST_DONE;
                changed = now; grace = found_grace;
            }
            snprintf(last_line, sizeof(last_line), "%s", found);
            last_count = count; first = 0; next_log = now + .5;
        }
        int idle = (state == ST_DONE && now-changed >= grace) ||
                   (state == ST_BUSY && now-changed >= 40) ||
                   (state == ST_UNKNOWN && now-started >= 15);
        if (now < volume_until) idle = 0;
        int mode = 0;
        if (idle) {
            mode = 1;
            if (artwork_frame()) mode = 2;
            else if (shown != 1 || now-last_render >= 5) { clock_frame(); last_render = now; }
        }
        if (mode != shown) {
            syslog(LOG_INFO, "capsula-led: %s", mode == 2 ? "artwork" : mode == 1 ? "clock" : "stock");
            shown = mode;
        }
        usleep(100000);
    }
}

static void dump_buf(const char *tag) {
    printf("%s:", tag);
    for (int i = 0; i < 6 && i < nleds; i++)
        printf(" [%d]t=%u b=%u", i, buf[i].trigger, buf[i].brightness);
    printf("\n");
}

static void probe_get(void) {
    unsigned long cmds[] = {
        _IOR('z', 0x03, struct led_ctrl_data *),
        _IOWR('z', 0x03, struct led_ctrl_data *),
        _IOR('z', 0x04, struct led_ctrl_data *),
        _IOW('z', 0x03, struct led_ctrl_data *),
        0
    };
    for (int c = 0; cmds[c]; c++) {
        for (int i = 0; i < nleds; i++) {
            buf[i].trigger = 0xAAAAAAAA;
            buf[i].delayed_trigger_ms = 0xBBBBBBBB;
            buf[i].brightness = 0xCCCCCCCC;
            buf[i].delay_on = 0xDDDDDDDD;
            buf[i].delay_off = 0xEEEEEEEE;
        }
        errno = 0;
        int r = ioctl(fd, cmds[c], buf);
        printf("cmd=0x%08lx ret=%d errno=%d\n", cmds[c], r, errno);
        dump_buf("  after");
    }
}

static void map_readback(void) {
    clear_buf();
    for (int i = 0; i < nleds; i++)
        set_ch(i, i + 1);
    apply();
    usleep(200000);
    printf("ch -> sysfs:\n");
    for (int n = 1; n <= 39; n++) {
        char path[64];
        snprintf(path, sizeof(path), "/sys/class/leds/led%d/brightness", n);
        FILE *f = fopen(path, "r");
        int v = -1;
        if (f) {
            if (fscanf(f, "%d", &v) != 1) v = -1;
            fclose(f);
        }
        printf("  led%-2d = %d\n", n, v);
    }
}

static int read_frame(int *out) {
    int changed = 0;
    for (int n = 1; n <= 39; n++) {
        char path[64];
        snprintf(path, sizeof(path), "/sys/class/leds/led%d/brightness", n);
        FILE *f = fopen(path, "r");
        int v = -1;
        if (f) {
            if (fscanf(f, "%d", &v) != 1) v = -1;
            fclose(f);
        }
        out[n - 1] = v;
        changed |= v;
    }
    return changed;
}

static unsigned long frame_hash(const int *v) {
    unsigned long h = 5381;
    for (int i = 0; i < 39; i++)
        h = h * 33 + (unsigned long)(v[i] + 1);
    return h;
}

static void watch(int seconds) {
    int v[39];
    time_t end = time(NULL) + seconds;
    unsigned long prev = 0;
    while (time(NULL) < end) {
        read_frame(v);
        unsigned long h = frame_hash(v);
        printf("%lu %s\n", h, h == prev ? "same" : "CHANGED");
        fflush(stdout);
        prev = h;
        usleep(300000);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr,
                "usage: %s info|off|fill R G B|pixel N R G B|top R G B|ch N V|test|clock [SEC]|daemon\n",
                argv[0]);
        return 2;
    }
    if (open_dev() != 0)
        return 1;

    const char *cmd = argv[1];
    if (!strcmp(cmd, "info")) {
        printf("leds=%d\n", nleds);
        return 0;
    }
    if (!strcmp(cmd, "off")) {
        off();
        return 0;
    }
    if (!strcmp(cmd, "fill") && argc >= 5) {
        fill(atoi(argv[2]), atoi(argv[3]), atoi(argv[4]));
        return 0;
    }
    if (!strcmp(cmd, "pixel") && argc >= 6) {
        clear_buf();
        set_ring(atoi(argv[2]), atoi(argv[3]), atoi(argv[4]), atoi(argv[5]));
        apply();
        return 0;
    }
    if (!strcmp(cmd, "top") && argc >= 5) {
        clear_buf();
        set_top(atoi(argv[2]), atoi(argv[3]), atoi(argv[4]));
        apply();
        return 0;
    }
    if (!strcmp(cmd, "ch") && argc >= 4) {
        clear_buf();
        set_ch(atoi(argv[2]), atoi(argv[3]));
        apply();
        return 0;
    }
    if (!strcmp(cmd, "test")) {
        for (int p = 0; p < 12; p++) {
            clear_buf();
            set_ring(p, 120, 120, 120);
            apply();
            printf("ring pixel %d\n", p);
            fflush(stdout);
            usleep(800000);
            off();
            usleep(200000);
        }
        clear_buf();
        set_top(120, 120, 120);
        apply();
        printf("top pixel\n");
        fflush(stdout);
        usleep(800000);
        off();
        return 0;
    }
    if (!strcmp(cmd, "watch")) {
        watch(argc > 2 ? atoi(argv[2]) : 10);
        return 0;
    }
    if (!strcmp(cmd, "map")) {
        map_readback();
        return 0;
    }
    if (!strcmp(cmd, "probe")) {
        probe_get();
        return 0;
    }
    if (!strcmp(cmd, "daemon")) {
        daemon_loop();
        return 0;
    }
    if (!strcmp(cmd, "clock")) {
        int seconds = argc >= 3 ? atoi(argv[2]) : 60;
        time_t end = time(NULL) + seconds;
        while (time(NULL) < end) {
            clock_frame();
            fflush(stdout);
            sleep(5);
        }
        off();
        return 0;
    }
    fprintf(stderr, "unknown command: %s\n", cmd);
    return 2;
}
