# Networking — `std.net`

| | |
|---|---|
| **Modules** | `std.net` |
| **Layers** | `L3` — TCP/UDP sockets, byte-order helpers, and non-blocking primitives over a per-OS PAL (wsock32 on win32, libc elsewhere) |
| **Import (re-export)** | `const std = @import("std");` → `std.net` |
| **Import (by path)** | `const std_net = @import("std_net");` |

## Module overview

`std.net` is the target-selected networking surface: on win32 it binds Winsock
1.1 (`wsock32`), elsewhere it binds libc. The per-OS C prototypes come from a
private prelude header, and the externs live in this module. Call `init`
before any socket call and `cleanup` when finished; on POSIX both are trivial
(`init` returns `0`, `cleanup` does nothing), while win32 runs
`WSAStartup(1,1)`/`WSACleanup`.

The module has two error styles. The **TCP factory and transfer functions**
(`createTcpServer`, `createTcpClient`, `bindListen`, `accept`, `connect`,
`send`, `recv`) return a raw `i32` and signal failure with `-1` (or `0` from
`recv` at peer close) — no error set. The **UDP and non-blocking functions**
return `NetError!…` and map the per-OS socket error codes through one table. The
module's one error set (R2) is `NetError`; it deliberately **excludes**
`OutOfMemory`, because no path here allocates. Addresses are IPv4 only: the TCP
factories and `connect` target `127.0.0.1`, and `udpBind` binds `0.0.0.0`.

`std.net` also provides the classic readiness surface — `fd_set`, `fdZero`,
`fdSet`, `fdIsset`, and `select` — and the Model C non-blocking primitives
`setNonBlocking`, `recvNonBlocking`, and `sendNonBlocking`. There is no
executor or poll loop: the caller drives readiness and treats
`error.WouldBlock` as "yield and retry next tick". On a socket the caller has
set non-blocking, `recvNonBlocking` returns `0` at peer close and
`error.WouldBlock` when no data is ready; `sendNonBlocking` returns
`error.WouldBlock` when the send buffer is full.

Byte-order helpers round out the module: `htons`/`htonl` are the real OS
converters, and `htonsManual`/`htonlManual` are unconditional byte swaps for
debugging. `IpAddr` is the dotted-quad address value used by the UDP calls.

## Quick start

```zig
const std = @import("std");

const PORT: u16 = 9099;

pub fn main() !void {
    if (std.net.init() != 0) return;

    const server = std.net.createTcpServer(PORT);
    if (server < 0) return;
    if (std.net.bindListen(server, 1) < 0) {
        std.net.close(server);
        return;
    }

    const client = std.net.createTcpClient(PORT);
    if (client < 0) {
        std.net.close(server);
        return;
    }

    var conn: i32 = -1;
    while (conn < 0) {
        conn = std.net.accept(server);
    }

    const msg: []const u8 = "ping\n";
    _ = std.net.send(client, msg.ptr, @intCast(i32, msg.len));

    var buf: [16]u8 = undefined;
    const n = std.net.recv(conn, &buf[0], @intCast(i32, buf.len));
    if (n > 0) std.io.write(buf[0..@intCast(usize, n)]);

    std.net.close(conn);
    std.net.close(client);
    std.net.close(server);
    std.net.cleanup();
}
```

## API

### `fd_set`

**Purpose** — the opaque descriptor-set blob used by `select`, `fdZero`,
`fdSet`, and `fdIsset`.

**When to use** — declare one local per set you pass to `select`; do not
inspect its contents by hand.

**Signature** — `pub const fd_set = struct { data: [128]u32 };`

**Parameters** (fields)
- `data` — a 512-byte blob, large enough for the win32 (260-byte) and linux
  (128-byte) native `fd_set` layouts. The `[128]u32` type forces the 4-byte
  alignment WinSock's `select` requires.

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
var fds: std.net.fd_set = undefined;
std.net.fdZero(@ptrCast(*u8, &fds));
```

**Gotchas** — the blob is byte-layout-identical to the native `fd_set` at
offset 0, so the `*u8` parameters below accept a cast pointer to it. Never
assume its internal layout is portable; always go through the helpers.

### `Socket`

**Purpose** — the UDP descriptor type: an alias for the module's raw `i32`
descriptor convention.

**When to use** — as the value returned by `udpBind` and passed by pointer to
the other UDP functions.

**Signature** — `pub const Socket = i32;`

**Parameters** — none.

**Returns** — a type alias, not a value.

**Errors** — none.

**Example**
```zig
const s: std.net.Socket = try std.net.udpBind(0);
```

**Gotchas** — the TCP surface does not use this alias; it uses plain `i32`.
`Socket` is purely a readability alias — the values are interchangeable.

### `NetError`

**Purpose** — the module's single error set, shared by the UDP and non-blocking
functions.

**When to use** — when naming or matching a `std.net` failure on the UDP or
non-blocking paths.

**Signature** — `pub const NetError = error { WouldBlock, Timeout, ConnRefused, ConnReset, NotConnected, AddrInUse, InvalidAddr, Io };`

**Parameters** — none.

**Returns** — an error set, not a value.

**Errors**
- `error.WouldBlock` — the operation would block (`EAGAIN`/`EWOULDBLOCK` on
  POSIX, `WSAEWOULDBLOCK` on win32).
- `error.Timeout` — the operation timed out (`ETIMEDOUT`/`WSAETIMEDOUT`); on the
  receive path an `SO_RCVTIMEO` expiry is normalized from `WouldBlock` to
  `Timeout`.
- `error.ConnRefused` — the peer refused the connection.
- `error.ConnReset` — the peer reset the connection.
- `error.NotConnected` — the socket is not connected.
- `error.AddrInUse` — the address is already in use.
- `error.InvalidAddr` — an invalid argument or unsupported address family
  (`EINVAL`/`EAFNOSUPPORT`, `WSAEINVAL`/`WSAEAFNOSUPPORT`).
- `error.Io` — any other socket failure.

**Example**
```zig
const s = std.net.udpBind(4145) catch |e| {
    if (e == error.AddrInUse) return;
    return;
};
_ = s;
```

**Gotchas** — the error codes are the pinned i386-linux numbers on POSIX and the
Winsock 1.1 `WSAE*` numbers on win32; unrecognized codes collapse to `Io`. The
set has no `OutOfMemory` — no `std.net` path allocates.

### `IpAddr`

**Purpose** — a dotted-quad IPv4 address value.

**When to use** — as the destination of `udpSendTo` and the source out-param of
`udpRecvFrom`.

**Signature** — `const IpAddr = struct { a: u8, b: u8, c: u8, d: u8 };`

**Parameters** (fields)
- `a`/`b`/`c`/`d` — the four octets, `a` being the most significant (e.g.
  `127.0.0.1` is `{ .a = 127, .b = 0, .c = 0, .d = 1 }`).

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
const loopback = std.net.IpAddr{ .a = 127, .b = 0, .c = 0, .d = 1 };
```

**Gotchas** — declared without `pub`, but Z98 does not gate top-level
declarations on `pub`, so `std.net.IpAddr` is still nameable. Addresses are IPv4
only; there is no IPv6 form.

### `htons`

**Purpose** — converts a 16-bit host value to network byte order.

**When to use** — before placing a port into a socket address; for a portable
byte swap use `htonsManual`.

**Signature** — `pub extern "stdcall" fn htons(x: u16) u16`

**Parameters**
- `x` — the host-order value.

**Returns** — the network-order value.

**Errors** — none.

**Example**
```zig
const p = std.net.htons(4145);
```

**Gotchas** — this is the real OS converter (`wsock32` on win32, libc
elsewhere), not a hand-written swap. On a big-endian host it is the identity.

### `htonl`

**Purpose** — converts a 32-bit host value to network byte order.

**When to use** — before placing a 32-bit address into a socket address; for a
portable byte swap use `htonlManual`.

**Signature** — `pub extern "stdcall" fn htonl(x: u32) u32`

**Parameters**
- `x` — the host-order value.

**Returns** — the network-order value.

**Errors** — none.

**Example**
```zig
const a = std.net.htonl(0x7F000001);
```

**Gotchas** — the real OS converter, same as `htons`. On a big-endian host it
is the identity.

### `htonsManual`

**Purpose** — swaps the two bytes of a 16-bit value.

**When to use** — for debugging or for a self-contained byte swap when the OS
converter is not wanted.

**Signature** — `pub fn htonsManual(x: u16) u16`

**Parameters**
- `x` — the value to byte-swap.

**Returns** — the byte-swapped value.

**Errors** — none.

**Example**
```zig
const p = std.net.htonsManual(4145);
```

**Gotchas** — it is an **unconditional** byte swap, so it equals `htons` only on
little-endian hosts; on a big-endian host it differs. `udpRecvFrom` uses it to
read a network-order source port back into host order.

### `htonlManual`

**Purpose** — reverses the four bytes of a 32-bit value.

**When to use** — for debugging or for a self-contained byte swap.

**Signature** — `pub fn htonlManual(x: u32) u32`

**Parameters**
- `x` — the value to byte-reverse.

**Returns** — the byte-reversed value.

**Errors** — none.

**Example**
```zig
const a = std.net.htonlManual(0x7F000001);
```

**Gotchas** — unconditional byte reversal; equals `htonl` only on little-endian
hosts.

### `init`

**Purpose** — initializes the platform networking stack.

**When to use** — once at startup, before any socket call. On win32 this runs
`WSAStartup(1,1)`.

**Signature** — `pub fn init() i32`

**Parameters** — none.

**Returns** — `0` on success. win32 returns the `WSAStartup` result; POSIX
always returns `0`.

**Errors** — none; a nonzero return is the failure signal.

**Example**
```zig
if (std.net.init() != 0) return;
```

**Gotchas** — on POSIX it is a no-op. On win32, calling any socket function
before a successful `init` is undefined; check the return.

### `cleanup`

**Purpose** — releases the platform networking stack.

**When to use** — once at shutdown, after every socket is closed.

**Signature** — `pub fn cleanup() void`

**Parameters** — none.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.net.cleanup();
```

**Gotchas** — on win32 it runs `WSACleanup`; on POSIX it does nothing. Do not
call it while sockets are still in use.

### `createTcpServer`

**Purpose** — creates a TCP socket bound to `0.0.0.0:port`.

**When to use** — the first step of a listening server. It does **not** listen;
call `bindListen` next.

**Signature** — `pub fn createTcpServer(port: u16) i32`

**Parameters**
- `port` — the local port to bind, in host byte order (converted internally).

**Returns** — the bound socket descriptor, or `-1` if the socket or bind
failed. On POSIX the socket has `SO_REUSEADDR` set.

**Errors** — none; failure is `-1`.

**Example**
```zig
const server = std.net.createTcpServer(9099);
if (server < 0) return;
```

**Gotchas** — bind-only, so a connect attempt before `bindListen` is refused.
The win32 path does **not** set `SO_REUSEADDR`, so a recently closed port may
still be unavailable there. On a bind failure the socket is closed for you.

### `createTcpClient`

**Purpose** — creates a TCP socket connected to `127.0.0.1:port`.

**When to use** — the loopback client side of a test or a local protocol.

**Signature** — `pub fn createTcpClient(port: u16) i32`

**Parameters**
- `port` — the remote port on `127.0.0.1`, in host byte order.

**Returns** — the connected socket descriptor, or `-1` if the socket or connect
failed.

**Errors** — none; failure is `-1`.

**Example**
```zig
const client = std.net.createTcpClient(9099);
if (client < 0) return;
```

**Gotchas** — connects to loopback only; there is no host parameter. The
connect is blocking. On failure the socket is closed for you.

### `bindListen`

**Purpose** — puts a bound TCP socket into the listening state.

**When to use** — immediately after `createTcpServer`.

**Signature** — `pub fn bindListen(fd: i32, backlog: i32) i32`

**Parameters**
- `fd` — a socket from `createTcpServer`.
- `backlog` — the maximum pending-connection queue length.

**Returns** — `0` on success, `-1` on failure.

**Errors** — none; failure is `-1`.

**Example**
```zig
if (std.net.bindListen(server, 5) < 0) return;
```

**Gotchas** — despite the name it only calls `listen`; the bind already happened
in `createTcpServer`. It does not close the socket on failure.

### `accept`

**Purpose** — accepts a pending connection on a listening socket.

**When to use** — in a server loop after `bindListen`.

**Signature** — `pub fn accept(fd: i32) i32`

**Parameters**
- `fd` — the listening socket.

**Returns** — a new connected socket descriptor, or `-1` on failure (including
"no pending connection" while blocking).

**Errors** — none; failure is `-1`.

**Example**
```zig
var conn: i32 = -1;
while (conn < 0) {
    conn = std.net.accept(server);
}
```

**Gotchas** — blocking by default, and the peer address is discarded (there is
no out-param). A `-1` return is not always fatal; the accept loop above retries.

### `connect`

**Purpose** — connects an existing socket to `127.0.0.1:port`.

**When to use** — when you created the socket yourself and want to connect it
(versus `createTcpClient`, which does both).

**Signature** — `pub fn connect(fd: i32, port: u16) i32`

**Parameters**
- `fd` — an unconnected TCP socket.
- `port` — the remote port on `127.0.0.1`, in host byte order.

**Returns** — `0` on success, `-1` on failure.

**Errors** — none; failure is `-1`.

**Example**
```zig
if (std.net.connect(fd, 9099) != 0) return;
```

**Gotchas** — loopback only. Blocking; there is no timeout parameter.

### `send`

**Purpose** — sends bytes on a connected socket.

**When to use** — the blocking TCP send path. For a non-blocking socket use
`sendNonBlocking`.

**Signature** — `pub fn send(fd: i32, buf: [*]const u8, len: i32) i32`

**Parameters**
- `fd` — a connected socket.
- `buf` — a many-item pointer to the bytes.
- `len` — the number of bytes to send.

**Returns** — the number of bytes sent, or `-1` on error. The count may be less
than `len`.

**Errors** — none; failure is `-1`.

**Example**
```zig
const msg: []const u8 = "ping\n";
_ = std.net.send(fd, msg.ptr, @intCast(i32, msg.len));
```

**Gotchas** — a short send is legal; loop until all bytes are out if the message
must be complete. Blocking by default, so it can stall on a full buffer.

### `recv`

**Purpose** — receives bytes from a connected socket.

**When to use** — the blocking TCP receive path. For a non-blocking socket use
`recvNonBlocking`.

**Signature** — `pub fn recv(fd: i32, buf: [*]u8, len: i32) i32`

**Parameters**
- `fd` — a connected socket.
- `buf` — a many-item pointer to the destination.
- `len` — the destination capacity in bytes.

**Returns** — the number of bytes received; `0` at peer close; `-1` on error.

**Errors** — none; failure is `-1` and close is `0`.

**Example**
```zig
var buf: [64]u8 = undefined;
const n = std.net.recv(fd, &buf[0], @intCast(i32, buf.len));
if (n > 0) std.io.write(buf[0..@intCast(usize, n)]);
```

**Gotchas** — a single call may return fewer bytes than requested; loop for a
complete message. `0` is the EOF signal, not an error. Blocking by default.

### `close`

**Purpose** — closes a socket.

**When to use** — when finished with any socket from this module.

**Signature** — `pub fn close(fd: i32) void`

**Parameters**
- `fd` — the socket to close.

**Returns** — nothing.

**Errors** — none exposed; the OS close result is ignored.

**Example**
```zig
std.net.close(fd);
```

**Gotchas** — uses `closesocket` on win32 and `close` on POSIX. Using a closed
descriptor is a use-after-close.

### `udpBind`

**Purpose** — creates a UDP socket bound to `0.0.0.0:port`.

**When to use** — the first step for either side of a UDP exchange. Bind port
`0` to let the kernel choose an ephemeral port.

**Signature** — `pub fn udpBind(port: u16) NetError!Socket`

**Parameters**
- `port` — the local port in host byte order; `0` requests an ephemeral port.

**Returns** — the bound `Socket`.

**Errors** — the mapped socket/bind failure (`error.AddrInUse`,
`error.InvalidAddr`, `error.Io`, …). On a bind failure the socket is closed
first.

**Example**
```zig
const rx = try std.net.udpBind(4145);
const tx = try std.net.udpBind(0);
```

**Gotchas** — binds the wildcard address `0.0.0.0`, so it receives on all
interfaces. The returned socket is blocking; set an `SO_RCVTIMEO` with
`udpSetTimeout` to bound `udpRecvFrom`.

### `udpSendTo`

**Purpose** — sends one datagram to an address and port.

**When to use** — the send side of a UDP exchange.

**Signature** — `pub fn udpSendTo(s: *Socket, addr: IpAddr, port: u16, data: []const u8) NetError!void`

**Parameters**
- `s` — pointer to a UDP socket from `udpBind`.
- `addr` — the destination IPv4 address.
- `port` — the destination port in host byte order.
- `data` — the datagram payload; its length is the datagram length.

**Returns** — nothing on success.

**Errors** — the mapped `sendto` failure (`error.InvalidAddr`, `error.Io`, …).

**Example**
```zig
try std.net.udpSendTo(&tx, .{ .a = 127, .b = 0, .c = 0, .d = 1 }, 4145, "loop");
```

**Gotchas** — UDP is unreliable and message-oriented: a successful send means
only that the datagram was handed to the OS. A zero-length `data` sends an empty
datagram.

### `udpRecvFrom`

**Purpose** — receives one datagram and reports its source address and port.

**When to use** — the receive side of a UDP exchange.

**Signature** — `pub fn udpRecvFrom(s: *Socket, buf: []u8, out_addr: *IpAddr, out_port: *u16) NetError!usize`

**Parameters**
- `s` — pointer to a UDP socket from `udpBind`.
- `buf` — the destination; at most `buf.len` bytes are delivered.
- `out_addr` — receives the source IPv4 address.
- `out_port` — receives the source port in host byte order.

**Returns** — the number of bytes received. If the datagram was larger than
`buf`, this is `buf.len` and the excess is discarded.

**Errors** — `error.Timeout` when an `SO_RCVTIMEO` set by `udpSetTimeout`
expires; otherwise the mapped `recvfrom` failure.

**Example**
```zig
var buf: [16]u8 = undefined;
var addr: std.net.IpAddr = undefined;
var port: u16 = 0;
const n = try std.net.udpRecvFrom(&rx, buf[0..], &addr, &port);
```

**Gotchas** — **truncation is not detectable**: both targets report a
buffer-sized result whether or not the datagram was longer (win32's
`WSAEMSGSIZE` is normalized to `buf.len`, with the out-params still filled). A
datagram that does not fit is silently cut. The receive path normalizes
`WouldBlock` to `error.Timeout` so a timeout is uniform across targets.

### `udpSetTimeout`

**Purpose** — sets the receive timeout on a UDP socket.

**When to use** — to bound `udpRecvFrom` so it returns `error.Timeout` instead
of blocking forever.

**Signature** — `pub fn udpSetTimeout(s: *Socket, ms: u32) NetError!void`

**Parameters**
- `s` — pointer to a UDP socket.
- `ms` — the receive timeout in milliseconds.

**Returns** — nothing on success.

**Errors** — the mapped `setsockopt` failure.

**Example**
```zig
try std.net.udpSetTimeout(&rx, 250);
```

**Gotchas** — implemented as `SO_RCVTIMEO`: win32 takes a `DWORD` of
milliseconds, POSIX takes a `timeval`. It affects `udpRecvFrom` only (the
socket is never set non-blocking).

### `select`

**Purpose** — waits for readiness on one or more sockets.

**When to use** — to drive a readiness-gated loop without blocking on any one
socket; the Model C non-blocking pattern.

**Signature** — `pub fn select(nfds: i32, readfds: ?*u8, writefds: ?*u8, exceptfds: ?*u8, timeout_ms: i32) i32`

**Parameters**
- `nfds` — the highest descriptor in the sets plus one. On POSIX it must cover
  every descriptor in the sets; on win32 it is ignored.
- `readfds` — pointer to an `fd_set` blob cast to `?*u8` (usually the only set),
  or `null`.
- `writefds` — pointer to an `fd_set` blob cast to `?*u8`, or `null`.
- `exceptfds` — pointer to an `fd_set` blob cast to `?*u8`, or `null`.
- `timeout_ms` — `>= 0` waits at most that many milliseconds; a negative value
  blocks indefinitely.

**Returns** — the number of ready descriptors, `0` on timeout, or `-1` on
error.

**Errors** — none; failure is `-1`.

**Example**
```zig
var fds: std.net.fd_set = undefined;
std.net.fdZero(@ptrCast(*u8, &fds));
std.net.fdSet(fd, @ptrCast(*u8, &fds));
const rc = std.net.select(fd + 1, @ptrCast(*u8, &fds), null, null, 100);
if (rc > 0 and std.net.fdIsset(fd, @ptrCast(*u8, &fds))) {
    // fd is readable
}
```

**Gotchas** — `select` mutates the sets: re-`fdZero`/`fdSet` before each call.
Build sets with the helpers and cast the blob with `@ptrCast(*u8, &set)`; do not
pass a raw integer. `nfds` is ignored by win32 but is required on POSIX.

### `setNonBlocking`

**Purpose** — switches a connected socket to non-blocking mode.

**When to use** — before `recvNonBlocking`/`sendNonBlocking`, or before driving
a socket through `select`.

**Signature** — `pub fn setNonBlocking(s: *Socket) NetError!void`

**Parameters**
- `s` — pointer to the socket to change.

**Returns** — nothing on success.

**Errors** — the mapped `ioctlsocket`/`fcntl` failure.

**Example**
```zig
try std.net.setNonBlocking(&client);
```

**Gotchas** — win32 uses `ioctlsocket(FIONBIO)`; POSIX preserves the existing
`fcntl` status flags and adds `O_NONBLOCK`. The change is one-way here — there
is no `setBlocking`.

### `recvNonBlocking`

**Purpose** — receives bytes from a socket the caller has set non-blocking.

**When to use** — in a Model C loop that treats `error.WouldBlock` as "yield and
retry next tick".

**Signature** — `pub fn recvNonBlocking(s: *Socket, buf: []u8) NetError!usize`

**Parameters**
- `s` — pointer to a socket already set non-blocking.
- `buf` — the destination slice.

**Returns** — the number of bytes received; `0` at peer close; `error.WouldBlock`
when no data is ready.

**Errors** — `error.WouldBlock` (no data), `error.ConnReset`, and the other
mapped `recv` failures. Unlike `udpRecvFrom`, `WouldBlock` is preserved, not
normalized to `Timeout`.

**Example**
```zig
const n = std.net.recvNonBlocking(&client, buf[0..]) catch |e| {
    if (e == error.WouldBlock) return; // retry next tick
    return;
};
if (n == 0) return; // peer closed
```

**Gotchas** — the caller is responsible for having called `setNonBlocking`;
this wrapper does not set the mode. `0` is peer close, not would-block.

### `sendNonBlocking`

**Purpose** — sends bytes on a socket the caller has set non-blocking.

**When to use** — in a Model C loop alongside `recvNonBlocking`.

**Signature** — `pub fn sendNonBlocking(s: *Socket, buf: []const u8) NetError!usize`

**Parameters**
- `s` — pointer to a socket already set non-blocking.
- `buf` — the bytes to send.

**Returns** — the number of bytes accepted; may be less than `buf.len`.

**Errors** — `error.WouldBlock` when the send buffer is full, plus the other
mapped `send` failures.

**Example**
```zig
const n = std.net.sendNonBlocking(&client, msg) catch |e| {
    if (e == error.WouldBlock) return; // retry next tick
    return;
};
_ = n;
```

**Gotchas** — a short write is normal on a non-blocking socket; advance by the
returned count and retry the remainder. The caller must have set the mode.

### `fdZero`

**Purpose** — clears an `fd_set` to the empty set.

**When to use** — before building a set for `select`, and again before each
`select` call (which mutates the set).

**Signature** — `pub fn fdZero(s: *u8) void`

**Parameters**
- `s` — pointer to an `fd_set` blob cast to `*u8`.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.net.fdZero(@ptrCast(*u8, &fds));
```

**Gotchas** — on POSIX it zeroes 128 bytes (32 `u32` words); on win32 it clears
only the count word. Always use it rather than writing the blob directly.

### `fdSet`

**Purpose** — adds a descriptor to an `fd_set`.

**When to use** — after `fdZero`, to register each descriptor to watch.

**Signature** — `pub fn fdSet(fd: i32, s: *u8) void`

**Parameters**
- `fd` — the descriptor to add.
- `s` — pointer to an `fd_set` blob cast to `*u8`.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.net.fdSet(fd, @ptrCast(*u8, &fds));
```

**Gotchas** — win32 stores an explicit descriptor list (bounded by the native
64-socket limit); POSIX sets a bit. There is no `fdClr`.

### `fdIsset`

**Purpose** — tests whether a descriptor is in an `fd_set`.

**When to use** — after `select` returns a positive count, to find which
descriptors are ready.

**Signature** — `pub fn fdIsset(fd: i32, s: *u8) bool`

**Parameters**
- `fd` — the descriptor to test.
- `s` — pointer to the `fd_set` blob that `select` filled in.

**Returns** — `true` if the descriptor is set, `false` otherwise.

**Errors** — none.

**Example**
```zig
if (std.net.fdIsset(fd, @ptrCast(*u8, &fds))) {
    // fd is ready
}
```

**Gotchas** — only meaningful after a successful `select`; the set it inspects
is the one `select` mutated in place.

## See also

- `std.net` — the module in this doc.
- [`io.md`](io.md) — `std_file`/`std_stdin` input and output, and the
  descriptor conventions that pair with socket descriptors.
- [`os_time.md`](os_time.md) — `std.time.highRes`/`sleepMs` for pacing a
  non-blocking poll loop.
- [`async_stream.md`](async_stream.md) — the Model C scheduler and the stream
  readers (`SocketLineReader`, `MsgReader`) built on this module.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
