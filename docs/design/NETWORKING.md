# Z98 Networking API

This document describes the minimal socket-based networking API provided by the Z98 Platform Abstraction Layer (PAL). This API is designed to be compatible with both 1998-era Windows (Winsock 1.1) and modern POSIX environments.

## Data Types

### `PlatSocket`
A platform-specific handle for a socket.
- **Windows**: `SOCKET` (from `winsock.h`)
- **POSIX**: `int`

### `PLAT_INVALID_SOCKET`
The value representing an invalid socket handle.
- **Windows**: `INVALID_SOCKET`
- **POSIX**: `-1`

### `plat_fd_set`
A structure for managing sets of sockets, used with `plat_socket_select`. Maps directly to the platform's `fd_set`.

## Functions

### `int plat_socket_init(void)`
Initializes the underlying networking subsystem.
- **Windows**: Calls `WSAStartup`.
- **POSIX**: Returns 0 (no initialization needed).
- **Return**: 0 on success, non-zero on failure.

### `void plat_socket_cleanup(void)`
Cleans up the networking subsystem.
- **Windows**: Calls `WSACleanup`.
- **POSIX**: Does nothing.

### `PlatSocket plat_create_tcp_server(u16 port)`
Creates a TCP socket, binds it to all available interfaces on the specified port, and prepares it for listening.
- **Return**: A valid `PlatSocket`, or `PLAT_INVALID_SOCKET` on error.

### `int plat_bind_listen(PlatSocket sock, int backlog)`
Places the socket in a state where it is listening for incoming connections.
- **Return**: 0 on success, -1 on error.

### `PlatSocket plat_accept(PlatSocket server_sock)`
Accepts a pending connection on a listening socket.
- **Return**: A new `PlatSocket` for the accepted connection, or `PLAT_INVALID_SOCKET` on error.

### `int plat_recv(PlatSocket sock, char* buf, int len)`
Receives data from a connected socket.
- **Return**: Number of bytes received, 0 if the connection was closed, or -1 on error.

### `int plat_send(PlatSocket sock, const char* buf, int len)`
Sends data to a connected socket.
- **Return**: Number of bytes sent, or -1 on error.

### `void plat_close_socket(PlatSocket sock)`
Closes a socket.
- **Windows**: Calls `closesocket`.
- **POSIX**: Calls `close`.

### `int plat_socket_select(int nfds, plat_fd_set* readfds, plat_fd_set* writefds, plat_fd_set* exceptfds, int timeout_ms)`
Monitors multiple sockets for activity.
- **`nfds`**: On POSIX, the highest-numbered socket plus one. On Windows, ignored.
- **`readfds`**, **`writefds`**, **`exceptfds`**: Pointers to `plat_fd_set` structures.
- **`timeout_ms`**: Timeout in milliseconds. Use -1 for infinite wait.
- **Return**: Total number of ready socket handles, 0 on timeout, or -1 on error.

## FD Set Macros

The following macros are provided to manipulate `plat_fd_set` structures:

- `PLAT_FD_ZERO(plat_fd_set* s)`: Clears the set.
- `PLAT_FD_SET(PlatSocket fd, plat_fd_set* s)`: Adds a socket to the set.
- `PLAT_FD_ISSET(PlatSocket fd, plat_fd_set* s)`: Checks if a socket is in the set (activity detected).

## Usage Example (MUD Server Pattern)

```zig
extern fn plat_socket_init() i32;
extern fn plat_socket_cleanup() void;
// ... (other extern declarations)

pub fn main() !void {
    if (plat_socket_init() != 0) return error.SocketInit;
    defer plat_socket_cleanup();

    const server = plat_create_tcp_server(4000);
    if (server == PLAT_INVALID_SOCKET) return error.BindFailed;
    _ = plat_bind_listen(server, 5);

    var read_fds: plat_fd_set = undefined;
    while (true) {
        PLAT_FD_ZERO(&read_fds);
        PLAT_FD_SET(server, &read_fds);
        // ... add other client sockets to read_fds

        if (plat_socket_select(max_fd + 1, &read_fds, null, null, 100) > 0) {
            if (PLAT_FD_ISSET(server, &read_fds)) {
                const client = plat_accept(server);
                // ... handle new connection
            }
            // ... check other sockets
        }
    }
}
```
