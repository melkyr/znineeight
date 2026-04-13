# Z98 Networking Platform Abstraction Layer (PAL)

The Z98 networking PAL provides a minimal, cross-platform socket API compatible with Windows 98 (Winsock 1.1) and POSIX-compliant systems.

## API Reference

### Core Functions

```c
int plat_socket_init(void);
```
Initializes the networking subsystem. Must be called once before any other socket functions. On Windows, this calls `WSAStartup`. Returns 0 on success.

```c
void plat_socket_cleanup(void);
```
Cleans up the networking subsystem. Should be called before program exit. On Windows, this calls `WSACleanup`.

```c
PlatSocket plat_create_tcp_server(u16 port);
```
Creates a TCP socket, binds it to the specified port on all interfaces, and prepares it for listening. Returns `PLAT_INVALID_SOCKET` on failure.

```c
int plat_bind_listen(PlatSocket sock, int backlog);
```
Places the socket in a state where it is listening for incoming connections.

```c
PlatSocket plat_accept(PlatSocket server_sock);
```
Accepts an incoming connection. Returns a new socket for the client. Note: This implementation does not return the client's address to keep the API simple.

```c
int plat_recv(PlatSocket sock, char* buf, int len);
```
Receives data from a socket. Returns the number of bytes received, 0 if the connection was closed, or -1 on error.

```c
int plat_send(PlatSocket sock, const char* buf, int len);
```
Sends data over a socket. Returns the number of bytes sent.

```c
void plat_close_socket(PlatSocket sock);
```
Closes a socket.

### Multiplexing (select)

The PAL uses a simplified `select` model with an opaque `fd_set` type.

```c
typedef struct {
    u8 data[256];
} plat_fd_set;
```

```c
int plat_socket_select(int nfds, plat_fd_set* readfds, plat_fd_set* writefds, plat_fd_set* exceptfds, int timeout_ms);
```
Monitors multiple sockets for activity. `timeout_ms` specifies the wait time (-1 for infinite).

```c
void plat_socket_fd_zero(plat_fd_set* s);
void plat_socket_fd_set(PlatSocket fd, plat_fd_set* s);
bool plat_socket_fd_isset(PlatSocket fd, plat_fd_set* s);
```
Helpers for manipulating the `plat_fd_set`.

## Platform-Specific Details

### Windows 98
- Uses `wsock32.lib`.
- Compatible with Winsock 1.1.
- `PLAT_INVALID_SOCKET` is mapped to `INVALID_SOCKET`.

### POSIX (Linux/BSD)
- Uses standard `<sys/socket.h>` and related headers.
- `PLAT_INVALID_SOCKET` is -1.
- `plat_create_tcp_server` uses `SO_REUSEADDR` for better development experience.
