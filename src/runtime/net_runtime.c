#include "zig_runtime.h"
#include <string.h>

#ifdef _WIN32
#include <winsock.h>
#pragma comment(lib, "wsock32.lib")
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/select.h>
#include <unistd.h>
#include <fcntl.h>
#endif

int plat_socket_init(void) {
#ifdef _WIN32
    WSADATA wsa;
    return WSAStartup(MAKEWORD(1, 1), &wsa);
#else
    return 0;
#endif
}

void plat_socket_cleanup(void) {
#ifdef _WIN32
    WSACleanup();
#endif
}

int plat_create_tcp_server(unsigned short port) {
#ifdef _WIN32
    SOCKET s = socket(AF_INET, SOCK_STREAM, 0);
    if (s == INVALID_SOCKET) return -1;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(s, (struct sockaddr*)&addr, sizeof(addr)) == SOCKET_ERROR) {
        closesocket(s);
        return -1;
    }
    return (int)s;
#else
    int s;
    int opt = 1;
    struct sockaddr_in addr;

    s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return -1;

    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(s, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(s);
        return -1;
    }
    return s;
#endif
}

int plat_bind_listen(int sock, int backlog) {
#ifdef _WIN32
    if (listen((SOCKET)sock, backlog) == SOCKET_ERROR) return -1;
    return 0;
#else
    if (listen(sock, backlog) < 0) return -1;
    return 0;
#endif
}

int plat_accept(int server_sock) {
#ifdef _WIN32
    SOCKET client = accept((SOCKET)server_sock, NULL, NULL);
    if (client == INVALID_SOCKET) return -1;
    return (int)client;
#else
    return accept(server_sock, NULL, NULL);
#endif
}

int plat_recv(int sock, u8* buf, int len) {
#ifdef _WIN32
    return recv((SOCKET)sock, (char*)buf, len, 0);
#else
    return recv(sock, (char*)buf, len, 0);
#endif
}

int plat_send(int sock, const u8* buf, int len) {
#ifdef _WIN32
    return send((SOCKET)sock, (const char*)buf, len, 0);
#else
    return send(sock, (const char*)buf, len, 0);
#endif
}

void plat_close_socket(int sock) {
#ifdef _WIN32
    closesocket((SOCKET)sock);
#else
    close(sock);
#endif
}

int plat_socket_select(int nfds, u8* readfds, u8* writefds, u8* exceptfds, int timeout_ms) {
    struct timeval tv;
    struct timeval* p_tv = NULL;
    if (timeout_ms >= 0) {
        tv.tv_sec = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
        p_tv = &tv;
    }
#ifdef _WIN32
    return select(nfds, (fd_set*)readfds, (fd_set*)writefds, (fd_set*)exceptfds, p_tv);
#else
    return select(nfds, (fd_set*)readfds, (fd_set*)writefds, (fd_set*)exceptfds, p_tv);
#endif
}

void plat_socket_fd_zero(u8* set) {
#ifdef _WIN32
    FD_ZERO((fd_set*)set);
#else
    FD_ZERO((fd_set*)set);
#endif
}

void plat_socket_fd_set(int fd, u8* set) {
#ifdef _WIN32
    FD_SET((SOCKET)fd, (fd_set*)set);
#else
    FD_SET(fd, (fd_set*)set);
#endif
}

int plat_socket_fd_isset(int fd, u8* set) {
#ifdef _WIN32
    return FD_ISSET((SOCKET)fd, (fd_set*)set) != 0;
#else
    return FD_ISSET(fd, (fd_set*)set) != 0;
#endif
}
