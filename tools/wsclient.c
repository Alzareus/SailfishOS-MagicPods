/*
 * Client WebSocket minimal en ligne de commande.
 * Concu pour dialoguer avec magicpodscore sur 127.0.0.1:2020.
 *
 * Aucune dependance externe.
 *
 * Compilation :
 *   gcc -O2 -Wall -o wsclient wsclient.c
 *
 * Usage :
 *   ./wsclient                 se connecte a 127.0.0.1:2020
 *   ./wsclient 127.0.0.1 2020  hote et port explicites
 *
 * Une fois connecte, tape une commande JSON par ligne :
 *   {"method":"GetAll"}
 *   {"method":"GetDevices"}
 * Raccourcis : all, devices, info, adapter, quit
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <poll.h>
#include <netdb.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define DEFAULT_HOST "127.0.0.1"
#define DEFAULT_PORT "2020"
#define BUF_SIZE 262144

static const char BASE64_CHARS[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void base64_encode(const unsigned char *in, size_t len, char *out)
{
    size_t i, o = 0;

    for (i = 0; i < len; i += 3) {
        unsigned int block = (unsigned int)in[i] << 16;
        size_t remaining = len - i;

        if (remaining > 1)
            block |= (unsigned int)in[i + 1] << 8;
        if (remaining > 2)
            block |= (unsigned int)in[i + 2];

        out[o++] = BASE64_CHARS[(block >> 18) & 0x3f];
        out[o++] = BASE64_CHARS[(block >> 12) & 0x3f];
        out[o++] = remaining > 1 ? BASE64_CHARS[(block >> 6) & 0x3f] : '=';
        out[o++] = remaining > 2 ? BASE64_CHARS[block & 0x3f] : '=';
    }

    out[o] = '\0';
}

static int tcp_connect(const char *host, const char *port)
{
    struct addrinfo hints;
    struct addrinfo *result;
    struct addrinfo *entry;
    int fd = -1;
    int rc;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    rc = getaddrinfo(host, port, &hints, &result);
    if (rc != 0) {
        fprintf(stderr, "ECHEC getaddrinfo(): %s\n", gai_strerror(rc));
        return -1;
    }

    for (entry = result; entry != NULL; entry = entry->ai_next) {
        fd = socket(entry->ai_family, entry->ai_socktype, entry->ai_protocol);
        if (fd < 0)
            continue;
        if (connect(fd, entry->ai_addr, entry->ai_addrlen) == 0)
            break;
        close(fd);
        fd = -1;
    }

    freeaddrinfo(result);

    if (fd < 0)
        fprintf(stderr, "ECHEC connect(): %s\n", strerror(errno));

    return fd;
}

static int ws_handshake(int fd, const char *host, const char *port)
{
    unsigned char nonce[16];
    char key[32];
    char request[512];
    char response[2048];
    ssize_t n;
    int i;

    srand((unsigned int)time(NULL) ^ (unsigned int)getpid());
    for (i = 0; i < 16; i++)
        nonce[i] = (unsigned char)(rand() & 0xff);

    base64_encode(nonce, sizeof(nonce), key);

    snprintf(request, sizeof(request),
             "GET / HTTP/1.1\r\n"
             "Host: %s:%s\r\n"
             "Upgrade: websocket\r\n"
             "Connection: Upgrade\r\n"
             "Sec-WebSocket-Key: %s\r\n"
             "Sec-WebSocket-Version: 13\r\n"
             "\r\n",
             host, port, key);

    if (send(fd, request, strlen(request), 0) < 0) {
        fprintf(stderr, "ECHEC envoi de la poignee de main: %s\n", strerror(errno));
        return -1;
    }

    n = recv(fd, response, sizeof(response) - 1, 0);
    if (n <= 0) {
        fprintf(stderr, "Pas de reponse a la poignee de main.\n");
        return -1;
    }

    response[n] = '\0';

    if (strstr(response, "101") == NULL) {
        fprintf(stderr, "Poignee de main refusee:\n%s\n", response);
        return -1;
    }

    return 0;
}

static int ws_send_text(int fd, const char *text)
{
    unsigned char header[14];
    unsigned char mask[4];
    unsigned char *payload;
    size_t len = strlen(text);
    size_t header_len = 0;
    size_t i;
    int ok;

    header[header_len++] = 0x81; /* FIN + opcode texte */

    if (len < 126) {
        header[header_len++] = (unsigned char)(0x80 | len);
    } else if (len < 65536) {
        header[header_len++] = 0x80 | 126;
        header[header_len++] = (unsigned char)((len >> 8) & 0xff);
        header[header_len++] = (unsigned char)(len & 0xff);
    } else {
        int shift;
        header[header_len++] = 0x80 | 127;
        for (shift = 56; shift >= 0; shift -= 8)
            header[header_len++] = (unsigned char)((len >> shift) & 0xff);
    }

    for (i = 0; i < 4; i++) {
        mask[i] = (unsigned char)(rand() & 0xff);
        header[header_len++] = mask[i];
    }

    payload = malloc(len ? len : 1);
    if (payload == NULL)
        return -1;

    for (i = 0; i < len; i++)
        payload[i] = (unsigned char)text[i] ^ mask[i % 4];

    ok = send(fd, header, header_len, 0) >= 0 && send(fd, payload, len, 0) >= 0;
    free(payload);

    if (!ok)
        fprintf(stderr, "ECHEC send(): %s\n", strerror(errno));

    return ok ? 0 : -1;
}

static int recv_exact(int fd, unsigned char *buf, size_t len)
{
    size_t got = 0;

    while (got < len) {
        ssize_t n = recv(fd, buf + got, len - got, 0);
        if (n <= 0)
            return -1;
        got += (size_t)n;
    }

    return 0;
}

static int ws_read_frame(int fd, unsigned char *buf, size_t max, size_t *out_len)
{
    unsigned char header[2];
    unsigned char ext[8];
    unsigned char opcode;
    unsigned long long len;

    if (recv_exact(fd, header, 2) != 0)
        return -1;

    opcode = header[0] & 0x0f;
    len = header[1] & 0x7f;

    if (len == 126) {
        if (recv_exact(fd, ext, 2) != 0)
            return -1;
        len = ((unsigned long long)ext[0] << 8) | ext[1];
    } else if (len == 127) {
        int i;
        if (recv_exact(fd, ext, 8) != 0)
            return -1;
        len = 0;
        for (i = 0; i < 8; i++)
            len = (len << 8) | ext[i];
    }

    if (len >= max) {
        fprintf(stderr, "Trame trop grande (%llu octets), ignoree.\n", len);
        return -1;
    }

    if (len > 0 && recv_exact(fd, buf, (size_t)len) != 0)
        return -1;

    buf[len] = '\0';
    *out_len = (size_t)len;

    if (opcode == 0x08) /* fermeture */
        return 1;

    if (opcode == 0x09) { /* ping : repondre par un pong, sinon le serveur coupe */
        unsigned char pong[4 + 2 + 125];
        unsigned char pong_mask[4];
        size_t i;

        if (len > 125)
            return 2;

        pong[0] = 0x8a; /* FIN + opcode pong */
        pong[1] = (unsigned char)(0x80 | len);

        for (i = 0; i < 4; i++) {
            pong_mask[i] = (unsigned char)(rand() & 0xff);
            pong[2 + i] = pong_mask[i];
        }

        for (i = 0; i < len; i++)
            pong[6 + i] = buf[i] ^ pong_mask[i % 4];

        if (send(fd, pong, 6 + len, 0) < 0)
            return -1;

        return 2;
    }

    return 0;
}

static const char *expand_shortcut(const char *line)
{
    if (strcmp(line, "all") == 0)
        return "{\"method\":\"GetAll\"}";
    if (strcmp(line, "devices") == 0)
        return "{\"method\":\"GetDevices\"}";
    if (strcmp(line, "info") == 0)
        return "{\"method\":\"GetActiveDeviceInfo\"}";
    if (strcmp(line, "adapter") == 0)
        return "{\"method\":\"GetDefaultBluetoothAdapter\"}";
    return NULL;
}

int main(int argc, char **argv)
{
    const char *host = argc > 1 ? argv[1] : DEFAULT_HOST;
    const char *port = argc > 2 ? argv[2] : DEFAULT_PORT;
    struct pollfd fds[2];
    unsigned char *buf;
    char line[8192];
    int fd;

    buf = malloc(BUF_SIZE);
    if (buf == NULL) {
        fprintf(stderr, "Memoire insuffisante.\n");
        return 1;
    }

    printf("Connexion a %s:%s ...\n", host, port);

    fd = tcp_connect(host, port);
    if (fd < 0) {
        free(buf);
        return 1;
    }

    if (ws_handshake(fd, host, port) != 0) {
        close(fd);
        free(buf);
        return 1;
    }

    printf("WebSocket etabli.\n");
    printf("Raccourcis: all | devices | info | adapter | quit\n");
    printf("Ou colle un JSON, ex: {\"method\":\"GetAll\"}\n\n");

    fds[0].fd = fd;
    fds[0].events = POLLIN;
    fds[1].fd = STDIN_FILENO;
    fds[1].events = POLLIN;

    for (;;) {
        if (poll(fds, 2, -1) < 0) {
            if (errno == EINTR)
                continue;
            break;
        }

        if (fds[0].revents & POLLIN) {
            size_t len = 0;
            int rc = ws_read_frame(fd, buf, BUF_SIZE, &len);

            if (rc < 0)
                break;
            if (rc == 1) {
                printf("Connexion fermee par le serveur.\n");
                break;
            }
            if (rc == 0 && len > 0)
                printf("<- %s\n\n", buf);

            fflush(stdout);
        }

        if (fds[1].revents & POLLIN) {
            const char *shortcut;
            size_t n;

            if (fgets(line, sizeof(line), stdin) == NULL)
                break;

            n = strlen(line);
            while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r'))
                line[--n] = '\0';

            if (n == 0)
                continue;
            if (strcmp(line, "quit") == 0 || strcmp(line, "exit") == 0)
                break;

            shortcut = expand_shortcut(line);
            if (shortcut != NULL) {
                printf("-> %s\n", shortcut);
                if (ws_send_text(fd, shortcut) != 0)
                    break;
            } else {
                printf("-> %s\n", line);
                if (ws_send_text(fd, line) != 0)
                    break;
            }

            fflush(stdout);
        }
    }

    close(fd);
    free(buf);
    return 0;
}
