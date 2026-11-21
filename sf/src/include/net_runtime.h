#ifndef NET_RUNTIME_H
#define NET_RUNTIME_H

#include "zig_runtime.h"

int plat_socket_init(void);
void plat_socket_cleanup(void);
int plat_create_tcp_server(unsigned short port);
int plat_bind_listen(int sock, int backlog);
int plat_accept(int server_sock);
int plat_recv(int sock, u8* buf, int len);
int plat_send(int sock, const u8* buf, int len);
void plat_close_socket(int sock);
int plat_socket_select(int nfds, u8* readfds, u8* writefds, u8* exceptfds, int timeout_ms);
void plat_socket_fd_zero(u8* set);
void plat_socket_fd_set(int fd, u8* set);
int plat_socket_fd_isset(int fd, u8* set);

#endif
