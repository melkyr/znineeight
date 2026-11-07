# Phase 3.3 — HTTP/2 Client Design

**Date:** 2026-11-07
**Branch:** `zig1_improvements`
**Baseline:** HEAD `f400e135`, seed v143, lib 56
**Status:** design for implementation

## 1. Intent

Add a real HTTP/2 client to the Z98 std library: connection reuse, multiplexed
streams, HPACK, flow control, TLS+ALPN and h2c prior knowledge. It is a std
capability, not a z9git change. z9git stays HTTP/1.1.

The design is deliberately split into two phases inside one plan:

- **3.3a** — transport prerequisite: TLS ALPN, nonblocking/async socket helpers,
  and the TLS socket driver.
- **3.3b** — HTTP/2: HPACK, frame codec, connection/streams/flow control, public
  API, and integration tests.

## 2. Goals

- TLS 1.2 and TLS 1.3 ALPN negotiation, offering `h2` with `http/1.1` fallback.
- h2c prior knowledge (cleartext, no Upgrade).
- One connection reused by many concurrent streams.
- Full HPACK decoding (static table, dynamic table, Huffman, integers/strings);
  literal-only encoding is sufficient.
- Connection and stream flow control, SETTINGS/ACK, PING/ACK, WINDOW_UPDATE,
  GOAWAY, RST_STREAM, HEADERS/CONTINUATION/DATA.
- Buffered convenience responses and streaming `ResponseSink`/`RequestSource`.
- A coroutine-friendly request API driven by a caller-owned event loop.

## 3. Non-goals

- No z9git HTTP/2 integration in 3.3; z9git remains HTTP/1.1.
- No server push processing and no priority scheduling.
- No HTTP/2 Upgrade (`h2c` Upgrade); prior knowledge only.
- No automatic HTTP/1.1-to-HTTP/2 fallback inside one call. The caller inspects
  ALPN and chooses `std_http2` or `std_http`.
- No threads, no background reader thread, no OS event-loop dependency.
- No new compiler features or builtins.
- No performance/cycle-target claims.
- No committed HTTP/2 test server.

## 4. Constraints

- Pure Z98: no `@cImport`, `asm`, intrinsics, or C macros; externs are allowed.
- No generics, methods, `anytype`, `@alignCast`, or type parameters.
- `std_tls` stays sans-I/O: it owns records/handshake and takes bytes; it does
  not own sockets or wall-clock reads. The socket driver is a companion module.
- Single-threaded cooperative model: `WouldBlock` is a yield, not a block.
- 32-bit offsets and bounds checks; use `u64` intermediates where size math can
  exceed `0xFFFFFFFF`.
- Bounded memory: no unbounded arena growth per stream or per connection.
- HTTP/2 requires TLS 1.2+ with an allowed cipher suite; the existing TLS
  suites are acceptable.
- The HTTP/2 test server is generated at test time in `/tmp`; no server source
  is committed. Existing localhost certificates are used.
- `TlsConfig.prefer_chacha20: bool` (default `false`) controls suite/group
  order: when `true`, the ClientHello offers ChaCha20-Poly1305 before
  AES-128-GCM and x25519 before secp256r1. The HTTP/2 path sets `true`;
  `false` keeps every existing wire fixture byte-identical.
- The caller event loop selects for **read and write** readiness with a bounded
  timeout and a stall watchdog; `http2Pump` may hold pending output.
- `TlsIoError` is the full `TlsError` ∪ `NetError` name union (31 names);
  collapsing happens only at the `Http2Error` boundary.
- Server-dependent fixtures pin a deterministic argless usage golden
  (`expected.txt` usage line, nonzero `expected.rc`).

## 5. Current state and feasibility

- `sf/src/std_tls.zig` implements TLS 1.2/1.3 records and a client handshake. It
  has **no ALPN**. `TlsConfig` has 6 literal call sites (z9git, tls_demo, four
  TLS fixtures). TLS 1.3 EncryptedExtensions only validates its length; TLS 1.2
  ServerHello only handles `supported_versions` and `key_share`.
- `sf/src/std_net.zig` already has `setNonBlocking`, `recvNonBlocking`,
  `sendNonBlocking`, `select`, and `error.WouldBlock`.
- `sf/src/std_async.zig` provides cooperative tasks and `@asyncSuspend`.
  `examples/z98/z9torr` already uses this model for nonblocking peer I/O.
- `sf/src/std_http.zig` is HTTP/1.1, per-request, and closes its transport. It
  already defines `Header`, `Response`, `ResponseSink`, and `RequestSource`.
- No HPACK, HTTP/2 frame codec, or ALPN code exists.
- The compiler has no HTTP/2 dependencies; new modules are path-imported and do
  not change the compiler fixed point.
- `std_net` is barrel-exported from `sf/src/std.zig`; adding declarations moves
  the 8 dump-MD5 pins and the marker anchor. Fold-era verified-delta accounting
  applies. The re-baseline lands **immediately at the Task 2 commit**; the later
  path modules (`std_tls_io`, `std_hpack`, `std_http2`) move no pins.

## 6. Approaches considered

1. **Single-stream h2 per connection** — smallest risk, fits the existing
   per-request `HttpTransport`, but does not deliver the requested multiplexing.
   Rejected.
2. **Full h2 reuse + multiplexing with an internal reader task** — simple call
   sites, but `std.async` has no readiness set; a `WouldBlock` reader is resumed
   every tick and spins, and a blocking select defeats cooperation. Rejected.
3. **Full h2 reuse + multiplexing, caller event loop + nonblocking pump**
   — chosen. The caller owns `select`/readiness; `http2Pump` never blocks;
   request coroutines suspend until their stream completes.
4. **Transport in `std_tls`** — would turn a sans-I/O module into a socket
   owner and break its contract. Rejected in favor of a `std_tls_io` companion.
5. **h2c Upgrade** — extra handshake surface with no value for this client.
   Rejected; prior knowledge only.
6. **HPACK full encode including dynamic table** — unnecessary for a client;
   full decode plus literal encode is interoperable. Dynamic encode deferred.

## 7. Architecture

### 7.1 3.3a — transport

**ALPN (`std_tls.zig`)**

- `pub const AlpnProtocol = enum(u8) { none = 0, h2 = 1, http11 = 2, other = 3 };`
- `TlsConfig` gains `alpn_h2: bool`.
- `TlsSession` gains `alpn: AlpnProtocol`.
- `pub fn tlsAlpnSelected(sess: *const TlsSession) AlpnProtocol`.
- `sendClientHello` appends extension 16 only when `alpn_h2`; the list is
  `h2`, then `http/1.1`.
- TLS 1.2: parse ALPN in ServerHello extensions.
- TLS 1.3: parse ALPN in EncryptedExtensions; the existing length check stays.
- If the server selects a protocol not offered, fail the handshake.
- `alpn_h2 = false` emits no extension; existing wire fixtures stay identical.

**Suite/group preference (`std_tls.zig`)**

- `TlsConfig.prefer_chacha20: bool` reorders the ClientHello: when set, TLS 1.3
  `0x1303` (ChaCha20-Poly1305) precedes `0x1301`, the TLS 1.2 ChaCha20 pair
  precedes the AES-GCM pair, and `supported_groups` lists x25519 before
  secp256r1. Pure-C ChaCha20-Poly1305 is 2–4× faster than AES-GCM on era
  hardware (GHASH ≈ 50–80% of HTTPS CPU); the server still picks the suite and
  AES-GCM stays offered as fallback. Default `false` preserves the current
  order byte-for-byte.

**Nonblocking/async socket helpers (`std_net.zig`)**

- `pub fn sendAllAsync(s: *Socket, data: []const u8) NetError!void`
- `pub fn recvSomeAsync(s: *Socket, buf: []u8) NetError!usize`
- Both suspend with `@asyncSuspend(null)` on `WouldBlock`; `recvSomeAsync`
  returns 0 only at EOF.

**TLS socket driver (`std_tls_io.zig`, new)**

`std_tls` remains sans-I/O. `std_tls_io` owns the socket, pending output, and
nonblocking pump:

```zig
pub const TlsIo = struct {
    sess: *tls.TlsSession,
    sock: net.Socket,
    out: [tls.TLS_MAX_WIRE_RECORD + 64]u8,
    out_len: usize,
    out_off: usize,
    in: [tls.TLS_MAX_WIRE_RECORD]u8,
    established: bool,
    closed: bool,
};

pub const TlsIoError = error{
    // full TlsError names (std_tls.zig)
    BadAction, AppTooLarge, OutputTooSmall, BadConfig, HandshakeFailed,
    UnsupportedVersion, UnsupportedSuite, UnsupportedGroup,
    CertificateExpired, CertificateNotYetValid, UnknownIssuer,
    HostnameMismatch, BadSignature, ChainTooLong, UnsupportedAlgorithm,
    Corrupt, AuthenticationFailed, RecordTooLarge, Closed, WeakPublicKey,
    InvalidPrivateKey, InvalidPublicKey,
    // full NetError names (std_net.zig)
    WouldBlock, Timeout, ConnRefused, ConnReset, NotConnected, AddrInUse,
    InvalidAddr, ResolveFailed, Io,
};

pub fn tlsIoInit(io: *TlsIo, sess: *tls.TlsSession, sock: net.Socket) void;
pub fn tlsIoHandshakePump(io: *TlsIo) TlsIoError!bool; // true = established
pub fn tlsIoReadPump(io: *TlsIo, out: []u8) TlsIoError!usize; // 0 = closed
pub fn tlsIoWritePump(io: *TlsIo, data: []const u8) TlsIoError!usize;
pub fn tlsIoClose(io: *TlsIo) void;
```

`tlsIo*Pump` are non-suspending. They flush pending wire bytes, use
`sendNonBlocking`/`recvNonBlocking`, and return `WouldBlock` when the socket is
not ready. They never block the scheduler.

`TlsIoError` is the **full `TlsError` ∪ `NetError` name union**: bare `try`
stays valid (name-subset rule), and when either upstream set grows the compiler
flags the one-line addition instead of silently misclassifying a new name in a
catch-map `else`. Cert-class detail is preserved here; collapsing happens only
into `Http2Error` at the HTTP/2 boundary.

### 7.2 3.3b — HTTP/2

**Files and ownership**

- `sf/src/std_hpack.zig` — HPACK tables, HPACK Huffman, integer/string codec.
- `sf/src/std_http2.zig` — frames, settings, connection, streams, flow control,
  public API.
- `sf/src/std_tls_io.zig` — TLS socket driver.
- `std_http2` reuses `http.Header`, `http.Response`, `http.ResponseSink`, and
  `http.RequestSource`.

**Concrete transport seam**

`std_http2` defines a non-suspending transport table:

```zig
pub const Transport = struct {
    state: *void,
    read_fn: fn (*void, []u8) TransportError!usize,
    write_fn: fn (*void, []const u8) TransportError!usize,
    close_fn: fn (*void) void,
};
pub const TransportError = error{ WouldBlock, Closed, Io };
```

The TLS adapter's close-pending state is tracked internally on `Http2Conn`
(`tls_io`), not in the public `Transport` table, so external `Transport`
literals keep the four-field shape.

The table is non-suspending, so function-pointer dispatch is safe (no async
propagation through a pointer). A suspending function address is rejected
(`error[3017]`), so this is the only possible fn-pointer shape; `fn` fields
with `E!T` returns are proven (`std_http.HttpTransport` precedent) while
`?fn … E!T` call-through-unwrap is unproven and must not be used.
`http2OpenTransport` is the test seam;
`http2OpenTls` adapts `TlsIo`; `http2OpenTcp` adapts a nonblocking socket.

**Public API**

```zig
pub const Http2Config = struct {
    max_streams: u32,        // default 16
    max_header_list: usize,  // default 65536
    initial_window: u32,     // default 65535
    max_frame_size: u32,     // default 16384
    header_table_size: u32,  // default 4096
};

pub const PumpStatus = enum(u8) { progress = 0, would_block = 1, closed = 2 };

pub const Http2Error = error{
    NotHttp2, BadConfig, TooLarge, Protocol, Corrupt, Closed, Io,
    OutOfMemory, StreamClosed, StreamReset, GoAway, NoStream, Busy,
};

pub fn http2OpenTls(arena: *std.arena.Arena, io: *tls_io.TlsIo, cfg: Http2Config) Http2Error!*Http2Conn;
pub fn http2OpenTcp(arena: *std.arena.Arena, sock: net.Socket, cfg: Http2Config) Http2Error!*Http2Conn;
pub fn http2OpenTransport(arena: *std.arena.Arena, t: *const Transport, cfg: Http2Config) Http2Error!*Http2Conn;
pub fn http2Submit(c: *Http2Conn, req: *Http2Request) Http2Error!u32;
pub fn http2Pump(c: *Http2Conn) Http2Error!PumpStatus;
pub fn http2Wait(c: *Http2Conn, stream_id: u32) Http2Error!void;
pub fn http2Release(c: *Http2Conn, stream_id: u32) Http2Error!void;
pub fn http2Get(c: *Http2Conn, url: []const u8, out: *http.Response, id_out: *u32) Http2Error!void;
pub fn http2Post(c: *Http2Conn, url: []const u8, body: []const u8, content_type: []const u8, accept: []const u8, out: *http.Response, id_out: *u32) Http2Error!void;
pub fn http2GetStream(c: *Http2Conn, url: []const u8, headers: []const http.Header, sink: *http.ResponseSink, out_head: *http.Response, id_out: *u32) Http2Error!void;
pub fn http2PostStream(c: *Http2Conn, url: []const u8, body_len: usize, content_type: []const u8, accept: []const u8, body: *http.RequestSource, sink: *http.ResponseSink, out_head: *http.Response, id_out: *u32) Http2Error!void;
pub const CloseStatus = enum(u8) { closed = 0, pending = 1 };
pub fn http2Close(c: *Http2Conn) CloseStatus;     // graceful; retry on pending
pub fn http2CloseForce(c: *Http2Conn) void;       // unconditional teardown; drops unsent output
pub fn http2ClosePending(c: *const Http2Conn) bool; // true = call http2Close again
pub fn http2Fd(c: *const Http2Conn) net.Socket;
```

`http2Request`:

```zig
pub const Http2Request = struct {
    method: []const u8,
    scheme: []const u8,
    authority: []const u8,
    path: []const u8,
    headers: []const http.Header,
    body: []const u8,                 // buffered body; empty for streaming
    body_len: usize,                  // 0 for buffered empty
    body_source: ?*http.RequestSource, // streaming body
    sink: ?*http.ResponseSink,        // streaming response
    out: *http.Response,              // status/headers; out.body is caller capacity when non-sink
    stream_id: u32,
    done: bool,
    failed: bool,
};
```

`http2Submit` is non-suspending: it queues a request and returns the odd stream
id. `http2Pump` performs all nonblocking I/O and frame dispatch. `http2Wait`
suspends with `@asyncSuspend(null)` until the stream is done or failed; it does
not call `http2Pump`.

**Stream lease and response ownership**

A submitted stream is leased until the caller releases it. `http2Wait` returns
when the stream completes or fails, but the slot is **not** reused and its
response state is not invalidated until `http2Release(c, stream_id)`. A
closed/reset slot is not a free slot; only `idle` slots and explicitly released
slots are reusable. `http2Wait` by id remains valid for the whole lease,
including after protocol close/reset. `http2Release` is idempotent only in the
sense that it returns `NoStream` for an unknown/already-released id; abandoned
streams are reclaimed by `http2Close`/`http2CloseForce`. Callers must read
`out.headers` before release.

`http2Close` is **graceful and retryable**. It flushes HTTP output first; if
that flush or the `TlsIo.close_pending` ciphertext state (tracked internally on
`Http2Conn`) still has pending output, it leaves `close_called` false, does not
invoke `close_fn`, returns `.pending`, and sets `http2ClosePending` true. The
caller waits for writability and calls `http2Close` again until it returns
`.closed` (usually one retry). A blocked close never leaks the socket or marks
the connection finalized.

`http2CloseForce` is the unconditional teardown path: it makes one best-effort
flush, then invokes `close_fn` exactly once and marks the connection closed. It
explicitly drops unsent frames; callers use it when they will not retry a
graceful close. `http2ClosePending` remains available for event loops that
prefer polling to the status return.

Buffered mode (`sink == null`) uses **caller-owned response storage**:
`out.body` is the capacity buffer at submit time. The response body is copied
into it; if the body exceeds the buffer or the 1 MiB buffered cap, the stream
fails with `TooLarge`. The final `out.body` is a subslice of the caller's
buffer, so it remains valid after release. `out.headers` points into the stream
slot and is valid only until `http2Release`; callers that need headers longer
copy them before release. Streaming mode (`sink != null`) writes body bytes to
the sink and does not use `out.body` storage. Convenience functions submit,
wait internally via `http2Wait`, and write the stream id to `id_out`; they do
not release implicitly. The id out-parameter exists because Z98 cannot lower a
suspending function whose result is an error-union payload in this wrapper shape
(see `examples/torrent_example_defects.md` D14); `Http2Error!void` + `*u32` is
the expressible form.

**Event-loop contract.** The caller selects `http2Fd` for **read and write**
readiness with a bounded timeout (never an infinite block), calls `http2Pump`
whenever either fires, and runs the `std.async` scheduler between iterations. A
stall watchdog (per-stream / per-connection deadline) is the caller's job.
Whenever `http2Pump` returns `would_block` with output still pending, the loop
must wait for writability before sleeping again — a read-only select stalls the
preface, SETTINGS, WINDOW_UPDATE and queued DATA. This is the cooperative
contract.

**Stream state**

- Client streams use odd ids; ids are never reused on a connection.
- States: `idle`, `open`, `half_closed_local`, `half_closed_remote`, `closed`,
  `reset`.
- `http2Submit` fails when the active stream table is full.
- `http2Pump` enforces server `MAX_CONCURRENT_STREAMS` when submitting.
- Headers and trailers: request pseudo-headers `:method`, `:scheme`,
  `:authority`, `:path`; response `:status`; other pseudo-headers are errors.
  Trailers are ignored after the first headers block.

**Flow control**

- Connection and per-stream receive windows start at 65535.
- DATA consumes the receive window; `http2Pump` queues WINDOW_UPDATE after the
  body is consumed (immediately for buffered, after `sink.write_fn` succeeds).
- Send windows are reduced by DATA; `http2Pump` sends queued request DATA only
  while the connection and stream windows allow it.
- `SETTINGS_INITIAL_WINDOW_SIZE` adjusts every open stream's send window by the
  delta; a negative window is represented by a signed 32-bit value.
- WINDOW_UPDATE with increment 0 is a protocol error.
- WINDOW_UPDATE sending is threshold-coalesced: emit when accumulated
  consumption reaches half the initial window, when the peer would otherwise
  stall, or at stream close; updates ride the writer queue (no extra record or
  syscall). Window math is O(1) per DATA (signed i32 connection + stream
  fields); no stream-table scans.
- Buffered response bodies are capped at 1 MiB and must fit the caller's
  `out.body` capacity; larger bodies use a sink. On a buffered `TooLarge`, the
  stream fails with `FailReason.too_large`, the connection receive credit for
  the rejected DATA is returned immediately via WINDOW_UPDATE, and **the pump
  continues**: a stream-local capacity failure is not a connection-level pump
  error. Low-level callers observe it via `http2Wait`/stream state; other
  streams in the same pump continue. The stream stays leased until
  `http2Release`. Streaming mode neither reads nor writes `out.body`.

**Frames and settings**

- Client preface: `PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n` followed by SETTINGS. The
  client sends this exactly once. The **server preface is its SETTINGS frame**;
  the client must never require or consume a peer-side PRI preface.
- Wire oracle: scripted tests use literal RFC/Node bytes for server data,
  never the production `CLIENT_PREFACE` constant as a peer preface.
- SETTINGS: `ENABLE_PUSH=0`, `MAX_CONCURRENT_STREAMS`, `INITIAL_WINDOW_SIZE`,
  `MAX_FRAME_SIZE`, `HEADER_TABLE_SIZE`, `MAX_HEADER_LIST_SIZE`.
- Handle SETTINGS ACK, PING ACK, WINDOW_UPDATE, GOAWAY, RST_STREAM,
  HEADERS/CONTINUATION/DATA.
- Ignore PRIORITY. Reject PUSH_PROMISE (push disabled).
- GOAWAY: fail streams above `last_stream_id`; no new streams; finish lower
  streams; close when idle.
- Frame size, header-list size, stream-id, and continuation ordering are
  bounds-checked before allocation.
- Parse layout (era CPU): zero allocation — the payload is an **in-place slice**
  of the 64 KiB read buffer and bounds checks are **per frame, never per byte**.
  CONTINUATION joins into pre-capped scratch (≤ `max_header_list`) with one
  decode pass at END_HEADERS — no per-continuation memmove. `FrameWriter`
  coalesces multiple frames into **one transport write per pump** so they share
  one TLS record and one syscall.
- For TLS, the caller must have selected `h2` via `tlsAlpnSelected`; otherwise
  `http2OpenTls` returns `error.NotHttp2`.

**HPACK**

- `sf/src/std_hpack.zig`:
  - Static table: RFC 7541 Appendix A (61 entries).
  - Dynamic table: caller-provided storage, default 4096 bytes, entries evicted
    by insertion order; no heap growth per entry.
  - Integer representation with 1..8-bit prefix.
  - String literal with Huffman flag; full HPACK Huffman decode (257 symbols,
    EOS rejected as a symbol); encode uses raw literals only.
  - Indexed fields, literal-with-incremental-indexing, literal-without-indexing,
    literal-never-indexed, and dynamic-table-size updates.
- Decoded header names/values are copied into the caller arena; the dynamic
  table keeps its own bounded copies.
- Algorithm pins (era CPU): Huffman decode uses a **two-level 8-bit canonical
  table** with a rare-code bit-walk tail — never a per-bit tree walk (5–10×
  slower); the dynamic table is a **ring buffer** with O(1) eviction (no
  memmove); static lookup is direct-index on decode, linear scan on encode.
- Encoding uses the static table where possible and literal-without-indexing
  otherwise; it never grows the encoder dynamic table.
- `SETTINGS_HEADER_TABLE_SIZE` from the server bounds the encoder table; the
  decoder honors the client's advertised table size.

### 7.3 HTTP/1.1 relationship

`std_http` is unchanged. `std_http2` is a separate path import. A caller opens a
TLS connection, requests ALPN (`alpn_h2 = true`), checks
`tlsAlpnSelected`; if it is `h2`, it uses `http2OpenTls`; otherwise it can use
the existing `std_http` HTTP/1.1 path. z9git never enables `alpn_h2`.

### 7.4 Memory and bounds

- Stream table: fixed `max_streams` entries in the connection arena.
- HPACK dynamic table: caller-provided `[4096]u8` (or configured size) storage.
- Frame read buffer: 64 KiB; write queue: 64 KiB.
- Header list: `max_header_list` cap; decoded strings in the per-request arena.
- Buffered response: 1 MiB cap and caller-owned `out.body` capacity; headers
  valid until `http2Release`.
- No per-connection unbounded growth from evicted HPACK entries or closed
  streams; stream slots are reused after close.
- Size arithmetic uses `u64` and rejects results above `0xFFFFFFFF`.

## 8. Testing

### 8.1 Offline

- HPACK RFC 7541 C.2/C.3/C.4 vectors: decoded header lists, dynamic table state,
  Huffman edge cases (EOS, padding), integer overflow/truncation.
- Frame codec vectors: header length/type/flags/stream id, SETTINGS, WINDOW_UPDATE,
  GOAWAY, RST, CONTINUATION ordering.
- Wire conformance: client PRI is emitted exactly once; server SETTINGS parses
  as the first server frame; no peer-side PRI is required. Scripted server data
  is literal wire bytes, independent of production constants.
- State-machine tests through `http2OpenTransport` with a scripted in-memory
  transport: stream lifecycle, flow-control windows, PING ACK, GOAWAY; partial
  write / `WouldBlock` mid-frame (pending output resumed across pumps);
  zero-increment WINDOW_UPDATE → protocol error; `SETTINGS_INITIAL_WINDOW_SIZE`
  mid-stream signed delta; bounded arena growth over many streams; slow-sink
  backpressure on one stream while a second stream flows.
- ALPN negative case: server selects a protocol the client never offered →
  handshake failure (never `h2`/`http11`).
- Every server-dependent fixture (ALPN, async I/O, tls_io, h2) also pins a
  deterministic **argless usage golden** (`expected.txt` usage line + nonzero
  `expected.rc`) so the discovery pin runs it safely without a server.

### 8.2 Local server

- The test harness writes an ephemeral Node 18+ (`http2` built-in; Node 20 in
  the dev environment) server into `/tmp`; no
  server source is committed.
- TLS: `http2.createSecureServer` with `ALPNProtocols: ['h2', 'http/1.1']`,
  using `examples/z98/demo/tls_demo/tests/certs/localhost.pem`/`.key`.
- Cleartext: `http2.createServer` for h2c prior knowledge.
- Cases: one request; two concurrent streams; interleaved DATA; large response
  (>= 256 KiB) with WINDOW_UPDATE; large request body; GOAWAY; RST_STREAM;
  ALPN fallback to `http/1.1`; malformed frame/HPACK rejection.
- If `node` is absent, the harness prints `SKIP` and exits 0; it never reports
  a false PASS.

### 8.3 Gates

- New fixtures under `-ffast` and `-fsafe`.
- `verify_stdlib.sh` and `run_crosscheck.sh`.
- Win9x cross-build + no-CRT + `check_win9x_imports.sh` `9x`/`nt` gates, run in
  the task that adds each module (`std_tls_io`, `std_hpack`, `std_http2`); no
  new OS imports.
- z9git is compile/link-checked at Task 1 and gets one mock-clone smoke at
  closeout (plus tls_demo and z9torr tier smokes); no full z9git tier.
- Testing is focused per task. **One** full std run happens at closeout
  (Task 9a); it repeats only if a later fix touches std source.
- `std_net` anchor re-baseline: verified-delta dump diff, goldens 5/5 identical,
  frozen-1124 zero movers, 8 pins and markers re-recorded once, **at the Task 2
  commit** (gate never red; later path modules move nothing).
- Seed v145 at closeout, rotated **after** the final fix wave; lib count 59
  (56 + `std_tls_io`, `std_hpack`, `std_http2`); fixed point expected unchanged.
  A seed rotated before a later std-source fix must be re-rotated, not shipped
  stale.

## 9. Security and performance

- h2c is cleartext and unauthenticated; it is for local/dev tests and explicit
  callers. TLS remains the authenticated transport.
- No server push; no priority; no connection coalescing across origins.
- No performance claims. The target is correctness/interoperability.
- HPACK header-list and frame-size caps are enforced before allocation.
- TLS handshake/certificate behavior is unchanged except ALPN.
- No new C runtime, no new Win9x imports.

## 10. Deferred

- z9git HTTP/2 integration.
- HPACK dynamic-table encoding, server push, priority tree.
- HTTP/2 Upgrade (`h2c` Upgrade).
- Connection coalescing and TLS session resumption.
- Trailers beyond ignoring them.
- Real Win9x h2 interoperability (cross-build/Wine only).
- Per-connection idle timeouts and keep-alive policy; the caller drives them.
- GHASH 8-bit table upgrade (4 KiB) for AES-GCM performance; a separate std
  change (moves pins, needs its own seed rotation).

## 11. Review focus

1. ALPN: TLS 1.2 ServerHello vs TLS 1.3 EncryptedExtensions; unsupported
   selection rejected; no-ALPN wire byte-identical.
2. `WouldBlock` correctness in `std_tls_io` and `http2Pump`; no blocking call,
   no busy-wait, no lost pending output.
3. HPACK Huffman/dynamic-table eviction and header-list bounds; malformed input
   fails closed.
4. Flow-control deadlock: large request/response bodies, WINDOW_UPDATE after
   consumption, zero increments, settings changes.
5. Stream lifecycle under GOAWAY/RST/END_STREAM; no use after close; stream-slot
   reuse; no unbounded arena growth.
6. Multiplexing with a slow sink; one stream must not corrupt another.
7. `std_net` barrel anchor movement and seed/docs truth.
8. z9git unchanged; HTTP/1.1 path unchanged.

## 12. Decisions and rulings

- **Ruling: `std_tls` stays sans-I/O.** The socket driver is the new
  `std_tls_io` companion. Adding sockets to `std_tls` would break its documented
  contract and the z9git driver pattern. Cost if wrong: an extra module and a
  small import layer; no behavior risk.
- **Ruling: `http2Pump` is non-suspending.** It returns `WouldBlock`; the caller
  owns readiness. This avoids an internal reader task that would spin under
  `std.async`. Cost if wrong: callers must integrate `select`.
- **Ruling: no automatic HTTP/1.1 fallback.** The caller checks ALPN; z9git is
  untouched. Cost if wrong: callers need one explicit branch.
- **Ruling: HPACK encode is literal-only.** Full decode is mandatory; dynamic
  encode is a future optimization. Cost if wrong: slightly larger request
  headers, no interoperability loss.

## 13. Language_Spec_Z98.md adjustments

Wording only — no new language features.

| Section | Edit |
|---|---|
| §1.5 Error Handling Types | Error sets are per-module named sets; `error{...}` lists interned names from any domain; cross-module `try` is a name-subset check; a non-superset needs an explicit catch-map or a widened set. |
| §3.3 Error Handling Expressions | Extend the "set-only" rule with name-subset semantics and the widen-or-map rule. |
| §4.1 Async / coroutines | Fn-pointer calls are never propagation edges or suspension points (a suspending function address is `error[3017]`); document the suspend-until + caller-driven pump contract; note the frame-layout rejection of `while` + `!?[]u8` returns (scalar-status core + thin wrapper workaround). |
| §5 Known Limitations | `?fn` with an error-union return (call-through-unwrap) is unproven; no suspending vtable is expressible. |
| §6.2 Manual Virtual Tables | Fn-ptr fields with `E!T` returns are legal (`std_http` precedent); the D8 typedef-ordering defect is fixed — holding vtables by pointer is optional conservatism. |
| FX17-F Function-Pointer Signature Matching | Signature matching covers error-union returns; `?fn` unwrap-matches one level. |
| §4 `@import` bullet | Truth-up the barrel list (17 members: io, fmt, arena, str, mem, math, debug, net, async, bits, os, time, page, gpa, pool, buf, fold). |
| §7.2 Designed, Not Implemented | Reference the HTTP/2 caller event-loop contract. |

Non-spec bookkeeping owned by the closeout task: module count 56→59 in
`STD_README.MD`, `docs/sf/QUICK_REF.md`, and the seed scripts.
- **Ruling: h2c prior knowledge only.** No Upgrade path. Cost if wrong: no
  support for cleartext servers that require Upgrade.
- **Ruling: `prefer_chacha20` flag.** Pure-C ChaCha20-Poly1305 is 2–4× faster
  than AES-GCM on era CPUs (GHASH ≈ 50–80% of HTTPS CPU; SOTA pure-C AES-GCM
  with a table GHASH still does not reach parity and keeps cache-timing
  exposure). Default `false` keeps existing wire fixtures byte-identical; the
  HTTP/2 path sets `true`. Cost if wrong: one config field; the server still
  picks the suite.
- **Ruling: `TlsIoError` is widened to the full `TlsError`∪`NetError` union.**
  A catch-map with a mandatory `else` silently misclassifies future upstream
  error names; widening makes the compiler flag each growth (≈ one extension per
  feature phase in this repo's history). Collapsing happens only into
  `Http2Error`. Cost if wrong: a 31-name public set on `std_tls_io`.
- **Ruling: server-dependent fixtures use argless usage goldens.** Keeps the
  discovery pin green and makes the no-server contract explicit. Cost if wrong:
  a fixture without a server cannot run a real case through discovery (already
  true).
- **Ruling: `std_net` async helpers stay, with the anchor re-baseline landing
  immediately at the Task 2 commit.** The gate is never red; the later path
  modules move no pins. Cost if wrong: one early verified-delta re-record.
