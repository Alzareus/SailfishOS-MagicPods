/*
 * Console AAP (AirPods) sur socket L2CAP brut.
 * Lecture des notifications et envoi de commandes.
 *
 * Aucune dependance : ni libbluetooth, ni en-tetes BlueZ.
 *
 * Compilation :
 *   gcc -O2 -Wall -o aapconsole aapconsole.c
 *
 * Usage :
 *   ./aapconsole 20:15:82:D3:15:DB
 *
 * Commandes au clavier :
 *   off | anc | transparency | adaptive   bascule le controle du bruit
 *   <hexa>                                envoie une trame brute, ex: 040004000900 0d02000000
 *   quit                                  quitte
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/types.h>

#ifndef AF_BLUETOOTH
#define AF_BLUETOOTH 31
#endif
#define BTPROTO_L2CAP 0
#define AAP_PSM 0x1001

#define CMD_BATTERY  0x04
#define CMD_SETTINGS 0x09

struct sockaddr_l2_min {
    sa_family_t    l2_family;
    unsigned short l2_psm;
    unsigned char  l2_bdaddr[6];
    unsigned short l2_cid;
    unsigned char  l2_bdaddr_type;
};

static const unsigned char INIT_FRAME[] = {
    0x00, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};
static const unsigned char NOTIF_1[] = {
    0x04, 0x00, 0x04, 0x00, 0x0f, 0x00, 0xff, 0xff, 0xef, 0xff
};
static const unsigned char NOTIF_2[] = {
    0x04, 0x00, 0x04, 0x00, 0x0f, 0x00, 0xff, 0xff, 0xff, 0xff
};

struct setting_name {
    unsigned char id;
    const char *name;
};

static const struct setting_name SETTINGS[] = {
    { 0x0d, "controle du bruit" },
    { 0x17, "vitesse d'appui" },
    { 0x18, "duree d'appui long" },
    { 0x1b, "ANC avec un seul ecouteur" },
    { 0x1f, "volume des tonalites" },
    { 0x23, "longueur du balayage de volume" },
    { 0x24, "fin d'appel" },
    { 0x25, "balayage de volume" },
    { 0x26, "volume personnalise" },
    { 0x28, "conversation awareness" },
    { 0x2e, "bruit en mode adaptatif" },
    { 0x00, NULL }
};

static const char *anc_mode_name(unsigned char value)
{
    switch (value) {
    case 0x01: return "desactive";
    case 0x02: return "reduction de bruit";
    case 0x03: return "transparence";
    case 0x04: return "adaptatif";
    default:   return "inconnu";
    }
}

static const char *battery_type_name(unsigned char type)
{
    switch (type) {
    case 0x01: return "unite";
    case 0x02: return "droite";
    case 0x04: return "gauche";
    case 0x08: return "boitier";
    default:   return NULL;
    }
}

static const char *charging_name(unsigned char status)
{
    switch (status) {
    case 0x00: return "indefini";
    case 0x01: return "en charge";
    case 0x02: return "pas en charge";
    case 0x04: return "deconnecte";
    default:   return NULL;
    }
}

static void decode_battery(const unsigned char *data, ssize_t len)
{
    int count = data[6];
    int i, pos = 7, printed = 0;

    for (i = 0; i < count; i++) {
        const char *type_name;
        const char *status_name;

        if (pos + 4 >= (int)len)
            break;

        type_name = battery_type_name(data[pos]);
        status_name = charging_name(data[pos + 3]);

        if (type_name && status_name) {
            if (!printed) {
                printf("     BATTERIE:");
                printed = 1;
            }
            printf(" %s %d%% (%s)", type_name, data[pos + 2], status_name);
        }

        pos += 5;
    }

    if (printed)
        printf("\n");
}

static void decode_settings(const unsigned char *data, ssize_t len)
{
    unsigned char id;
    int i;

    if (len < 8)
        return;

    id = data[6];

    for (i = 0; SETTINGS[i].name != NULL; i++) {
        if (SETTINGS[i].id != id)
            continue;

        printf("     REGLAGE: %s = %d", SETTINGS[i].name, data[7]);
        if (id == 0x0d)
            printf(" (%s)", anc_mode_name(data[7]));
        printf("\n");
        return;
    }

    printf("     REGLAGE: id 0x%02x = %d (non repertorie)\n", id, data[7]);
}

static void decode(const unsigned char *data, ssize_t len)
{
    if (len < 7)
        return;

    if (data[4] == CMD_BATTERY && len >= 11)
        decode_battery(data, len);
    else if (data[4] == CMD_SETTINGS)
        decode_settings(data, len);
}

static void dump(const char *prefix, const unsigned char *data, ssize_t len)
{
    ssize_t i;

    printf("%s", prefix);
    for (i = 0; i < len; i++)
        printf("%02x", data[i]);
    printf("\n");
}

static int send_frame(int fd, const unsigned char *frame, size_t len)
{
    if (send(fd, frame, len, 0) < 0) {
        fprintf(stderr, "ECHEC send(): %s\n", strerror(errno));
        return -1;
    }

    dump("  -> ", frame, (ssize_t)len);
    return 0;
}

static int send_anc(int fd, unsigned char mode)
{
    unsigned char frame[11] = {
        0x04, 0x00, 0x04, 0x00, CMD_SETTINGS, 0x00, 0x0d, 0x00, 0x00, 0x00, 0x00
    };

    frame[7] = mode;
    printf("  Bascule du controle du bruit vers: %s\n", anc_mode_name(mode));
    return send_frame(fd, frame, sizeof(frame));
}

static int hex_value(char c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}

static int parse_hex(const char *line, unsigned char *out, size_t max)
{
    size_t count = 0;
    int high = -1;

    while (*line) {
        int v;

        if (isspace((unsigned char)*line) || *line == ':') {
            line++;
            continue;
        }

        v = hex_value(*line);
        if (v < 0)
            return -1;

        if (high < 0) {
            high = v;
        } else {
            if (count >= max)
                return -1;
            out[count++] = (unsigned char)((high << 4) | v);
            high = -1;
        }

        line++;
    }

    if (high >= 0)
        return -1;

    return (int)count;
}

static int handle_input(int fd, char *line)
{
    unsigned char frame[512];
    int len;
    size_t n = strlen(line);

    while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r'))
        line[--n] = '\0';

    if (n == 0)
        return 0;

    if (strcmp(line, "quit") == 0 || strcmp(line, "exit") == 0)
        return 1;

    if (strcmp(line, "off") == 0)
        return send_anc(fd, 0x01) < 0 ? 1 : 0;
    if (strcmp(line, "anc") == 0)
        return send_anc(fd, 0x02) < 0 ? 1 : 0;
    if (strcmp(line, "transparency") == 0)
        return send_anc(fd, 0x03) < 0 ? 1 : 0;
    if (strcmp(line, "adaptive") == 0)
        return send_anc(fd, 0x04) < 0 ? 1 : 0;

    len = parse_hex(line, frame, sizeof(frame));
    if (len <= 0) {
        printf("  Entree non reconnue. Attendu: off|anc|transparency|adaptive|quit, ou une trame hexa.\n");
        return 0;
    }

    return send_frame(fd, frame, (size_t)len) < 0 ? 1 : 0;
}

static int parse_mac(const char *str, unsigned char out[6])
{
    unsigned int b[6];
    int i;

    if (sscanf(str, "%x:%x:%x:%x:%x:%x",
               &b[0], &b[1], &b[2], &b[3], &b[4], &b[5]) != 6)
        return -1;

    for (i = 0; i < 6; i++)
        out[i] = (unsigned char)b[5 - i];

    return 0;
}

int main(int argc, char **argv)
{
    struct sockaddr_l2_min addr;
    struct pollfd fds[2];
    unsigned char buf[1024];
    char line[1024];
    int fd;

    if (argc != 2) {
        fprintf(stderr, "Usage: %s AA:BB:CC:DD:EE:FF\n", argv[0]);
        return 2;
    }

    memset(&addr, 0, sizeof(addr));
    addr.l2_family = AF_BLUETOOTH;
    addr.l2_psm = AAP_PSM;

    if (parse_mac(argv[1], addr.l2_bdaddr) != 0) {
        fprintf(stderr, "Adresse MAC invalide: %s\n", argv[1]);
        return 2;
    }

    fd = socket(AF_BLUETOOTH, SOCK_SEQPACKET, BTPROTO_L2CAP);
    if (fd < 0) {
        fprintf(stderr, "ECHEC socket(): %s\n", strerror(errno));
        return 1;
    }

    printf("Connexion L2CAP vers %s PSM 0x%04x ...\n", argv[1], AAP_PSM);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        fprintf(stderr, "ECHEC connect(): %s\n", strerror(errno));
        close(fd);
        return 1;
    }

    printf("OK: socket L2CAP ouvert.\n");

    send_frame(fd, INIT_FRAME, sizeof(INIT_FRAME));
    usleep(200000);
    send_frame(fd, NOTIF_1, sizeof(NOTIF_1));
    usleep(200000);
    send_frame(fd, NOTIF_2, sizeof(NOTIF_2));

    printf("\nCommandes: off | anc | transparency | adaptive | <trame hexa> | quit\n\n");

    fds[0].fd = fd;
    fds[0].events = POLLIN;
    fds[1].fd = STDIN_FILENO;
    fds[1].events = POLLIN;

    for (;;) {
        if (poll(fds, 2, -1) < 0) {
            if (errno == EINTR)
                continue;
            fprintf(stderr, "ECHEC poll(): %s\n", strerror(errno));
            break;
        }

        if (fds[0].revents & POLLIN) {
            ssize_t n = recv(fd, buf, sizeof(buf), 0);

            if (n < 0) {
                fprintf(stderr, "ECHEC recv(): %s\n", strerror(errno));
                break;
            }
            if (n == 0) {
                printf("Socket ferme par le peripherique.\n");
                break;
            }

            dump("  <- ", buf, n);
            decode(buf, n);
            fflush(stdout);
        }

        if (fds[1].revents & POLLIN) {
            if (fgets(line, sizeof(line), stdin) == NULL)
                break;
            if (handle_input(fd, line))
                break;
            fflush(stdout);
        }
    }

    close(fd);
    return 0;
}
