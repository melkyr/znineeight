# TCP/IP — `std_tcpip`

| | |
|---|---|
| **Modules** | `std_tcpip` |
| **Layers** | `L5` — userspace IPv4 + TCP client, UDP, DNS A-record, and ICMP echo |
| **Import (by path)** | `const std_tcpip = @import("std_tcpip.zig");` |
| **Consumes** | `std_arena` (`Arena` only; no sockets, clock, or environment) |

`std_tcpip` is not re-exported through `std`; import it by path.

## Module overview

`std_tcpip` is a **sans-I/O** userspace IPv4 stack. The caller owns the
transport (for example a WireGuard UDP tunnel, or a raw socket) and feeds
received IPv4 datagrams into `tcpipPoll`; the stack returns raw IPv4 datagrams
to send. It never opens a socket, reads a clock, reads the environment, or
allocates from the heap. The only allocation is the arena-backed state created
by `tcpipInit` (R1).

The API is client-only and IPv4-only:

- **TCP client.** Three-way handshake, sequence/acknowledgement, a fixed 8 KiB
  receive window, retransmission, slow start / AIMD (minimal Reno), and active
  close. There is no `listen`/`accept` server role.
- **UDP.** One pending transmit datagram and one received datagram per socket.
- **DNS.** A recursive-resolver-style A-record query to `cfg.dns_server` on
  UDP port 53. CNAME chains are **not** followed.
- **ICMP.** Echo request/reply client with RTT measurement.

`tcpipPoll` is a pump, not a blocking API: each call may consume one received
datagram, return one datagram to send, return one socket event, or tell the
caller how long it may wait. DNS and ICMP are pump-driven requests with the
call/`poll`/call completion protocol described below.

The module's one error set is `TcpipError` (R2): `Corrupt`, `NoRoute`,
`ConnRefused`, `Timeout`, `DnsFailed`, `OutOfMemory`, `OutputTooSmall`, and
`Closed`. A TCP reset or connection failure is reported as
`TcpipAction.failed`, not as a poll error. Determinism holds: no output depends
on addresses, wall time, or the process id (R6).

## Quick start

A driver loop that connects to one TCP peer and drains data. The driver owns
`pkt_buf` for `send_pkt`; it must be at least `cfg.mtu` bytes.

```zig
const std = @import("std");
const tcpip = @import("std_tcpip.zig");

var backing: [512 * 1024]u8 = undefined;
var pkt_buf: [1400]u8 = undefined;

pub fn main() !void {
    var arena = std.arena.init(backing[0..]);
    var cfg = tcpip.TcpipConfig{
        .ip = 0x0A070002,        // 10.7.0.2
        .netmask = 0xFFFFFF00,   // /24
        .gateway = 0x0A070001,   // 10.7.0.1
        .mtu = 1400,
        .dns_server = 0,
        .max_sockets = 4,
    };
    const s = try tcpip.tcpipInit(&arena, &cfg);
    const sock = try tcpip.tcpConnect(s, 0x0A070001, 4000);

    while (true) {
        const act = try tcpip.tcpipPoll(s, 0, null, pkt_buf[0..]);
        if (act == .send_pkt) {
            // transport.send(act.send_pkt); then feed the reply back as rx_ip
            continue;
        }
        if (act == .connected) {
            _ = try tcpip.tcpSend(s, sock, "look\r\n");
        } else if (act == .data) {
            var buf: [256]u8 = undefined;
            const n = try tcpip.tcpRecv(s, sock, buf[0..]);
            std.io.write(buf[0..n]);
        } else if (act == .closed or act == .failed) {
            break;
        }
    }
}
```

## TCP policy

| Policy | Value / rule |
|---|---|
| Inner MTU | `cfg.mtu`, **authoritative**, IPv4 headers included; default `1400` when zero |
| Maximum emitted datagram | Never larger than `cfg.mtu`; `OutputTooSmall` if the caller buffer or MTU cannot hold it |
| Local MSS | `cfg.mtu - 40` (20-byte IPv4 + 20-byte TCP); floored at 1 |
| Effective MSS | `min(peer-advertised MSS, local MSS)`; local MSS when the peer advertises none |
| SYN option | MSS option emitted on the initial SYN only |
| Receive window | 8 KiB minus outstanding unread bytes (`recvWindow`), advertised on every segment |
| Window scaling / SACK | None |
| Initial cwnd | One MSS |
| Initial `ssthresh` | 65535 |
| Congestion control | Slow start while `cwnd < ssthresh`, then additive increase (`mss*mss/cwnd` per ACK); RTO sets `ssthresh = cwnd/2` (floor `2*mss`) and restarts slow start |
| RTT / Karn | No RTT samples are taken; retransmitted segments can never bias an RTT estimate (simplified Karn) |
| RTO | Fixed 1 s (`TCP_RTO_MS = 1000`) |
| Retry caps | SYN: 8 retries; data/FIN: 12 retries, then `.failed` |
| Out-of-order data | Buffered in the 8 KiB receive ring only when inside the advertised window; duplicate bytes are ACKed but delivered once |
| Receive buffering | 8 KiB ring plus per-byte sequence/validity arrays; no growth beyond the fixed window |
| Fragments | Inbound IPv4 fragments (MF or non-zero offset) are dropped; the stack never emits fragments |
| FIN | Active close after queued data drains; a FIN outside the current receive window is ACKed but rejected, so a later valid FIN still closes |
| RST / failure | Socket-level failure surfaced as `TcpipAction.failed`; no `TcpipError` is raised by the poll for this |

`tcpSend` copies into a fixed 16 KiB per-socket send buffer and returns the
number of bytes accepted (possibly less than `data.len`). A second call before
the buffer drains may accept fewer bytes or zero; the caller must retry. The
stack never allocates a larger send buffer.

## DNS and ICMP completion semantics

Both helpers are **pump-driven step functions** because their compact
signatures carry no receive argument:

1. The first `dnsResolve`/`icmpPing` call starts the request and returns
   `error.Timeout`.
2. The driver calls `tcpipPoll` with the current monotonic `now_ms`. The poll
   emits the request, retransmits on a fixed 1 s cadence (3 attempts total), and
   parses the reply. It returns `.done` when the request reaches a terminal
   state, and also when the stack has no live sockets or pending requests
   (idle).
3. After `.done`, call the same helper again. `dnsResolve` returns the IPv4 A
   record; a terminal failure returns `error.DnsFailed`. `icmpPing` returns the
   RTT in milliseconds; a terminal failure returns `error.Timeout`.

DNS answers must match the query ID, source IP **and** UDP source port, and the
QNAME (case-insensitive, compression-pointer aware). A malformed response,
non-zero RCODE, absent question/answer, or CNAME-only answer is `DnsFailed`.
Only `A`/`IN` answers are accepted; the first matching 4-byte RDATA wins.
ICMP replies must come from the queried source IP and carry the fixed echo
identifier and sequence. Wrong-source or wrong-ID replies are ignored while the
request is pending.

## API

### TcpipConfig

**Purpose** — The stack's immutable configuration value, copied by
`tcpipInit`.

**When to use** — Set once per stack. `ip`, `netmask`, `gateway`, `mtu`,
`dns_server`, and `max_sockets` are all caller-supplied; there is no DHCP or
autoconfiguration.

**Signature** — `pub const TcpipConfig = struct { ip: u32, netmask: u32, gateway: u32, mtu: u16, dns_server: u32, max_sockets: u32 };`

**Parameters**
- `ip` — local IPv4 address in host byte order.
- `netmask` — prefix mask in host byte order (for example `0xFFFFFF00`).
- `gateway` — next-hop IPv4; `0` means "no off-subnet route".
- `mtu` — maximum inner IPv4 datagram size, headers included; `0` selects the
  `1400` default.
- `dns_server` — resolver IPv4; `0` disables DNS.
- `max_sockets` — number of TCP and UDP slots to allocate; `0` is treated as
  `1`.

**Returns** — A plain value.

**Errors** — none (the type has no methods).

**Example**
```zig
var cfg = tcpip.TcpipConfig{
    .ip = 0x0A070002, .netmask = 0xFFFFFF00, .gateway = 0x0A070001,
    .mtu = 1400, .dns_server = 0x0A070001, .max_sockets = 4,
};
```

**Gotchas** — `mtu` is the authoritative datagram ceiling; a value at or below
`40` cannot carry a TCP header plus MSS option (usable configurations should use
`mtu >= 44`). The struct is copied by `tcpipInit`; later mutation has no effect.

### TcpipError

**Purpose** — The module's single error set (R2).

**When to use** — Match/translate these at the call site; the stack does not
hide them.

**Signature** — `pub const TcpipError = error{ Corrupt, NoRoute, ConnRefused, Timeout, DnsFailed, OutOfMemory, OutputTooSmall, Closed };`

**Parameters** — none.

**Returns** — n/a.

**Errors**
- `Corrupt` — malformed IPv4/TCP/UDP/ICMP input (length, header, or checksum).
- `NoRoute` — destination is zero, off-subnet, and no gateway is configured.
- `ConnRefused` — reserved for the TCP error mapping; a reset in the current
  implementation is delivered as `TcpipAction.failed`.
- `Timeout` — DNS/ICMP request pending (the normal first-call result), or a
  terminal ICMP failure on the final call.
- `DnsFailed` — terminal DNS failure (malformed/mismatched answer, RCODE,
  CNAME-only, or retry exhaustion).
- `OutOfMemory` — arena exhaustion in `tcpipInit`, or no free TCP/UDP slot.
- `OutputTooSmall` — a datagram would exceed `cfg.mtu`, the caller's `out`
  buffer is too small, or a UDP send slot is still full.
- `Closed` — the socket id is not live or the socket is not in the required
  state.

**Example**
```zig
_ = tcpip.tcpConnect(s, dst, port) catch |e| {
    if (e == error.NoRoute) return;
    return e;
};
```

**Gotchas** — `ConnRefused` is part of the published contract; current resets
still surface through the action union.

### TcpipAction

**Purpose** — The result of one `tcpipPoll` step.

**When to use** — Drive the driver loop by switching on the active tag.

**Signature** — `pub const TcpipAction = union(enum) { send_pkt: []const u8, wait: u32, connected: u32, data: u32, closed: u32, failed: u32, done: void };`

**Parameters**
- `send_pkt` — raw IPv4 datagram in the caller's `out` buffer; valid until the
  next call.
- `wait` — sleep at most this many milliseconds (`1` means poll again
  immediately).
- `connected` — socket id whose handshake completed.
- `data` — socket id with buffered receive data (`tcpRecv`).
- `closed` — socket id whose FIN exchange completed.
- `failed` — socket id that was reset or exhausted retries.
- `done` — a DNS/ICMP request reached a terminal state (call the helper
  again), or the stack is idle: no live socket and no pending request.

**Returns** — A tagged action value.

**Errors** — none (it is a union).

**Example**
```zig
const act = try tcpip.tcpipPoll(s, now_ms, rx, out);
if (act == .send_pkt) send_to_peer(act.send_pkt);
```

**Gotchas** — `send_pkt` aliases the caller's `out`; copy it before the next
call if the driver needs to keep it. `done` does not identify which request
completed (and is also the idle result), so do not overlap a DNS and ICMP
request in one driver.

### TCP_MSS / TCP_RECV_WINDOW / TCP_RTO_MS

**Purpose** — Published policy constants: historical default MSS name
(`1400`), fixed receive window (`8192`), fixed retransmission timeout
(`1000` ms).

**When to use** — Sizing driver buffers or documenting expectations. The live
MSS is derived from `cfg.mtu` and the peer's option, not from `TCP_MSS`.

**Signature** — `pub const TCP_MSS: usize = 1400;` /
`pub const TCP_RECV_WINDOW: usize = 8192;` /
`pub const TCP_RTO_MS: u64 = 1000;`

**Parameters** — none.

**Returns** — Compile-time values.

**Errors** — none.

**Example**
```zig
var out: [tcpip.TCP_MSS]u8 = undefined;
```

**Gotchas** — `TCP_MSS` is a compatibility name; use `cfg.mtu - 40` for the
actual local limit.

### UDP_MAX_PAYLOAD

**Purpose** — Maximum UDP payload the stack accepts (`1472` bytes, the classic
1500-byte Ethernet MTU minus IPv4/UDP headers).

**When to use** — Sizing a UDP send. This is an absolute cap in addition to the
`cfg.mtu` check.

**Signature** — `pub const UDP_MAX_PAYLOAD: usize = 1472;`

**Parameters** — none.

**Returns** — Compile-time value.

**Errors** — none.

**Example**
```zig
var payload: [tcpip.UDP_MAX_PAYLOAD]u8 = undefined;
```

**Gotchas** — A datagram must also satisfy `20 + 8 + payload.len <= cfg.mtu`.

### TcpSock / UdpSock / TcpipStack

**Purpose** — The concrete state records. `TcpipStack` is allocated by
`tcpipInit`; `TcpSock`/`UdpSock` are its arena-backed arrays. They are public so
drivers and white-box tests can inspect state, but normal callers should use the
functions below.

**When to use** — Diagnostics, tests, or a driver that wants to place the
records in its own arena. Do not mutate live socket fields unless you are
deliberately white-box testing.

**Signature** — `pub const TcpSock = struct { ... };` /
`pub const UdpSock = struct { ... };` /
`pub const TcpipStack = struct { ... };`

**Parameters** — see `sf/src/std_tcpip.zig` for the full field list.

**Returns** — n/a.

**Errors** — none.

**Example**
```zig
const s = try tcpip.tcpipInit(&arena, &cfg);
const used = s.sockets[0].in_use;
```

**Gotchas** — Sizes are target-dependent. On the 32-bit seed compiler the
measured sizes are `TcpipStack` 648 B, `TcpSock` 65648 B, `UdpSock` 2988 B
(see [Memory bounds](#memory-bounds)).

### tcpipInit

**Purpose** — Allocates and zero-initialises the stack and its fixed socket
arrays from the caller's arena.

**When to use** — Once per stack, before any other call.

**Signature** — `pub fn tcpipInit(arena: *arena_mod.Arena, cfg: *TcpipConfig) !*TcpipStack`

**Parameters**
- `arena` — caller-owned arena; the only memory source.
- `cfg` — configuration copied into the stack. `max_sockets == 0` becomes `1`.

**Returns** — A pointer to the initialised `TcpipStack`.

**Errors** — `error.OutOfMemory` when the stack or either socket array cannot
be allocated.

**Example**
```zig
var arena = std.arena.init(backing[0..]);
const s = try tcpip.tcpipInit(&arena, &cfg);
```

**Gotchas** — Allocation order is stack, TCP array, then UDP array; a failure
after a successful earlier allocation leaves that memory in the arena (there is
no partial rollback). Everything is reclaimed only by `std.arena.reset`.

### ipv4Checksum

**Purpose** — One's-complement checksum over a header whose checksum field is
zero. Also used for the ICMP header.

**When to use** — Building test packets or validating an IPv4/ICMP header.

**Signature** — `pub fn ipv4Checksum(header: []const u8) u16`

**Parameters**
- `header` — bytes to sum; for IPv4 pass exactly the 20-byte header with the
  checksum field zeroed.

**Returns** — The checksum in host byte order; an odd trailing byte is shifted
into the high byte (`data[i] << 8`), with a zero low pad byte.

**Errors** — none.

**Example**
```zig
const ck = tcpip.ipv4Checksum(pkt[0..20]);
```

**Gotchas** — This is the raw header checksum; TCP/UDP checksums include the
IPv4 pseudo-header and are built internally by the stack.

### tcpConnect

**Purpose** — Allocates a TCP socket slot, chooses the deterministic local port
(`49152 + slot`), and queues the initial SYN.

**When to use** — Starting a client connection. The SYN is emitted by
`tcpipPoll`, not by this call.

**Signature** — `pub fn tcpConnect(s: *TcpipStack, dst_ip: u32, dst_port: u16) !u32`

**Parameters**
- `s` — live stack.
- `dst_ip` — peer IPv4 in host byte order.
- `dst_port` — peer TCP port.

**Returns** — A nonzero socket id used by `tcpSend`/`tcpRecv`/`tcpClose`.

**Errors** — `error.NoRoute` when `routeOk` fails; `error.OutOfMemory` when no
slot is free.

**Example**
```zig
const sock = try tcpip.tcpConnect(s, 0x0A070001, 4000);
```

**Gotchas** — The initial ISS is deterministic (`0x12340000 + id*0x101`).
The socket remains `syn_sent` until a SYN-ACK is processed; closing it in that
state marks it failed.

### tcpSend

**Purpose** — Copies application bytes into the socket's fixed 16 KiB send
buffer.

**When to use** — Send request bytes after `connected`. Poll to actually emit
segments.

**Signature** — `pub fn tcpSend(s: *TcpipStack, sock: u32, data: []const u8) !usize`

**Parameters**
- `s` — live stack.
- `sock` — TCP socket id.
- `data` — bytes to enqueue; empty input returns `0` without error.

**Returns** — Number of bytes accepted (may be less than `data.len`; retry the
remainder).

**Errors** — `error.Closed` if the id is unknown, the state is not
`established`, or a close is already pending.

**Example**
```zig
const n = try tcpip.tcpSend(s, sock, "look\r\n");
```

**Gotchas** — The buffer is 16 KiB and compacts consumed prefixes; a full
buffer accepts zero bytes, not an error. The call does not transmit; polling
does.

### tcpRecv

**Purpose** — Drains in-order received bytes from the 8 KiB receive ring.

**When to use** — After a `.data` action, or whenever the driver wants to check
for buffered data.

**Signature** — `pub fn tcpRecv(s: *TcpipStack, sock: u32, out: []u8) !usize`

**Parameters**
- `s` — live stack.
- `sock` — TCP socket id.
- `out` — destination slice; at most its length is written.

**Returns** — Number of bytes copied; `0` when nothing is buffered or `out` is
empty. Data is removed from the ring as it is copied.

**Errors** — `error.Closed` if the id is unknown.

**Example**
```zig
const n = try tcpip.tcpRecv(s, sock, buf[0..]);
```

**Gotchas** — A pending FIN is reported as `.closed` only after buffered data
is drained, so call `tcpRecv` on `.data` before treating `.closed` as terminal.
The receive ring is fixed at 8 KiB; the sender's window prevents overflow.

### tcpClose

**Purpose** — Requests an active close.

**When to use** — After the application is done sending. The FIN is emitted
after queued data drains.

**Signature** — `pub fn tcpClose(s: *TcpipStack, sock: u32) !void`

**Parameters**
- `s` — live stack.
- `sock` — TCP socket id.

**Returns** — nothing.

**Errors** — `error.Closed` if the id is unknown. In `syn_sent` the socket is
marked failed immediately; in other non-established states the close is a
no-op.

**Example**
```zig
try tcpip.tcpClose(s, sock);
```

**Gotchas** — This is not a blocking close: setting the flag succeeds even if
the FIN later hits `OutputTooSmall`. The socket remains retryable and keeps the
same FIN sequence.

### tcpipPoll

**Purpose** — Advances the stack by one step: consume one received datagram,
emit one datagram, deliver one socket event, or report a wait or idle state.

**When to use** — Every driver loop iteration, with the current monotonic
milliseconds.

**Signature** — `pub fn tcpipPoll(s: *TcpipStack, now_ms: u64, rx_ip: ?[]const u8, out: []u8) !TcpipAction`

**Parameters**
- `s` — live stack.
- `now_ms` — caller's monotonic clock in milliseconds (never wall time).
- `rx_ip` — optional raw IPv4 datagram just received; consumed before any send.
- `out` — destination for `send_pkt`; must be at least `cfg.mtu` bytes for full
  segments.

**Returns** — One `TcpipAction`. The order is: process `rx_ip`; serve TCP sends
(slot order); serve UDP, DNS, then ICMP sends; serve socket events; return
`.done` for a terminal DNS/ICMP state or when the stack is idle; otherwise a
`wait` (at most 1000 ms).

**Errors** — `error.Corrupt` for a malformed received datagram;
`error.OutputTooSmall` if a datagram cannot fit `out`/`cfg.mtu`. The poll does
not allocate, so it cannot return `error.OutOfMemory`.

**Example**
```zig
const act = try tcpip.tcpipPoll(s, now_ms, rx_opt, pkt_buf[0..]);
```

**Gotchas** — One action per call. A `.send_pkt` result does not mean the same
socket has no further event; poll again. `now_ms` must be monotonic; deriving it
from the wall clock breaks RTO/determinism.

### udpOpen

**Purpose** — Allocates a UDP socket slot with a local port.

**When to use** — Before `udpSendTo`/`udpRecvFrom`.

**Signature** — `pub fn udpOpen(s: *TcpipStack, local_port: u16) !u32`

**Parameters**
- `s` — live stack.
- `local_port` — explicit local port, or `0` for the deterministic
  `49152 + slot`.

**Returns** — A nonzero socket id.

**Errors** — `error.OutOfMemory` when no slot is free.

**Example**
```zig
const u = try tcpip.udpOpen(s, 0);
```

**Gotchas** — UDP slots are separate from TCP slots but share the
`max_sockets` count.

### udpSendTo

**Purpose** — Queues one UDP datagram for emission by `tcpipPoll`.

**When to use** — Sending a datagram; there is exactly one pending TX slot per
socket.

**Signature** — `pub fn udpSendTo(s: *TcpipStack, sock: u32, ip: u32, port: u16, data: []const u8) !void`

**Parameters**
- `s` — live stack.
- `sock` — UDP socket id.
- `ip`, `port` — destination IPv4/port.
- `data` — payload; must satisfy the `UDP_MAX_PAYLOAD` and `cfg.mtu` checks.

**Returns** — nothing (the packet is emitted by the next poll).

**Errors** — `error.Closed` for an unknown id; `error.NoRoute` for an
unroutable destination; `error.OutputTooSmall` for an oversize payload or when
the previous TX slot has not been drained.

**Example**
```zig
try tcpip.udpSendTo(s, u, dst, 1234, payload[0..]);
```

**Gotchas** — This is a one-slot, best-effort API: a second send before the
poll returns `OutputTooSmall` rather than queueing. UDP is allowed to lose
packets.

### udpRecvFrom

**Purpose** — Drains the single received datagram slot for a UDP socket.

**When to use** — After polling, when the driver expects a datagram.

**Signature** — `pub fn udpRecvFrom(s: *TcpipStack, sock: u32, out: []u8, ip: *u32, port: *u16) !usize`

**Parameters**
- `s` — live stack.
- `sock` — UDP socket id.
- `out` — destination; the datagram is truncated to its length.
- `ip`, `port` — out-parameters for the sender; set to `0` when no datagram is
  pending.

**Returns** — Bytes copied; `0` when the slot is empty.

**Errors** — `error.Closed` for an unknown id.

**Example**
```zig
var from_ip: u32 = 0;
var from_port: u16 = 0;
const n = try tcpip.udpRecvFrom(s, u, buf[0..], &from_ip, &from_port);
```

**Gotchas** — Latest datagram wins: an unconsumed slot is overwritten by the
next arrival. Inbound UDP checksum `0` is accepted per IPv4 UDP semantics; a
bad non-zero checksum drops the packet.

### dnsResolve

**Purpose** — Starts or completes a pump-driven A-record query.

**When to use** — Resolving a name to IPv4 through `cfg.dns_server`.

**Signature** — `pub fn dnsResolve(s: *TcpipStack, name: []const u8, out_ip: *u32) !void`

**Parameters**
- `s` — live stack.
- `name` — dotted name; labels ≤ 63 bytes, total wire name ≤ 255 bytes.
- `out_ip` — receives the A record on the final call.

**Returns** — nothing on success (final call); `error.Timeout` while pending
and on the starting call.

**Errors** — `error.NoRoute` if the DNS server is unroutable;
`error.DnsFailed` for a malformed name or terminal resolver failure;
`error.Timeout` while pending.

**Example**
```zig
var ip: u32 = 0;
_ = tcpip.dnsResolve(s, "mud.example", &ip) catch |e| {
    if (e != error.Timeout) return e;
};
// poll until .done, then:
try tcpip.dnsResolve(s, "mud.example", &ip);
```

**Gotchas** — CNAME chains are unsupported and end as `DnsFailed`. The query
ID and local port are deterministic; retries reuse the identical payload/ID.

### icmpPing

**Purpose** — Starts or completes a pump-driven ICMP echo request.

**When to use** — Reachability/RTT checks through the same inner stack.

**Signature** — `pub fn icmpPing(s: *TcpipStack, ip: u32, now_ms: u64) !u32`

**Parameters**
- `s` — live stack.
- `ip` — echo destination.
- `now_ms` — monotonic time used to timestamp each send; the returned RTT is
  measured from the last retry send.

**Returns** — RTT in milliseconds on the final call; `error.Timeout` while
pending or on terminal failure.

**Errors** — `error.NoRoute` for an unroutable destination; `error.Timeout`
while pending and for an exhausted/failed probe.

**Example**
```zig
var rtt: u32 = 0;
_ = tcpip.icmpPing(s, dst, now_ms) catch |e| {
    if (e != error.Timeout) return e;
};
// poll until .done, then:
rtt = try tcpip.icmpPing(s, dst, now_ms);
```

**Gotchas** — The starting call returns `error.Timeout`; this is not a
failure. Only the final call after `.done` distinguishes success (RTT) from
terminal failure (`error.Timeout`). Replies from another source, ID, or
sequence are ignored.

## Memory bounds

All state is arena-backed and fixed at `tcpipInit` time; there is no per-packet
or per-connection heap allocation. Measured on the 32-bit seed compiler:

| Record | Bytes |
|---|---:|
| `TcpipStack` (fixed state, including the 512-byte DNS query buffer) | 648 |
| `TcpSock` (16 KiB send + 8 KiB receive ring + 32 KiB sequence + 8 KiB validity + fields) | 65648 |
| `UdpSock` (one 1472-byte RX + one 1472-byte TX buffer + fields) | 2988 |

`tcpipInit` therefore reserves:

```
648 + N * (65648 + 2988) = 648 + N * 68636 bytes,  N = max(max_sockets, 1)
```

Examples: `N = 1` → 69284 bytes; `N = 4` → 275192 bytes (the demo's measured
`arena_peak`); `N = 8` → 549736 bytes. The stack stores no dynamic lists: a
connection is a slot in the fixed arrays, and `max_sockets` is the hard ceiling
on simultaneous TCP and UDP sockets. `dnsResolve`/`icmpPing` use internal
`TcpipStack` state and do not consume public socket slots.

## See also

- [`std_wireguard`](wireguard.md) — the demo's transport; it encrypts the
  datagrams this stack emits.
- [`std_net`](net.md) — OS socket layer used by the WireGuard demo for its UDP
  underlay.
- [`wireguard_demo`](../../../examples/z98/demo/wireguard_demo/README.md) —
  end-to-end userspace TCP/IP through a real WireGuard tunnel.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
