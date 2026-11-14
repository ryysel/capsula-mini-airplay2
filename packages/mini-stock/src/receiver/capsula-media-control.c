/* Local-only AirPlay 2 transport endpoint. Uses upstream remote/remote.c;
 * no fabricated HTTP/DACP commands or changes to the native voice agent.
 * SPDX-License-Identifier: MIT
 */
#include "rtsp.h"
#include "ap2_event_receiver.h"
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

extern ssize_t ap2_event_send_simple_modern_media_remote_command(
    rtsp_conn_info *conn, unsigned int command_number);

static const char *socket_path = "/tmp/capsula-airplay-control.sock";

static void *control_loop(void *unused) {
    (void)unused;
    int server = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    if (server < 0) return NULL;
    struct sockaddr_un sa = { .sun_family = AF_UNIX };
    snprintf(sa.sun_path, sizeof(sa.sun_path), "%s", socket_path);
    /* Never unlink a socket that may belong to another live instance. */
    if (bind(server, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
        int bind_error = errno;
        struct stat before, after;
        int probe = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
        int stale = bind_error == EADDRINUSE && probe >= 0 &&
            lstat(socket_path, &before) == 0 && S_ISSOCK(before.st_mode);
        if (stale) {
            int result = connect(probe, (struct sockaddr *)&sa, sizeof(sa));
            stale = result < 0 && errno == ECONNREFUSED &&
                lstat(socket_path, &after) == 0 &&
                before.st_dev == after.st_dev && before.st_ino == after.st_ino;
        }
        if (probe >= 0) close(probe);
        if (!stale || unlink(socket_path) != 0 ||
            bind(server, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
            close(server);
            return NULL;
        }
    }
    chmod(socket_path, 0600);
    if (listen(server, 4) != 0) {
        close(server);
        unlink(socket_path);
        return NULL;
    }
    for (;;) {
        int fd = accept4(server, NULL, NULL, SOCK_CLOEXEC);
        if (fd < 0) {
            if (errno == EINTR) continue;
            break;
        }
        struct timeval timeout = { .tv_sec = 1 };
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        char command[32] = {0};
        ssize_t n = recv(fd, command, sizeof(command)-1, MSG_TRUNC);
        const char *reply = "invalid";
        if (n > 0 && n < (ssize_t)sizeof(command)) {
            int cmd = -1;
            if (!strcmp(command, "play")) cmd = 0;
            if (!strcmp(command, "pause")) cmd = 1;
            if (!strcmp(command, "toggle")) cmd = 2;
            pthread_rwlock_rdlock(&principal_conn_lock);
            rtsp_conn_info *conn = principal_conn;
            int active = conn && conn->airplay_type == ap_2;
            if (active) {
                pthread_mutex_lock(&conn->event_sender_mutex);
                active = conn->event_channel_fd > 0;
                pthread_mutex_unlock(&conn->event_sender_mutex);
            }
            if (!strcmp(command, "state")) {
                reply = active ? "active" : "idle";
            } else if (cmd >= 0) {
                reply = "idle";
                if (active) {
                    ssize_t result = ap2_event_send_simple_modern_media_remote_command(conn, cmd);
                    reply = result > 0 ? "sent" : "failed";
                }
            }
            pthread_rwlock_unlock(&principal_conn_lock);
        }
        send(fd, reply, strlen(reply), MSG_NOSIGNAL);
        close(fd);
    }
    close(server);
    unlink(socket_path);
    return NULL;
}

void capsula_media_control_start(void) {
    static int started;
    if (started) return;
    pthread_t thread;
    if (pthread_create(&thread, NULL, control_loop, NULL) == 0) {
        started = 1;
        pthread_detach(thread);
    }
}
