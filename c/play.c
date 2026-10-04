#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

/* Thin ANSI viewport. Soft owns the board, the active piece, next, hold,
   score, lines, and level. This process only reads keys and blits SNAP. */

enum { H = 20, W = 10, SNAP_CAP = 1 << 16, QCAP = 32 };

typedef struct {
    char board[H][W];
    int active;
    int type;
    int rot;
    int px;
    int py;
    int cx[8];
    int cy[8];
    int ncells;
    int next;
    int hold;
    int score;
    int lines;
    int level;
    int alive;
    int tick;
    int mid;
    char reason[32];
    int accepted;
} Snap;

static volatile sig_atomic_t g_stop = 0;

static void on_sig(int sig) {
    (void)sig;
    g_stop = 1;
}

static void sleep_ms(int ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    while (nanosleep(&ts, &ts) != 0) {
        if (errno != EINTR)
            break;
    }
}

static int write_all(int fd, const char *buf, size_t n) {
    size_t off = 0;
    while (off < n) {
        ssize_t w = write(fd, buf + off, n - off);
        if (w < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        if (w == 0)
            return -1;
        off += (size_t)w;
    }
    return 0;
}

static const char *piece_name(int t) {
    static const char *names[] = {"I", "J", "L", "O", "S", "T", "Z"};
    if (t < 0 || t > 6)
        return "-";
    return names[t];
}

static const char *piece_color(int t) {
    switch (t) {
    case 0: return "\033[96m";
    case 1: return "\033[94m";
    case 2: return "\033[38;5;208m";
    case 3: return "\033[93m";
    case 4: return "\033[92m";
    case 5: return "\033[95m";
    case 6: return "\033[91m";
    default: return "\033[37m";
    }
}

static int spawn_soft(char *const argv[], int *in_fd, int *out_fd, pid_t *pid) {
    int to_soft[2], from_soft[2];
    if (pipe(to_soft) != 0 || pipe(from_soft) != 0)
        return -1;
    pid_t child = fork();
    if (child < 0)
        return -1;
    if (child == 0) {
        dup2(to_soft[0], STDIN_FILENO);
        dup2(from_soft[1], STDOUT_FILENO);
        close(to_soft[0]);
        close(to_soft[1]);
        close(from_soft[0]);
        close(from_soft[1]);
        execvp(argv[0], argv);
        _exit(127);
    }
    close(to_soft[0]);
    close(from_soft[1]);
    *in_fd = to_soft[1];
    *out_fd = from_soft[0];
    *pid = child;
    return 0;
}

static int read_snap(int fd, char *buf, size_t cap, size_t *out_n) {
    size_t n = 0;
    for (;;) {
        if (n + 1 >= cap)
            return -1;
        struct pollfd p = {.fd = fd, .events = POLLIN};
        int pr = poll(&p, 1, 120000);
        if (pr < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        if (pr == 0)
            return -2;
        ssize_t r = read(fd, buf + n, cap - 1 - n);
        if (r < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        if (r == 0)
            return -3;
        n += (size_t)r;
        buf[n] = '\0';
        char *end = strstr(buf, "\nEND\n");
        if (end != NULL) {
            size_t complete = (size_t)(end - buf) + 5;
            char *snap = NULL;
            for (char *q = buf; q + 7 <= buf + complete; q++) {
                if (memcmp(q, "SNAP v1", 7) == 0 && (q == buf || q[-1] == '\n'))
                    snap = q;
            }
            if (snap != NULL) {
                size_t keep = (size_t)((buf + complete) - snap);
                memmove(buf, snap, keep);
                buf[keep] = '\0';
                *out_n = keep;
                return 0;
            }
        }
    }
}

static int parse_kv_int(const char *line, const char *key, int *out) {
    const char *p = strstr(line, key);
    if (p == NULL)
        return -1;
    p += strlen(key);
    char *end = NULL;
    long v = strtol(p, &end, 10);
    if (end == p)
        return -1;
    *out = (int)v;
    return 0;
}

static int parse_cells(const char *spec, Snap *s) {
    s->ncells = 0;
    if (spec == NULL || spec[0] == '\0')
        return 0;
    const char *p = spec;
    while (*p && s->ncells < 8) {
        char *end = NULL;
        long x = strtol(p, &end, 10);
        if (end == p || *end != ',')
            return -1;
        const char *ys = end + 1;
        long y = strtol(ys, &end, 10);
        if (end == ys)
            return -1;
        s->cx[s->ncells] = (int)x;
        s->cy[s->ncells] = (int)y;
        s->ncells++;
        p = end;
        if (*p == ';')
            p++;
        else
            break;
    }
    return 0;
}

static int parse_snap(const char *text, Snap *s) {
    memset(s, 0, sizeof(*s));
    s->hold = -1;
    s->next = -1;
    int row = 0;
    int saw_board = 0;
    int saw_score = 0;
    int saw_end = 0;
    const char *p = text;
    while (*p) {
        const char *nl = strchr(p, '\n');
        char line[256];
        size_t len = nl == NULL ? strlen(p) : (size_t)(nl - p);
        if (len >= sizeof(line))
            len = sizeof(line) - 1;
        memcpy(line, p, len);
        line[len] = '\0';
        if (strcmp(line, "SNAP v1") == 0) {
            /* header */
        } else if (strcmp(line, "BOARD") == 0) {
            saw_board = 1;
        } else if (saw_board && row < H && strncmp(line, "PIECE ", 6) != 0) {
            if ((int)strlen(line) < W)
                return 0;
            memcpy(s->board[row], line, (size_t)W);
            row++;
        } else if (strncmp(line, "PIECE ", 6) == 0) {
            saw_board = 0;
            if (parse_kv_int(line, "active=", &s->active) != 0)
                return 0;
            if (parse_kv_int(line, "type=", &s->type) != 0)
                return 0;
            if (parse_kv_int(line, "rot=", &s->rot) != 0)
                return 0;
            if (parse_kv_int(line, "x=", &s->px) != 0)
                return 0;
            if (parse_kv_int(line, "y=", &s->py) != 0)
                return 0;
            const char *cells = strstr(line, "cells=");
            if (cells == NULL || parse_cells(cells + 6, s) != 0)
                return 0;
        } else if (strncmp(line, "NEXT ", 5) == 0) {
            s->next = atoi(line + 5);
        } else if (strncmp(line, "HOLD ", 5) == 0) {
            s->hold = atoi(line + 5);
        } else if (strncmp(line, "SCORE ", 6) == 0) {
            if (parse_kv_int(line, "score=", &s->score) != 0)
                return 0;
            if (parse_kv_int(line, "lines=", &s->lines) != 0)
                return 0;
            if (parse_kv_int(line, "level=", &s->level) != 0)
                return 0;
            saw_score = 1;
        } else if (strncmp(line, "STATUS ", 7) == 0) {
            if (parse_kv_int(line, "alive=", &s->alive) != 0)
                return 0;
            if (parse_kv_int(line, "tick=", &s->tick) != 0)
                return 0;
        } else if (strncmp(line, "MID ", 4) == 0) {
            if (parse_kv_int(line, "mid=", &s->mid) != 0)
                return 0;
            const char *r = strstr(line, "reason=");
            if (r == NULL)
                return 0;
            snprintf(s->reason, sizeof(s->reason), "%s", r + 7);
        } else if (strcmp(line, "END") == 0) {
            saw_end = 1;
        }
        if (nl == NULL)
            break;
        p = nl + 1;
    }
    s->accepted = (row == H && saw_score && saw_end) ? 1 : 0;
    return s->accepted;
}

static int cell_at(const Snap *s, int x, int y, int *type_out) {
    for (int i = 0; i < s->ncells; i++) {
        if (s->cx[i] == x && s->cy[i] == y) {
            *type_out = s->type;
            return 1;
        }
    }
    return 0;
}

static void blit(int tty, const Snap *s, int paused) {
    char frame[8192];
    size_t n = 0;
    int room = (int)sizeof(frame);
    const char *banner = paused ? "PAUSED" : (s->alive ? "RUN" : "TOPOUT");
    int wr = snprintf(frame + n, (size_t)room,
                      "\033[2J\033[H\033[1maura-tetris\033[0m  %s\n"
                      "+--------------------+\n",
                      banner);
    if (wr < 0 || wr >= room)
        return;
    n += (size_t)wr;
    room -= wr;
    for (int y = 0; y < H; y++) {
        wr = snprintf(frame + n, (size_t)room, "|");
        if (wr < 0 || wr >= room)
            return;
        n += (size_t)wr;
        room -= wr;
        for (int x = 0; x < W; x++) {
            int pt = 0;
            const char *col;
            const char *glyph;
            if (cell_at(s, x, y, &pt)) {
                col = piece_color(pt);
                glyph = "[]";
            } else if (s->board[y][x] >= '1' && s->board[y][x] <= '7') {
                col = piece_color(s->board[y][x] - '1');
                glyph = "##";
            } else {
                col = "\033[2m";
                glyph = "..";
            }
            wr = snprintf(frame + n, (size_t)room, "%s%s\033[0m", col, glyph);
            if (wr < 0 || wr >= room)
                return;
            n += (size_t)wr;
            room -= wr;
        }
        wr = snprintf(frame + n, (size_t)room, "|\n");
        if (wr < 0 || wr >= room)
            return;
        n += (size_t)wr;
        room -= wr;
    }
    wr = snprintf(frame + n, (size_t)room,
                  "+--------------------+\n"
                  "score %d   lines %d   level %d   tick %d\n"
                  "next %s   hold %s   mid %d   %s\n"
                  "a/d move  s soft  w/space hard  z/q ccw  e/x cw\n"
                  "c hold  f strategy-step  p pause  r restart  Esc/Q quit\n",
                  s->score, s->lines, s->level, s->tick,
                  piece_name(s->next), piece_name(s->hold), s->mid, s->reason);
    if (wr < 0 || wr >= room)
        return;
    n += (size_t)wr;
    if (tty >= 0)
        write_all(tty, frame, n);
    else {
        fwrite(frame, 1, n, stdout);
        fflush(stdout);
    }
}

static int open_tty(void) {
    return open("/dev/tty", O_RDWR | O_NONBLOCK);
}

enum {
    VK_NONE = 0,
    VK_LEFT,
    VK_RIGHT,
    VK_SOFT,
    VK_HARD,
    VK_CW,
    VK_CCW,
    VK_HOLD,
    VK_AUTO,
    VK_PAUSE,
    VK_RESTART,
    VK_QUIT
};

static const char *verb_of(int k) {
    switch (k) {
    case VK_LEFT: return "left";
    case VK_RIGHT: return "right";
    case VK_SOFT: return "soft";
    case VK_HARD: return "hard";
    case VK_CW: return "cw";
    case VK_CCW: return "ccw";
    case VK_HOLD: return "hold";
    case VK_AUTO: return "auto";
    case VK_RESTART: return "restart";
    case VK_QUIT: return "quit";
    default: return NULL;
    }
}

static int map_key(unsigned char ch) {
    switch (ch) {
    case 'a':
    case 'A': return VK_LEFT;
    case 'd':
    case 'D': return VK_RIGHT;
    case 's':
    case 'S': return VK_SOFT;
    case 'w':
    case 'W':
    case ' ': return VK_HARD;
    case 'e':
    case 'E':
    case 'x':
    case 'X': return VK_CW;
    case 'q':
    case 'z':
    case 'Z': return VK_CCW;
    case 'Q': return VK_QUIT;
    case 'c':
    case 'C': return VK_HOLD;
    case 'f':
    case 'F': return VK_AUTO;
    case 'p':
    case 'P': return VK_PAUSE;
    case 'r':
    case 'R': return VK_RESTART;
    case 27: return VK_QUIT;
    default: return VK_NONE;
    }
}

static int gq[QCAP];
static int gqn = 0;

static void push_key(int k) {
    if (k == VK_NONE || gqn >= QCAP)
        return;
    gq[gqn++] = k;
}

static int pop_key(void) {
    if (gqn <= 0)
        return VK_NONE;
    int k = gq[0];
    memmove(gq, gq + 1, (size_t)(gqn - 1) * sizeof(int));
    gqn--;
    return k;
}

static void drain_keys(int tty) {
    if (tty < 0)
        return;
    for (;;) {
        struct pollfd p = {.fd = tty, .events = POLLIN};
        if (poll(&p, 1, 0) <= 0)
            break;
        unsigned char ch = 0;
        if (read(tty, &ch, 1) != 1)
            break;
        if (ch == 27) {
            struct pollfd p2 = {.fd = tty, .events = POLLIN};
            if (poll(&p2, 1, 15) > 0) {
                unsigned char seq[8];
                ssize_t nr = read(tty, seq, sizeof(seq));
                if (nr >= 2 && seq[0] == '[') {
                    if (seq[1] == 'D')
                        push_key(VK_LEFT);
                    else if (seq[1] == 'C')
                        push_key(VK_RIGHT);
                    else if (seq[1] == 'B')
                        push_key(VK_SOFT);
                    else if (seq[1] == 'A')
                        push_key(VK_HARD);
                }
                continue;
            }
            push_key(VK_QUIT);
            continue;
        }
        push_key(map_key(ch));
    }
}

static int send_verb(int fd, const char *verb) {
    char line[64];
    int n = snprintf(line, sizeof(line), "INPUT %s\n", verb);
    if (n < 0 || n >= (int)sizeof(line))
        return -1;
    return write_all(fd, line, (size_t)n);
}

static void usage(const char *argv0) {
    fprintf(stderr,
            "usage: %s -- soft-command [args...]\n"
            "       Soft child speaks SNAP on stdout; accepts INPUT verbs on stdin.\n",
            argv0);
}

int main(int argc, char **argv) {
    int soft_i = -1;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--") == 0) {
            soft_i = i + 1;
            break;
        }
    }
    if (soft_i < 0 || soft_i >= argc) {
        usage(argv[0]);
        return 2;
    }

    signal(SIGINT, on_sig);
    signal(SIGTERM, on_sig);

    int soft_in = -1, soft_out = -1;
    pid_t soft_pid = -1;
    if (spawn_soft(&argv[soft_i], &soft_in, &soft_out, &soft_pid) != 0) {
        fprintf(stderr, "tetris_play: cannot spawn Soft child\n");
        return 1;
    }

    int tty = open_tty();
    struct termios saved, raw;
    int raw_on = 0;
    if (tty >= 0 && tcgetattr(tty, &saved) == 0) {
        raw = saved;
        raw.c_lflag &= (tcflag_t)~(ICANON | ECHO);
        raw.c_cc[VMIN] = 0;
        raw.c_cc[VTIME] = 0;
        if (tcsetattr(tty, TCSANOW, &raw) == 0)
            raw_on = 1;
    }

    char *snapbuf = malloc(SNAP_CAP);
    if (snapbuf == NULL) {
        fprintf(stderr, "tetris_play: oom\n");
        return 1;
    }

    fprintf(stderr, "tetris_play: waiting for Soft world...\n");
    Snap snap;
    size_t snap_n = 0;
    if (read_snap(soft_out, snapbuf, SNAP_CAP, &snap_n) != 0 ||
        !parse_snap(snapbuf, &snap)) {
        fprintf(stderr, "tetris_play: Soft did not produce an initial SNAP\n");
        g_stop = 1;
    } else {
        blit(tty, &snap, 0);
    }

    int paused = 0;
    while (!g_stop) {
        drain_keys(tty);
        int k = pop_key();
        if (k == VK_QUIT) {
            send_verb(soft_in, "quit");
            break;
        }
        if (k == VK_PAUSE)
            paused = !paused;

        const char *verb = NULL;
        if (k != VK_NONE && k != VK_PAUSE)
            verb = verb_of(k);
        else if (!paused && snap.alive && k == VK_NONE)
            verb = "tick";
        else {
            blit(tty, &snap, paused);
            sleep_ms(40);
            continue;
        }

        if (verb == NULL) {
            sleep_ms(20);
            continue;
        }
        if (!snap.alive && strcmp(verb, "restart") != 0 && strcmp(verb, "quit") != 0) {
            blit(tty, &snap, paused);
            sleep_ms(40);
            continue;
        }
        if (send_verb(soft_in, verb) != 0) {
            fprintf(stderr, "tetris_play: Soft stdin closed\n");
            break;
        }
        int rs = read_snap(soft_out, snapbuf, SNAP_CAP, &snap_n);
        if (rs != 0) {
            fprintf(stderr, "tetris_play: Soft SNAP read failed (%d)\n", rs);
            break;
        }
        if (!parse_snap(snapbuf, &snap)) {
            fprintf(stderr, "tetris_play: Soft SNAP parse failed\n");
            break;
        }
        blit(tty, &snap, paused);
        if (strcmp(verb, "tick") == 0)
            sleep_ms(40);
    }

    if (raw_on)
        tcsetattr(tty, TCSANOW, &saved);
    if (tty >= 0)
        close(tty);
    if (soft_in >= 0)
        close(soft_in);
    if (soft_out >= 0)
        close(soft_out);
    if (soft_pid > 0) {
        kill(soft_pid, SIGTERM);
        waitpid(soft_pid, NULL, 0);
    }
    free(snapbuf);
    return 0;
}
