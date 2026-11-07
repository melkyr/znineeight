# Phase 3.3 — HTTP/2 Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a coroutine-driven HTTP/2 client with connection reuse and multiplexing, over TLS+ALPN and h2c prior knowledge, without changing z9git or the compiler.

**Architecture:** Phase 3.3a keeps `std_tls` sans-I/O and adds ALPN plus a nonblocking socket driver (`std_tls_io`) on top of `std_net`. Phase 3.3b adds `std_hpack` and `std_http2`; a caller-owned event loop calls a nonblocking `http2Pump`, while request coroutines submit streams and suspend in `http2Wait`.

**Tech Stack:** Z98 only; `std_tls`, `std_net`, `std_async`/coroutines, `std_arena`, `std_buf`; Node 18+ `http2` for local tests (Node 20 in the dev environment; ephemeral, not committed).

**Spec:** `docs/superpowers/specs/2026-11-07-phase33-http2-design.md`

## Global Constraints

- Pure Z98. No `@cImport`, `asm`, intrinsics, C macros, generics, methods, `anytype`, or `@alignCast`.
- `std_tls` stays sans-I/O. Socket I/O belongs to `std_tls_io` and `std_net`.
- `http2Pump` is non-suspending and returns `WouldBlock`; it never blocks.
- Request convenience functions are suspending and run under `std.async`; the caller drives `http2Pump` from its own readiness loop.
- z9git and `std_http` HTTP/1.1 behavior stay unchanged.
- TLS 1.2/1.3 only; HTTP/2 requires ALPN `h2` or h2c prior knowledge.
- `TlsConfig.prefer_chacha20: bool` (default `false`) reorders suites/groups
  ChaCha20-first and x25519-first when set; the HTTP/2 path sets `true`;
  default keeps existing wire fixtures byte-identical.
- `TlsIoError` = full `TlsError`∪`NetError` name union (31 names); collapse
  only into `Http2Error` at the HTTP/2 boundary.
- Event loop contract: select read AND write readiness with a bounded timeout
  and a stall watchdog; wake for writability whenever `http2Pump` reports
  pending output.
- No server push, no priority scheduling, no HTTP/2 Upgrade.
- **Wire conformance:** the client sends the 24-byte `PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`
  preface exactly once; the **server preface is its SETTINGS frame**. The client
  must never require a peer-side PRI preface. Scripted fixtures use literal
  RFC/Node wire bytes, never the production preface constant as server data.
- HPACK decoding is full (two-level canonical Huffman, ring dynamic table);
  HPACK encoding is literal-only.
- Buffered response bodies are capped at 1 MiB; larger bodies use `ResponseSink`.
- Header/frame/window/stream limits are checked before allocation; size math uses `u64` and rejects `> 0xFFFFFFFF`.
- Seed only at Task 9b **after** any final std-source fix; a seed rotated before
  a later fix is re-rotated, never shipped stale. `std_net` is barrel-exported; its 8-pin/marker
  re-baseline lands **immediately at the Task 2 commit** (fold-era
  verified-delta); later path modules move no pins.
- Server-dependent fixtures pin an argless usage golden (`expected.txt` usage
  line + nonzero `expected.rc`); fixture dirs and `expected_dirs.txt` updates
  land in the same commit.
- The HTTP/2 test server is generated in `/tmp` at run time; no server source
  is committed. Node 18+ required (Node 20 in the dev environment).
- If Node is absent, the server-backed tests print `SKIP` and never claim PASS.
- Test compiler: set `ZIG1` to a seed-built `zig1_5_clean`; refresh its sibling
  `lib/` with the task's new/changed std modules before each verify step. Offline `-ffast`
  runs use `bash scripts/stdlib/run_fixtures.sh "$ZIG1" <dir>...`; offline
  `-fsafe` runs use `bash scripts/stdlib/run_phase33_safe.sh "$ZIG1" <dir>...`.

## Review Focus

1. ALPN location: TLS 1.2 ServerHello vs TLS 1.3 EncryptedExtensions; unsupported selection rejected; `alpn_h2 = false` wire byte-identical; `prefer_chacha20` default keeps suites/groups byte-identical.
2. `WouldBlock` and pending-output correctness in `std_tls_io`/`http2Pump`; no blocking call, no busy-wait; partial write resumed across pumps; write-wake in the caller loop.
3. HPACK Huffman/dynamic-table eviction and header-list bounds; malformed input fails closed.
4. Flow-control deadlock for large request/response bodies; WINDOW_UPDATE after consumption; zero increments; SETTINGS window changes.
5. Stream lifecycle under GOAWAY/RST/END_STREAM; no use after close; slot reuse; bounded arena growth.
6. Multiplexing with a slow sink; one stream must not corrupt another.
7. `std_net` barrel pin/marker movement re-baselined at the Task 2 commit (verified-delta, gate never red) and seed/docs truth.
8. z9git and HTTP/1.1 paths unchanged.

---

### Task 0: Feasibility probes (no commits)

**Files:**
- Temporary only: `/tmp/phase33_probe/*`
- Read: `sf/src/std_tls.zig`, `sf/src/std_net.zig`, `sf/src/std_async.zig`, `examples/z98/z9torr/peer.zig`

**Interfaces:**
- Consumes: none.
- Produces: confirmed facts for Tasks 1–8; no repository file.

- [ ] **Step 1: Probe ALPN-capable TLS server**
Run `openssl version` and confirm `-alpn`, `-tls1_2`, `-tls1_3` are available. Start, then stop, `openssl s_server` with `examples/z98/demo/tls_demo/tests/certs/localhost.pem` and `.key`. Expected: server starts; no certificate error.
- [ ] **Step 2: Probe Node HTTP/2**
Run `node -e "require('http2'); console.log(process.version)"`. Expected: `v18+`.
- [ ] **Step 3: Probe nonblocking coroutine I/O pattern**
Compile a temporary copy of the z9torr-style `sendNonBlocking`/`@asyncSuspend` loop against the current lib. Expected: compiles under `-ffast` and `-fsafe`; no `@asyncSuspend` diagnostic.
- [ ] **Step 4: Probe error-returning fn-pointer struct field**
Compile a temporary struct with `read_fn: fn (*void, []u8) E!usize` (the `Transport` shape) and call through it. Expected: compiles and runs under `-ffast` and `-fsafe`.
- [ ] **Step 5: Probe new-module lib resolution**
Copy a throwaway `std_probe.zig` into `$ZIG1`'s sibling `lib/` and path-import it from a fixture. Expected: resolves via the importer-dir → `-I` → `<exe_dir>/lib` chain; confirms the per-task lib-refresh workflow.
- [ ] **Step 6: Record findings**
Write the probe outputs into the task report. If any probe fails, STOP and present the failure before Task 1.

---

### Task 1: TLS ALPN

**Files:**
- Modify: `sf/src/std_tls.zig`
- Modify: `examples/z98/z9git/httpgit.zig`
- Modify: `examples/z98/demo/tls_demo/main.zig`
- Modify: `repro/mi_matrix/stdlib_tls12_handshake_xmod/main.zig`
- Modify: `repro/mi_matrix/stdlib_tls13_auth_xmod/main.zig`
- Modify: `repro/mi_matrix/stdlib_tls13_fallback_xmod/main.zig`
- Modify: `repro/mi_matrix/stdlib_tls13_handshake_xmod/main.zig`
- Create: `repro/mi_matrix/stdlib_tls_alpn_xmod/main.zig`, `expected.txt`, `expected.rc`
- Create: `scripts/stdlib/run_phase33_safe.sh` (clone of `run_gpa_safe.sh`; accepts explicit dirs; default dirs grow per task)
- Create: `scripts/stdlib/run_tls_alpn.sh`
- Modify: `scripts/stdlib/expected_dirs.txt`
- Test: `scripts/stdlib/run_tls_alpn.sh`

**Interfaces:**
- Consumes: current `TlsConfig`, `TlsSession`, `tlsInit`, `tlsStep`.
- Produces:
  - `pub const AlpnProtocol = enum(u8) { none = 0, h2 = 1, http11 = 2, other = 3 };`
  - `TlsConfig.alpn_h2: bool`
  - `TlsConfig.prefer_chacha20: bool`
  - `TlsSession.alpn: AlpnProtocol`
  - `pub fn tlsAlpnSelected(sess: *const TlsSession) AlpnProtocol`

- [ ] **Step 1: Write the failing fixture**
Create `stdlib_tls_alpn_xmod/main.zig`. It takes `host:port` and a mode (`1.2h2`, `1.3h2`, `1.3http11`, `1.3none`, `1.3chacha`, `1.3badalpn`) from `argv`, loads the trust store exactly as `stdlib_tls13_handshake_xmod`, sets `alpn_h2 = true` for the h2 modes, performs the handshake, and prints `alpn=<none|h2|http11|other>`. `1.3chacha` also sets `prefer_chacha20 = true` and asserts the first ClientHello suite is `0x1303` and the first group is x25519; `1.3badalpn` runs against a server offering only a protocol the client never offers and asserts the result is never `h2`/`http11`. The fixture's argless run prints a usage line to stdout and exits 2 (pinned golden). Also create `scripts/stdlib/run_phase33_safe.sh` by cloning `run_gpa_safe.sh` and renaming its summary; it takes `<zig1> [dirs...]`; later tasks pass their fixture dirs explicitly (no per-task script edits).
- [ ] **Step 2: Run it against the missing API**
Run `bash scripts/stdlib/run_tls_alpn.sh "$ZIG1"`. Expected: compile failure on `alpn_h2`/`tlsAlpnSelected`.
- [ ] **Step 3: Add the API and extension**
In `std_tls.zig`, add the enum/fields/accessor. In `sendClientHello`, append extension 16 with `h2` then `http/1.1` when `alpn_h2`; when `prefer_chacha20`, order suites TLS 1.3 `0x1303` → `0x1301`, TLS 1.2 ChaCha pair before the AES pair, and `supported_groups` x25519 → secp256r1. Parse ALPN in TLS 1.2 `handleServerHello` and TLS 1.3 EncryptedExtensions. Reject a selected protocol not offered. Set `.none` in `tlsInit`.
- [ ] **Step 4: Update the six call sites**
Add `.alpn_h2 = false, .prefer_chacha20 = false` to z9git, tls_demo, and the four TLS fixtures. z9git and all existing wire bytes must not change.
- [ ] **Step 5: Verify**
Run `bash scripts/stdlib/run_tls_alpn.sh "$ZIG1"` and the existing TLS fixtures:
`bash scripts/stdlib/run_fixtures.sh "$ZIG1" repro/mi_matrix/stdlib_tls12_handshake_xmod repro/mi_matrix/stdlib_tls13_auth_xmod repro/mi_matrix/stdlib_tls13_fallback_xmod repro/mi_matrix/stdlib_tls13_handshake_xmod repro/mi_matrix/stdlib_tls_alpn_xmod` and the same dirs through `run_phase33_safe.sh`. Expected: ALPN modes print the selected protocol; `1.3none` prints `none`; `1.3chacha` shows ChaCha-first suite/group order; `1.3badalpn` never yields `h2`/`http11`; argless run prints the usage golden with rc 2; existing no-ALPN wire fixtures unchanged. Also compile/link z9git, tls_demo, and z9torr against the changed `std_tls` and run the tls_demo tier. Expected: all three build; tls_demo tier green.
- [ ] **Step 6: Commit**
`git add sf/src/std_tls.zig examples/z98/z9git/httpgit.zig examples/z98/demo/tls_demo/main.zig repro/mi_matrix/stdlib_tls* scripts/stdlib/run_tls_alpn.sh scripts/stdlib/run_phase33_safe.sh scripts/stdlib/expected_dirs.txt`
`git commit -m "feat(std): add TLS ALPN negotiation"`

---

### Task 2: Async socket helpers

**Files:**
- Modify: `sf/src/std_net.zig`
- Create: `repro/mi_matrix/stdlib_net_async_xmod/main.zig`, `expected.txt`, `expected.rc`
- Create: `scripts/stdlib/run_async_io.sh`
- Modify: `scripts/stdlib/expected_dirs.txt`
- Test: `scripts/stdlib/run_async_io.sh`

**Interfaces:**
- Consumes: `net.setNonBlocking`, `net.recvNonBlocking`, `net.sendNonBlocking`, `@asyncSuspend`.
- Produces:
  - `pub fn sendAllAsync(s: *Socket, data: []const u8) NetError!void`
  - `pub fn recvSomeAsync(s: *Socket, buf: []u8) NetError!usize`
- Note: no later task consumes these helpers (Task 3 pumps use the existing
  nonblocking calls; pumps must stay non-suspending). They are a general std
  utility and carry the plan's only anchor re-baseline.

- [ ] **Step 1: Write the failing fixture**
The fixture connects to a Node TCP echo server, sets the socket nonblocking, sends `hello`, receives 5 bytes, and prints `async=<text>`. Run it as a coroutine through `std.async`.
- [ ] **Step 2: Run it**
`bash scripts/stdlib/run_async_io.sh "$ZIG1" net`. Expected: compile failure on `sendAllAsync`/`recvSomeAsync`.
- [ ] **Step 3: Implement**
`sendAllAsync` loops over `sendNonBlocking`; on `WouldBlock` call `@asyncSuspend(null)` and retry; on 0 return `error.Io`; update the offset only after progress. `recvSomeAsync` loops over `recvNonBlocking`; on `WouldBlock` suspend; 0 means EOF.
- [ ] **Step 4: Verify**
Run the fixture under `-ffast` and `-fsafe`. Expected: `async=hello`; no busy loop; no error.
- [ ] **Step 5: Re-baseline the `std_net` anchors (immediate, fold-era)**
Run `bash scripts/compiler/gate_lower_depth.sh "$ZIG1"`: the 8 pins move (std_net barrel change). Verified-delta: dump diff of the 4 pin programs must be exactly the new `std_net` C + step-machine additions; goldens 5/5 byte-identical; frozen-1124 zero movers; live corpus unchanged. Re-record the 8 pins once in `gate_lower_depth.sh` and `docs/sf/QUICK_REF.md`; re-record markers with cause attribution (ruling-A format). Re-run the gate → OK. If goldens or frozen move, STOP.
- [ ] **Step 6: Commit**
`git add sf/src/std_net.zig repro/mi_matrix/stdlib_net_async_xmod scripts/stdlib/run_async_io.sh scripts/stdlib/expected_dirs.txt scripts/compiler/gate_lower_depth.sh docs/sf/QUICK_REF.md`
`git commit -m "feat(std): add coroutine socket helpers and re-baseline emission pins"`

---

### Task 3: TLS socket driver

**Files:**
- Create: `sf/src/std_tls_io.zig`
- Create: `repro/mi_matrix/stdlib_tls_io_xmod/main.zig`, `expected.txt`, `expected.rc`
- Modify: `scripts/stdlib/expected_dirs.txt`
- Test: `scripts/stdlib/run_async_io.sh`

**Interfaces:**
- Consumes: Task 1 `tlsAlpnSelected`; Task 2 socket helpers; current `tlsStep`/`tlsRead`/`tlsWrite`.
- Produces: `TlsIo`, `TlsIoError`, `tlsIoInit`, `tlsIoHandshakePump`, `tlsIoReadPump`, `tlsIoWritePump`, `tlsIoClose`, `tlsIoCloseForce`, `tlsIoPending`, `tlsIoClosePending` exactly as specified in the spec.

- [ ] **Step 1: Write the failing fixture**
Connect to a Node TLS echo server with localhost certs; use `tlsIoHandshakePump` until established; write `ping`; read 4 bytes; print `tlsio=ping`. The fixture runs under `std.async` and calls the pump from the scheduler task while a readiness loop drives the socket. The argless run prints a usage line and exits 2 (pinned golden).
- [ ] **Step 2: Run it**
`bash scripts/stdlib/run_async_io.sh "$ZIG1" tlsio`. Expected: compile failure on `std_tls_io`.
- [ ] **Step 3: Implement**
Own `out` and `in` buffers. Flush pending output before every step. `tlsIoHandshakePump` loops `tlsStep`, buffering `.send` output and reading on `.recv`/`.wait`; return `WouldBlock` when `sendNonBlocking`/`recvNonBlocking` does. `tlsIoReadPump` returns buffered app bytes, otherwise feeds a record then loops; 0 on close. `tlsIoWritePump` chunks plaintext at `TLS_MAX_PLAINTEXT_RECORD`, buffers one protected record, flushes, and returns consumed plaintext. `TlsIoError` is the widened full `TlsError`∪`NetError` union — use bare `try` (no catch-map); an upstream growth fails at compile time by design.
- [ ] **Step 4: Verify**
Run `bash scripts/stdlib/run_async_io.sh "$ZIG1" tlsio` under `-ffast` and `-fsafe`. Expected: `tlsio=ping`; `WouldBlock` is exercised at least once (the fixture prints `wb>=1`).
- [ ] **Step 5: Win9x cross-build + import gates**
Cross-build a minimal `std_tls_io` driver with `scripts/win32_cross/cross_nocrt.sh` and run `check_win9x_imports.sh <exe> 9x`; repeat with `cross_build_run.sh` and `check_win9x_imports.sh <exe> nt`. Expected: both gates PASS; imports unchanged (KERNEL32+WSOCK32 only).
- [ ] **Step 6: Commit**
`git add sf/src/std_tls_io.zig repro/mi_matrix/stdlib_tls_io_xmod scripts/stdlib/run_async_io.sh scripts/stdlib/expected_dirs.txt`
`git commit -m "feat(std): add nonblocking TLS socket driver"`

---

### Task 4: HPACK

**Files:**
- Create: `sf/src/std_hpack.zig`
- Create: `repro/mi_matrix/stdlib_hpack_vectors_xmod/main.zig`, `expected.txt`, `expected.rc`
- Create: `repro/mi_matrix/stdlib_hpack_huffman_xmod/main.zig`, `expected.txt`, `expected.rc`
- Create: `repro/mi_matrix/stdlib_hpack_dynamic_xmod/main.zig`, `expected.txt`, `expected.rc`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes: `std.arena`, `std.buf`, `std.mem`.
- Produces:
  - `pub const HpackHeader = struct { name: []const u8, value: []const u8 };`
  - `pub const Hpack = struct { /* caller storage; dynamic table state */ };`
  - `pub fn hpackInit(h: *Hpack, storage: []u8) void`
  - `pub fn hpackDecode(h: *Hpack, block: []const u8, out: []HpackHeader, arena: *std.arena.Arena) HpackError!usize`
  - `pub fn hpackEncode(headers: []const HpackHeader, out: *std.buf.Buf) HpackError!void`

- [ ] **Step 1: Write the RFC vector fixtures**
`stdlib_hpack_vectors_xmod` decodes RFC 7541 C.2/C.3/C.4 blocks and prints each `name: value` line. `stdlib_hpack_huffman_xmod` decodes the Huffman examples and a truncated/EOS case. `stdlib_hpack_dynamic_xmod` decodes a sequence that inserts, indexes, and evicts entries, then prints the table size and survivors.
- [ ] **Step 2: Run them**
`bash scripts/stdlib/run_fixtures.sh "$ZIG1" repro/mi_matrix/stdlib_hpack_vectors_xmod repro/mi_matrix/stdlib_hpack_huffman_xmod repro/mi_matrix/stdlib_hpack_dynamic_xmod`. Expected: compile failure on `std_hpack`.
- [ ] **Step 3: Implement**
Add the 61-entry static table, integer/string decoders, Huffman decode, dynamic table with caller storage and eviction, and literal-only encoder. Algorithm pins: Huffman decode is a **two-level 8-bit canonical table** with a rare-code bit-walk tail (never a per-bit tree walk); the dynamic table is a **ring buffer** with O(1) eviction (no memmove); static lookup is direct-index on decode, linear scan on encode. Decode copies names/values into `arena`; the dynamic table copies into its storage. Reject EOS as a symbol, overlong integers, table-size updates above configured storage, and header lists exceeding `out.len` — all as `HpackError.Corrupt`, never a `-fsafe` trap (pre-validate before every `@intCast`/shift/index).
- [ ] **Step 4: Verify**
Run `bash scripts/stdlib/run_fixtures.sh "$ZIG1" repro/mi_matrix/stdlib_hpack_vectors_xmod repro/mi_matrix/stdlib_hpack_huffman_xmod repro/mi_matrix/stdlib_hpack_dynamic_xmod` and the same dirs through `run_phase33_safe.sh`. Expected: exact expected lines; malformed cases return `HpackError.Corrupt` and print `corrupt`. Also cross-build a minimal `std_hpack` driver with the Task 3 Step 5 recipe (`cross_nocrt`+`9x`, `cross_build_run`+`nt`): gates PASS, no new imports.
- [ ] **Step 5: Commit**
`git add sf/src/std_hpack.zig repro/mi_matrix/stdlib_hpack_* scripts/stdlib/expected_dirs.txt`
`git commit -m "feat(std): add HPACK codec"`

---

### Task 5: HTTP/2 frame codec

**Files:**
- Create: `sf/src/std_http2.zig`
- Create: `repro/mi_matrix/stdlib_http2_frames_xmod/main.zig`, `expected.txt`, `expected.rc`
- Modify: `scripts/stdlib/expected_dirs.txt`
- Test: `scripts/stdlib/run_fixtures.sh`

**Interfaces:**
- Consumes: none beyond `std`.
- Produces:
  - `pub const FrameType = enum(u8) { data = 0, headers = 1, priority = 2, rst_stream = 3, settings = 4, push_promise = 5, ping = 6, goaway = 7, window_update = 8, continuation = 9 };`
  - `pub const Frame = struct { typ: FrameType, flags: u8, stream_id: u32, payload: []const u8 };`
  - `pub const Settings = struct { header_table_size: u32, enable_push: bool, max_concurrent_streams: u32, initial_window_size: u32, max_frame_size: u32, max_header_list_size: u32 };`
  - `pub fn frameParseHeader(raw: []const u8) Http2Error!FrameHeader`
  - `pub fn frameNext(r: *FrameReader, out: *Frame) Http2Error!bool`
  - `pub fn frameAppend(w: *FrameWriter, typ: FrameType, flags: u8, stream_id: u32, payload: []const u8) Http2Error!void`
  - `pub fn settingsParse(raw: []const u8, out: *Settings) Http2Error!void`
  - `pub fn settingsEncode(out: []u8, s: Settings) Http2Error!usize`

- [ ] **Step 1: Write the failing fixture**
Feed fixed frame bytes: SETTINGS, SETTINGS ACK, HEADERS with END_HEADERS, DATA with END_STREAM, WINDOW_UPDATE, PING, GOAWAY, RST_STREAM. Print `type flags stream len` for each and the parsed settings. Include bad length, bad stream id, and a CONTINUATION without END_HEADERS.
- [ ] **Step 2: Run it**
`bash scripts/stdlib/run_fixtures.sh "$ZIG1" repro/mi_matrix/stdlib_http2_frames_xmod`. Expected: compile failure on `std_http2`.
- [ ] **Step 3: Implement**
9-byte header; 24-bit length; 16 MiB max parse bound; type-specific payload validation; settings values validated (`initial_window_size <= 2^31-1`, `max_frame_size` in 16384..16777215, no duplicate/unknown handling beyond ignore). Frame append refuses payloads above `max_frame_size`. Parse layout: zero allocation — payload is an in-place slice of the read buffer, bounds checks per frame (never per byte); `FrameReader` is a sliding window compacted only past half; `FrameWriter` appends frames for one coalesced write per pump.
- [ ] **Step 4: Verify**
Run `bash scripts/stdlib/run_fixtures.sh "$ZIG1" repro/mi_matrix/stdlib_http2_frames_xmod` and `bash scripts/stdlib/run_phase33_safe.sh "$ZIG1" repro/mi_matrix/stdlib_http2_frames_xmod`. Expected: exact `type flags stream len` lines; malformed cases print `bad`. Also cross-build a minimal `std_http2` driver with the Task 3 Step 5 recipe: `9x`/`nt` gates PASS, no new imports.
- [ ] **Step 5: Commit**
`git add sf/src/std_http2.zig repro/mi_matrix/stdlib_http2_frames_xmod scripts/stdlib/expected_dirs.txt`
`git commit -m "feat(std): add HTTP/2 frame codec"`

---

### Task 6: Connection, streams, and flow control

**Files:**
- Modify: `sf/src/std_http2.zig`
- Create: `repro/mi_matrix/stdlib_http2_state_xmod/main.zig`, `expected.txt`, `expected.rc`
- Modify: `scripts/stdlib/expected_dirs.txt`
- Test: `scripts/stdlib/run_fixtures.sh`

**Interfaces:**
- Consumes: Task 4 HPACK; Task 5 frames/settings.
- Produces:
  - `pub const Transport = struct { state: *void, read_fn: fn (*void, []u8) TransportError!usize, write_fn: fn (*void, []const u8) TransportError!usize, close_fn: fn (*void) void };` (four fields; TLS close-pending is tracked internally on `Http2Conn`)
  - `pub const Http2Config`, `Http2Request`, `PumpStatus`, `Http2Conn` as in the spec.
  - `http2OpenTransport`, `http2Submit`, `http2Pump`, `http2Wait`, `http2Release`, `http2Close` (`CloseStatus`), `http2CloseForce`, `http2ClosePending`.

- [ ] **Step 1: Write the failing state fixture**
Use a scripted `Transport` in the fixture: it returns the server preface/SETTINGS, then a HEADERS block and DATA for one stream. Submit two requests; pump; assert `:status`, body, stream ids, flow-control windows, SETTINGS ACK, and PING ACK. Add a scripted GOAWAY and an RST case; a partial write (`WouldBlock` mid-frame) resumed across pumps with no lost output; a zero-increment WINDOW_UPDATE → `error.Protocol`; a mid-stream `SETTINGS_INITIAL_WINDOW_SIZE` change with signed window delta; and a many-stream run asserting bounded arena growth (peak stays under a fixed cap after 100 submit/complete cycles).
- [ ] **Step 2: Run it**
`bash scripts/stdlib/run_fixtures.sh "$ZIG1" repro/mi_matrix/stdlib_http2_state_xmod`. Expected: compile failure on `Http2Conn`.
- [ ] **Step 3: Implement**
Connection preface and SETTINGS; read/write queues; stream table; odd ids; frame dispatch; HPACK decode; O(1) signed-i32 window fields (no stream-table scans); threshold-coalesced WINDOW_UPDATE (≥ half initial window / stall-prevented / stream close) riding the writer queue; PING ACK; SETTINGS ACK with signed initial-window delta; GOAWAY; RST; END_STREAM. CONTINUATION joins into pre-capped scratch (≤ `max_header_list`) with one decode pass. `http2Submit` queues; `http2Pump` is nonblocking and returns `would_block`; `http2Wait` suspends (`@asyncSuspend` loop) until done. Keep all allocations in the caller arena. A closed/reset slot is **leased**, not free: it is reusable only after `http2Release(c, stream_id)` returns it to `idle`; `http2Wait` by id remains valid for the lease. `http2Close` reclaims abandoned leases.
- [ ] **Step 4: Verify**
Run `bash scripts/stdlib/run_fixtures.sh "$ZIG1" repro/mi_matrix/stdlib_http2_state_xmod` and the same dir through `run_phase33_safe.sh`. Expected: `streams=2`, `status=200`, `body=a/b`, `settings_ack=1`, `ping_ack=1`, `goaway=1`, `rst=1`, `wb_resume=1`, `zero_wu=protocol`, `win_delta=ok`, `arena_ok=1`.
- [ ] **Step 5: Commit**
`git add sf/src/std_http2.zig repro/mi_matrix/stdlib_http2_state_xmod scripts/stdlib/expected_dirs.txt`
`git commit -m "feat(std): add HTTP/2 connection and stream core"`

---

### Task 7: TLS/TCP adapters and body API

**Files:**
- Modify: `sf/src/std_http2.zig`
- Create: `repro/mi_matrix/stdlib_http2_body_xmod/main.zig`, `expected.txt`, `expected.rc`
- Modify: `scripts/stdlib/expected_dirs.txt`
- Test: `scripts/stdlib/run_fixtures.sh`

**Interfaces:**
- Consumes: Task 3 `TlsIo`; Task 6 connection.
- Produces:
  - `http2OpenTls`, `http2OpenTcp`, `http2Fd`, `http2Get`, `http2Post`, `http2GetStream`, `http2PostStream`, `http2Release`.
  - Convenience functions are `Http2Error!void` with a trailing `id_out: *u32`; they submit, wait internally via `http2Wait`, write the stream id, and do not release. Callers read headers/body then `http2Release`.
  - `http2OpenTls` returns `error.NotHttp2` unless `tlsAlpnSelected(io.sess) == .h2`.
  - Buffered bodies are capped at 1 MiB and copied into the caller's **`out.body` capacity**; `TooLarge` if it does not fit. `TooLarge` is stream-local: `http2Pump` continues, `http2Wait` returns `error.TooLarge`, and other streams keep running. Headers remain valid until release. `sink`/`body_source` use the existing `std_http` types.

- [ ] **Step 1: Write the failing body fixture**
Use the scripted transport to test: buffered GET, buffered POST, streaming response sink, streaming request source, body > 1 MiB rejection for buffered mode, body-too-small rejection, one stream's sink error not corrupting another, and a slow sink (short `write_fn` accepts) on one stream while a second stream completes — assert deferred WINDOW_UPDATE on the slow stream and no stall on the other. For each buffered request, set `out.body` to a caller buffer, `http2Wait`, read headers/body, then `http2Release`; assert the stream is `NoStream` after release and the slot is reusable. Print `body=<...>`, `sink=<n>`, `source=<n>`, `large=too_large`, `small_buf=too_large`, `release=1`, `slow_ok=1`. The h2 test configs set `prefer_chacha20 = true` (Suite order is exercised in Task 1; here it only rides along).
- [ ] **Step 2: Run it**
`bash scripts/stdlib/run_fixtures.sh "$ZIG1" repro/mi_matrix/stdlib_http2_body_xmod`. Expected: compile failure on the body APIs.
- [ ] **Step 3: Implement**
Map `http.Response`, `http.Header`, `http.ResponseSink`, and `http.RequestSource` onto streams. Build pseudo-headers from the URL; lowercase names; reject connection-specific headers. Lease each slot until `http2Release`; closed/reset is not free. Buffer response bytes into the caller's `out.body` capacity, up to 1 MiB, otherwise `TooLarge`; headers stay valid until release. Streaming bodies consume the receive window only after a successful sink write; request sources send DATA only inside the send window. Convenience functions are `Http2Error!void` with a trailing `id_out: *u32`: they submit, wait internally via `http2Wait`, write the id, and do not release. The id out-parameter is required because Z98 cannot lower this wrapper shape as a suspending `Http2Error!u32` (D14 in `examples/torrent_example_defects.md`). The TLS/TCP adapters catch-map `TlsIoError` into `Http2Error` at this boundary (cert-class names collapse to `BadCertificate`/`AuthenticationFailed`; everything else maps 1:1 or to `Io`).
- [ ] **Step 4: Verify**
Run `bash scripts/stdlib/run_fixtures.sh "$ZIG1" repro/mi_matrix/stdlib_http2_body_xmod` and the same dir through `run_phase33_safe.sh`. Expected: exact lines including `release=1` and `small_buf=too_large`; no leak/corruption across two streams; after `http2Release` the stream id is `NoStream` and the slot is reusable.
- [ ] **Step 5: Commit**
`git add sf/src/std_http2.zig repro/mi_matrix/stdlib_http2_body_xmod scripts/stdlib/expected_dirs.txt`
`git commit -m "feat(std): add HTTP/2 body API"`

---

### Task 8: Local h2 integration tests + wire conformance

**Files:**
- Create: `scripts/stdlib/run_http2.sh`
- Create: `repro/mi_matrix/stdlib_http2_tls_xmod/main.zig`, `expected.txt`, `expected.rc`
- Create: `repro/mi_matrix/stdlib_http2_h2c_xmod/main.zig`, `expected.txt`, `expected.rc`
- Modify: `scripts/stdlib/expected_dirs.txt`
- Modify: `sf/src/std_http2.zig`
- Modify: `repro/mi_matrix/stdlib_http2_state_xmod/main.zig`
- Modify: `repro/mi_matrix/stdlib_http2_body_xmod/main.zig`

**Interfaces:**
- Consumes: Task 7 API.
- Produces: server-backed tests only; no server source committed. The scripted fixtures become the independent wire oracle.

- [ ] **Step 0: Wire conformance + walking skeleton (root-cause fix)**
Update `stdlib_http2_state_xmod` and `stdlib_http2_body_xmod` so the scripted **server** sends only literal server bytes (SETTINGS/frames); remove any client `PREFACE_BYTES` from the server→client stream. Keep the assertion that the client emits the 24-byte preface exactly once. Run the scripted fixtures first: expected RED against the current library (`error.NotHttp2`). Then remove the peer-preface expectation from `processBuffered` in `sf/src/std_http2.zig`: the client sends PRI; the server preface is SETTINGS. Add a literal wire-vector assertion/fixture that does not import the production `CLIENT_PREFACE` constant. Refresh `zig1/lib/std_http2.zig`, run the h2c one-GET Node smoke before TLS, and then the scripted state/body/frames fixtures. Expected GREEN.

- [ ] **Step 1: Write the failing integration fixtures**
`stdlib_http2_tls_xmod` takes a URL, opens TLS with `alpn_h2=true, prefer_chacha20=true`, checks `tlsAlpnSelected == .h2`, opens `http2OpenTls`, submits two GETs concurrently, and prints both bodies and status. `stdlib_http2_h2c_xmod` does the same over cleartext with `http2OpenTcp`. Each buffered GET supplies a caller `out.body` buffer and an `id_out`, calls the convenience function (which waits internally), reads headers/body, then calls `http2Release`; both drive the event loop per the spec contract: `select` read AND write readiness with a bounded timeout, a per-stream stall watchdog, and a writability wait whenever `http2Pump` returns `would_block` with pending output. Both argless runs print a usage line and exit 2 (pinned goldens).
- [ ] **Step 2: Write the ephemeral server harness**
`run_http2.sh` checks for `node` (v18+). If absent, print `SKIP: node not found` and exit 0. Otherwise create `mktemp -d`, write `server.js` there (not in the repo), start `http2.createSecureServer` with `ALPNProtocols: ['h2','http/1.1']` and the localhost cert/key, and a second `http2.createServer` for h2c. Write the selected port to a file, run the fixture with the URL, compare output, kill the server, clean the temp dir. Mode selection: the script builds each fixture twice — once emitting `-ffast`, once with the compiler default (`-fsafe`) — and requires both to match the goldens.
- [ ] **Step 3: Add cases**
Server routes: `/a` and `/b` (multiplexing), `/large` (256 KiB), `/rst` (RST_STREAM), `/goaway` (GOAWAY), `/echo` (POST echo), `/alpn11` (TLS server selects `http/1.1`). Assert ALPN fallback returns `NotHttp2`; assert h2c works; assert large body flow control; assert GOAWAY/RST errors.
- [ ] **Step 4: Verify**
Run `bash scripts/stdlib/run_http2.sh "$ZIG1"` (both `-ffast` and `-fsafe` internally). Expected: `HTTP2 TLS PASS`, `HTTP2 H2C PASS`, `HTTP2 FLOW PASS`, `HTTP2 GOAWAY PASS`, `HTTP2 RST PASS`, `HTTP2 FALLBACK PASS`; or `SKIP` when Node is absent.
- [ ] **Step 5: Commit**
`git add scripts/stdlib/run_http2.sh repro/mi_matrix/stdlib_http2_tls_xmod repro/mi_matrix/stdlib_http2_h2c_xmod scripts/stdlib/expected_dirs.txt sf/src/std_http2.zig repro/mi_matrix/stdlib_http2_state_xmod repro/mi_matrix/stdlib_http2_body_xmod`
`git commit -m "test(std): add local HTTP/2 integration tier"`

---

### Task 9a: Full battery

**Files:**
- Test: existing battery scripts + `run_tls_alpn.sh`, `run_async_io.sh`, `run_http2.sh`, `run_phase33_safe.sh`.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: a green battery record; pins/markers proven unchanged since Task 2.

- [ ] **Step 1: Run the std battery**
Run `bash scripts/stdlib/verify_stdlib.sh "$ZIG1"`, `bash scripts/stdlib/run_crosscheck.sh "$ZIG1"`, `bash scripts/stdlib/run_fixtures.sh "$ZIG1"`, `bash scripts/stdlib/run_gpa_safe.sh "$ZIG1"`, `bash scripts/stdlib/run_phase33_safe.sh "$ZIG1"`, and the new `run_tls_alpn.sh`, `run_async_io.sh`, `run_http2.sh`. Record pass/fail/skip. Expected: all non-Node tests pass; Node tests pass when Node is present or print explicit SKIP.
- [ ] **Step 2: Consumer smokes**
Run the tls_demo tier and the z9torr tier (the real `std_tls`/`std_net` consumers), plus one z9git mock-clone smoke (a single clone against the local mock HTTP server used by the z9git tests — proves the HTTP/1.1 path end to end). Expected: all green. No `tier_git.sh` full run.
- [ ] **Step 3: Anchor sanity**
Run `bash scripts/compiler/gate_lower_depth.sh "$ZIG1"`. Expected: OK with the Task 2 pins — no movement from the path-module work. If anything moved, STOP and investigate.
- [ ] **Step 4: Commit only if this task changed test files**
If the battery run required no test/source edits, make no empty commit; record the pass/fail/skip summary in the SDD report and ledger. If it did change files, `git add tests scripts/stdlib` and commit `test(phase33): closeout std run and consumer smokes`.

---

### Task 9b: Seed v145

**Files:**
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (copy lists: `std_tls_io.zig`, `std_hpack.zig`, `std_http2.zig`; counts 56 -> 59; header comments, `SEED_README.txt` heredoc strings at `archive_seed.sh:378,395,493`, `build_from_seed.sh:24,146`).
- Modify: `docs/sf/QUICK_REF.md` install-cp list (~:506).

**Interfaces:**
- Consumes: Task 9a green battery.
- Produces: seed v145.

- [ ] **Step 1: Rotate seed v145**
Add the three new modules to the copy lists and update every 56 -> 59 string. Run `archive_seed.sh` and the two-hop `build_from_seed.sh` closure. Expected: hop1 == hop2; fixed point unchanged (compiler does not import the new modules); lib 59; archive/zip/manifest md5 recorded.
- [ ] **Step 2: Commit**
`git add scripts/seed release/seed docs/sf/QUICK_REF.md`
`git commit -m "chore(seed): rotate v145 (phase 3.3 HTTP/2)"`

---

### Task 9c: Docs and Z98 spec wording

**Files:**
- Modify: `README.md`, `STD_README.MD`, `docs/sf/QUICK_REF.md`, `release/seed/CHANGELOG.md`.
- Modify: `docs/reference/Language_Spec_Z98.md` per the spec's §13 table.

**Interfaces:**
- Consumes: Tasks 9a/9b.
- Produces: the documented surface.

- [ ] **Step 1: Update docs**
Document ALPN and `prefer_chacha20`, h2c, the pump/event-loop contract (read+write select, bounded timeout, watchdog), HPACK literal encode, the stream lease/`http2Release` lifetime, caller-owned `out.body` capacity, body cap, no push/priority/Upgrade, Node test SKIP, argless goldens, and z9git unchanged. Add `std_tls_io`/`std_hpack`/`std_http2` to the std list (56 -> 59). Do not claim Win9x h2 hardware testing.
- [ ] **Step 2: Update Language_Spec_Z98.md**
Apply the spec's §13 table: §1.5/§3.3 error-set name-subset + widen-or-map rule; §4.1 fn-pointer-never-suspends + pump contract + `!?[]u8`+while limitation; §5 `?fn`+EU unproven; §6.2 D8 note; FX17-F; §4 barrel truth-up (17 members); §7.2 event-loop reference.
- [ ] **Step 3: Commit**
`git add README.md STD_README.MD docs/sf/QUICK_REF.md release/seed docs/reference/Language_Spec_Z98.md`
`git commit -m "docs(phase33): document HTTP/2 surface and Z98 spec wording"`

---

### Task 10: Final whole-branch review and fixes

**Files:**
- Review range: `f400e135..HEAD` (plus any operator-authorized baseline adjustment).
- Create: review package under the SDD workspace; no production file list until findings arrive.

**Interfaces:**
- Consumes: Task 1–9c.
- Produces: final review record and any fix commits.

- [ ] **Step 1: Generate the review package**
Run the SDD skill's `review-package` script (superpowers:subagent-driven-development) for the full 3.3 range; include the spec and plan paths.
- [ ] **Step 2: Dispatch a fresh reviewer**
Use the most capable available reviewer; include the Review Focus list and the ledger rulings. No self-review as the only gate.
- [ ] **Step 3: Fix Critical/Important**
Fix only Critical/Important findings, each with a failing-then-passing test; run the focused tests covering the fix. Record deferred minors.
- [ ] **Step 4: Final gate**
Run `git diff --check` and the seed closure; re-run the one full std run (Task 9a Step 1) **only if a fix touched std source**. Expected: all green; Node-backed tests either PASS or explicit SKIP.
- [ ] **Step 5: Stop**
Hand the branch back. Do not merge/push unless the operator asks. z9git remains HTTP/1.1.

---

### Amendment — final review finding 7 (close retry)

The final review found `http2Close` could not honor `TlsIo.close_pending`: a
flush that would block left the socket open after the connection marked itself
closed. The fix is **CloseStatus + force**, not a required `Transport` field:

- `Transport` keeps its four public fields; TLS close-pending is tracked
  internally on `Http2Conn` (`tls_io`), set by `http2OpenTls`.
- `http2Close(c) CloseStatus` is graceful/retryable: `.pending` leaves the
  socket open and `close_called` false; the caller retries on writability.
- `http2CloseForce(c) void` is unconditional teardown: one best-effort flush,
  close exactly once, drops unsent frames. The TLS path uses
  `tlsIoCloseForce`, which guarantees the fd closes even when the final
  ciphertext flush would block; TCP/Transport uses `close_fn`.
- `http2ClosePending(c) bool` remains for event loops.
- `TooLarge` is stream-local: `http2Pump` continues; `http2Wait` returns
  `error.TooLarge`.
- Graceful close also checks `tlsIoPending` (queued ciphertext) and
  `tlsIoClosePending`; it never finalizes until the TLS fd is actually closed,
  and re-checks after `close_fn` in case the close deferred.
- Malformed response header semantics are stream-local (RFC 7540 §8.1.2.6):
  RST that stream, keep the pump running, and `http2Wait` returns
  `error.Protocol`; HPACK `Corrupt` stays connection-level.
- Seed v144 rotated before this wave is stale; rotate **v145** from the final
  HEAD and rerun the full battery.

---

## Self-review

- **Spec coverage:** 3.3a ALPN + suite preference → Task 1; async transport + anchor re-baseline → Tasks 2–3; HPACK → Task 4; frames → Task 5; connection/streams/flow → Task 6; bodies/adapters → Task 7; TLS+h2c tests → Task 8; battery → Task 9a; seed → Task 9b; docs/spec wording → Task 9c; review → Task 10.
- **Step scan:** Every implementation step names a signature/file; every test step has a command and expected output; no "handle edge cases" steps.
- **Type consistency:** `TlsConfig.alpn_h2` and `tlsAlpnSelected` are used by Tasks 4–8; `Transport`/`Http2Conn` names are consistent between Tasks 6–8; body types are the existing `std_http` types.
- **Review Focus:** each line has an owning task: ALPN → Task 1; WouldBlock/pending-output → Tasks 3/6/8; HPACK → Task 4; flow control → Tasks 6/8; stream lifecycle → Tasks 6/8; multiplexing → Task 8; anchors/seed → Tasks 2/9b; z9git unchanged → Tasks 9a/10.
- **Proportion:** the plan names interfaces and tests, not implementation bodies; the algorithms (HPACK Huffman, flow control) are constrained by the spec and fixtures.
