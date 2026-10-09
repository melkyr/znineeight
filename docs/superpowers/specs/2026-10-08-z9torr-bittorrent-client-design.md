# z9torr — BitTorrent client example — Design

> **Status:** Draft 2026-10-08 (awaiting operator review). Program-level
> spec: the milestone plans in §11 argue from this document.
>
> **Blueprint (source material):** `examples/ztorr_blp.txt`
> ("z9torr — Technical blueprint, revision 2", 577 lines). Untracked and
> gitignored (`*.txt`); this spec is the durable, committed source of
> record. Where the blueprint and this spec disagree, **this spec wins**.

**Goal:** Build `examples/z98/z9torr`, a working single-file BitTorrent
downloader written in Z98 (C89 / 32-bit Win9x / 16 MB RAM target), with
**resumable downloads** across restarts, plus the minimal std-lib additions
the client needs (`std_net` primitives, `std_bencode`, `std_http`).

**Architecture:** Hybrid. Generic OS/codec primitives go into the std lib
(the libc analogue): a few `std_net` socket additions, a `std_bencode`
codec (a general serialization format, sibling of `std_base64`/`std_hex`/
`std_utf8`), and a `std_http` HTTP/1.1 GET client. BitTorrent-specific logic
(torrent metadata, tracker protocol, peer wire, piece scheduling, rate/stats,
resume) lives in the example. The compiler imports zero std modules, so none
of this moves the compiler fixed point.

**Tech Stack:** Z98 (`zig1` self-hosted compiler, C89 emission), the
seed-built `zig1_5_clean` (+ its sibling `lib/`), `gcc -m32 -std=c89`,
POSIX `sh`/`make`/`cmp`/`diff`/`sha1sum` (no Python/Perl/curl/netcat in the
test suite), and the repo harnesses (`scripts/seed/build_from_seed.sh`,
`scripts/stdlib/run_fixtures.sh`, `scripts/corpus/classify`,
`scripts/corpus/list_corpus_dirs.sh`).

**Spec:** this document.

---

## §1 Scope and boundaries

**In scope (v1):**
- Single-file torrents only. (Multiple concurrent downloads = run multiple
  `z9torr` processes.)
- IPv4 only. Plaintext HTTP/1.1 tracker announces. `compact=1` peer lists only.
- Download only (leech). No seeding/upload serving.
- DHT, PEX, µTP, magnet links, encryption, TLS: out.
- Cross-restart resume of completed pieces **and** partial in-flight pieces.

**Target tiers:** Linux (host) for T1/T2; Win9x via mingw+Wine smoke (T4) and
a documented manual Win98 procedure (T5). Only T1/T2 are gating in v1 plans.

**Operator rulings recorded (binding):**
1. **Hybrid std/app split** — primitive/essential in std, custom/specific in
   the example.
2. **HTTP/1.1, no TLS.** Browsers and trackers aside, BitTorrent trackers do
   not require TLS; TLS is explicitly excluded.
3. **Chunked transfer-encoding and keep-alive are deferred** in `std_http`,
   and the deferral must be **noted in the lib** (module header comment +
   this spec). v1 requires `Content-Length` or a close-delimited body.
4. **Resume is core**, not deferred: write-through blocks, verify-on-complete,
   re-hash on start, and a fastresume sidecar for partial pieces.
5. **Single-file only**; multi-file layout (blueprint Stage 8) is dropped.
6. Test infrastructure lives **inside** `examples/z98/z9torr/` (repo
   convention), not a repo-root `tests/` tree; the blueprint's `make`
   tiers are delivered as `tests/*.sh`.
7. One spec + **milestone plans** (§11).

## §2 Blueprint → Z98 reality (adaptations)

| Blueprint | Reality / adaptation |
|---|---|
| Stage 2 writes a SHA-1 with streaming API | **Already exists**: `sf/src/std_crypto.zig` `sha1Init/sha1Update/sha1Final` (RFC-3174 GREEN fixtures). Stage 2 becomes "SHA-1 cross-check only". |
| `std.bencode` | Does not exist → **new** `sf/src/std_bencode.zig`. |
| `std.http.get` | Does not exist → **new** `sf/src/std_http.zig`. |
| `std.net.resolve` | Does not exist → **new** `std_net.resolve`. |
| `std.fs` | Does not exist → use `sf/src/std_file.zig` (`File`, `open/read/write/seek/size/readAll/writeAll`). |
| `std.hash` | Does not exist → `std_map.mix32`/`hashBytes` (FNV-1a) if a hash is needed. |
| `gethostbyname`, `getsockopt`, `shutdown`, arbitrary-IP connect | Absent → **new** `std_net` primitives (§4.1). |
| `tests/` tree, `make tierN` | Relocate into `examples/z98/z9torr/tests/*.sh` + `tools/` (§10). |
| Stage 8 multi-file | **Dropped** (single-file only). |
| `usize` assumed 64-bit | Z98 `usize` is 32-bit; file sizes/offsets are `u64`. |
| `std.fmt` float `{d}` | `std_fmt.printF64` exists via the compiler `print` path; `std_parse.ftoa` also exists. Use integer/decimal math for the stats line if needed. |

## §3 Architecture

```
                   +----------------------- examples/z98/z9torr ------------------------+
 stdin/uid  -->  main.zig --> cli.zig --> torrent.zig --> tracker.zig --> peer.zig
                   |                          |                 |             |
                   |                          |                 |             +--> piece.zig
                   |                          |                 |             |       |
                   |                          |                 +--> wire.zig  |       v
                   |                          |                               +--> disk.zig
                   |                          |                                       |
                   |                          +--> resume.zig                 scheduler.zig
                   |                                  |                        ratelimit.zig
                   |                                  v                        stats.zig
                   +---- consumes std_crypto.sha1, std_bencode, std_http, std_net,
                         std_async/std_stream, std_file, std_arena, std_buf, std_parse
                                                                     +-- tools/{mock_tracker,mock_peer}.zig, ref_check.c
```

Data flow: `cli` parses args → `torrent.load` parses metadata and computes
`info_hash` → `resume` reconstructs completed state from the output file +
sidecar → `tracker.announce` (via `std_http`) yields compact peers →
`scheduler`/`peer` connect and drive `piece` (block pipeline) → `disk` writes
blocks through and reads back for SHA-1 verification → `stats` renders the UI.
`wire` owns the framing; `ratelimit` gates sends.

## §4 Std-lib additions

All three follow the std-lib extension conventions (R1–R8 of
`2026-09-17-std-lib-extension-program-design.md` §5): every allocating
function takes `arena: *std.arena.Arena` first; one named error set per
module; new modules are **imported by path** (`@import("std_bencode.zig")`),
not added to the `std.zig` re-export set; each public function gets an R7
fixture under `repro/mi_matrix/stdlib_<module>_<name>_xmod/` with committed
`expected.txt` + `expected.rc`, and the dir is added to
`scripts/stdlib/expected_dirs.txt`. Adding a module also requires appending it
to the `lib/` copy lists in `scripts/seed/build_from_seed.sh` and
`scripts/seed/archive_seed.sh`, and to the `docs/sf/QUICK_REF.md` inventory —
**in the same commit**. None of this touches the compiler's `@import` closure,
so the compiler fixed point must remain **unmoved** (STOP if it moves).

### §4.1 `std_net` additions (`sf/src/std_net.zig`)

Primitive Winsock/POSIX socket calls missing today. `NetError` and `Socket`
already exist.

```zig
// gethostbyname behind a Z98 API. Returns IPv4 in NETWORK byte order
// (ready for sockaddr_in.sin_addr). IPv4 only.
pub fn resolve(host: []const u8) NetError!u32;

// A fresh TCP socket (AF_INET, SOCK_STREAM, IPPROTO_TCP).
pub fn tcpSocket() NetError!Socket;

// Non-blocking connect to an arbitrary IPv4 (NETWORK byte order) + port:
// set non-blocking, connect, select-write up to timeout_ms, then
// getsockopt(SO_ERROR). Replaces the loopback-only `connect`.
pub fn connectToIp(s: Socket, ip_be: u32, port: u16, timeout_ms: u32) NetError!void;

// getsockopt(SOL_SOCKET, SO_ERROR) as a normalized NetError!void.
pub fn checkSoError(s: Socket) NetError!void;

// shutdown(fd, how): how 0=recv, 1=send, 2=both.
pub fn shutdown(s: Socket, how: i32) void;
```

Notes: `resolve` copies the address out of `hostent.h_addr_list[0]` before any
other call (the structure is static); `connectToIp` handles
`WSAEWOULDBLOCK`/`EINPROGRESS`; `checkSoError` accounts for zeroed
SO_ERROR on success. The existing private `mapErr`/`lastErr` helpers are
reused so all error normalization stays in one place.

### §4.2 `std_bencode` (`sf/src/std_bencode.zig`, new)

```zig
pub const Value = union(enum) {
    int_val: i64,   // spelled `int_val`, not `int`: Z98 emits union tags verbatim as C members and `int` is a C keyword
    bytes: []const u8,
    list: []Value,
    dict: []Entry,
};
pub const Entry = struct { key: []const u8, value: Value };
pub const Span = struct { start: u32, end: u32 };   // byte offsets into the input

pub const BencodeError = error{
    InvalidToken, Overflow, TooDeep, TooLarge, DuplicateKey, OutOfMemory,
};

// Parse a complete bencoded value (must consume the whole input).
pub fn decode(arena: *std.arena.Arena, bytes: []const u8) BencodeError!Value;

// Serialize (canonical: keys emitted in insertion order as stored).
pub fn encode(arena: *std.arena.Arena, value: Value) BencodeError![]u8;

// Raw byte span of a top-level dict value, WITHOUT decoding it — used to
// capture the exact `info` bytes for info_hash. Walks only the top-level
// dict; `?` if the key is absent.
pub fn dictValueSpan(bytes: []const u8, key: []const u8) BencodeError!?Span;
```

Limits (from the blueprint): max nesting depth 100; max 1024 keys per dict;
max 32 MB per value; max 64 MB total input. Reject `i04e`, `i-0e`, leading
zeros, integer overflow of `i64`, and **duplicate keys** (a duplicate `info`
key yields two valid info_hashes — a real attack). `decode` checks string
lengths against remaining input before allocating, and rejects a trailing
byte after the top-level value. `dictValueSpan` must not allocate.

### §4.3 `std_http` (`sf/src/std_http.zig`, new)

**HTTP/1.1, no TLS.** Module header MUST carry a `DEFERRED` note (operator
ruling 3): chunked transfer-encoding and keep-alive are not implemented; v1
requires `Content-Length` or a close-delimited body.

```zig
pub const Url = struct { host: []const u8, port: u16, path: []const u8, query: []const u8 };
pub const Header = struct { name: []const u8, value: []const u8 };
pub const Response = struct { status: u16, headers: []Header, body: []u8 };

pub const HttpError = error{
    BadUrl, DnsFailed, ConnectFailed, Timeout, BadResponse, TooLarge, OutOfMemory,
};

pub fn parseUrl(url: []const u8) HttpError!Url;
pub fn percentEncode(arena: *std.arena.Arena, bytes: []const u8) HttpError![]u8;
// Pure: parse a full raw response (status line + headers + body) from memory.
pub fn parseResponse(arena: *std.arena.Arena, raw: []const u8) HttpError!Response;
// Network: resolve + connect + send GET + receive + parseResponse.
pub fn get(arena: *std.arena.Arena, url: []const u8, timeout_ms: u32) HttpError!Response;
```

Contract: send origin-form `GET <path>[?query] HTTP/1.1`, mandatory `Host`,
`Connection: close`. Parse the status line + case-insensitive headers; honor
`Content-Length`, else read to EOF. Follow one redirect (301/302/303/307) then
fail. Caps: header block 8 KB, body 1 MB. `Transfer-Encoding: chunked` is
rejected with `BadResponse` (deferred). `percentEncode` encodes every byte
outside `[A-Za-z0-9._~-]` as `%XX` — required for the raw-byte `info_hash`
and `peer_id` in the announce query. `parseResponse` is the pure seam the
fixtures drive; `get` is proven end-to-end in M2 against `mock_tracker`.

## §5 Example module layout

`examples/z98/z9torr/`:

| File | Responsibility | Key public surface |
|---|---|---|
| `main.zig` | Entry: parse args, parse torrent, resume, announce, download, print, exit | `pub fn main() void` |
| `cli.zig` | argv parsing, usage, exit-code mapping | `Args`, `parseArgs`, `usage`, `exitCodeFor` |
| `torrent.zig` | `.torrent` → `Torrent`; info_hash | `load(arena, bytes) !Torrent` |
| `tracker.zig` | announce query + response → peers | `announce(arena, t, peer_id, port, stats) !AnnounceResult` |
| `wire.zig` | handshake + message read/write, BE helpers | `readHandshake`, `writeHandshake`, `readMessage`, `writeMessage` |
| `peer.zig` | one peer's connection state machine | `peerRun(ctx, peer) !void` |
| `piece.zig` | block/piece state, pipeline, verify | `PieceState`, `RequestQueue`, `onBlock`, `nextRequests` |
| `disk.zig` | single-file write-through + read-back | `openTarget`, `writeBlock`, `readPiece` |
| `resume.zig` | sidecar load/save/validate + re-hash | `loadResume`, `saveResume`, `rehash` |
| `scheduler.zig` | rarest-first selection, claims, slot reuse | `Scheduler`, `pickPiece`, `claim`, `release` |
| `ratelimit.zig` | token bucket | `TokenBucket`, `take`, `refill` |
| `stats.zig` | counters + 1 Hz display | `Stats`, `render` |
| `tools/mock_tracker.zig` | listen :6969, fixed/parameterized response | `--fixture <file> --port <n>` |
| `tools/mock_peer.zig` | listen :6970, seed a fixture, `--mode` | `normal/choke-after-n/disconnect-after-n/bad-bitfield-length/wrong-info-hash` |
| `tools/ref_check.c` | C89 reference bencode + SHA-1 + info_hash | `ref_check --infohash <file>` / `--bdecode <file>` |
| `tests/*.sh` | tier drivers | `tier1.sh`, `tier2.sh`, `mkfixture.sh` |
| `testdata/` | fixtures + `expected/` (hashes) | `t1_single_1m.torrent`, `t2_single_25m.torrent`, `t5_unicode_name.torrent` |
| `demo/` | runtime goldens (md5) | `README.md` |
| `NOTES.md`, `README.md` | repo conventions | — |

Z98 rules apply throughout: no method syntax (free functions taking `self`),
no generics/`anytype`, strict `@intCast` at `i32`/`usize` boundaries, `switch`
needs `else`, string literals via `var s: []const u8 = "...";`.

## §6 Core data structures

```zig
const Args = struct { torrent_path: []const u8, max_peers: u32, max_up: u32, max_down: u32 };

const Torrent = struct {
    announce: []const u8,
    announce_list: [8][]const u8,      // fixed cap; up to 8 flattened tier URLs, extras dropped (D2-safe)
    announce_count: u32,               // entries actually stored in announce_list
    info_hash: [20]u8,
    name: []const u8,                 // pass-through bytes; sanitized for disk
    piece_length: u32,
    piece_hashes: []const u8,          // flat: concatenated SHA-1s, 20 bytes/piece (amended 2026-10-08 — see note)
    total_length: u64,
};

const PeerId = [20]u8;                                  // "-Z9T01-" + 12 seeded bytes
const PeerAddr = struct { ip_be: u32, port: u16 };      // network-order ip
const AnnounceResult = struct {
    interval: u32, min_interval: u32,
    peers: []PeerAddr,
    complete: u32, incomplete: u32,
    tracker_id: ?[]const u8,
};

const Handshake = struct {
    pstr: [19]u8, reserved: [8]u8, info_hash: [20]u8, peer_id: [20]u8,
};
const MsgType = enum(u8) { choke=0, unchoke=1, interested=2, not_interested=3,
                           have=4, bitfield=5, request=6, piece=7, cancel=8 };
const Message = struct { id: MsgType, payload: []const u8, is_keep_alive: bool };

const BlockState = enum(u8) { missing, requested, received, verified, failed };
const PieceState = struct {
    index: u32, state: BlockState,
    blocks: []BlockState, received_bytes: u32, hash: [20]u8,
};
const Request = struct { index: u32, begin: u32, length: u32 };
const RequestQueue = struct { in_flight: [4]Request, head: u32, tail: u32 };

const Peer = struct {
    addr: PeerAddr, sock: std.net.Socket, peer_id: [20]u8,
    am_choking: bool, am_interested: bool, peer_choking: bool, peer_interested: bool,
    bitfield: []u8, request_queue: RequestQueue,
    read_buf: [65536]u8, read_state: ReadState,
    last_recv_ms: u32, last_send_ms: u32, down_bytes: u64, up_bytes: u64,
};
const Scheduler = struct {
    piece_state: []PieceState, piece_rarest: []u32,
    peers: []Peer, active_peer_count: u32,
};
const TokenBucket = struct { tokens: u32, capacity: u32, rate: u32, last_refill_ms: u32 };
const Stats = struct { downloaded: u64, uploaded: u64, left: u64, peer_count: u32,
                       down_rate: u32, up_rate: u32, started_ms: u32,
                       window_down: [5]u32, window_up: [5]u32, window_idx: u32 };
```

> **Amendment — M1 Task 2 / M1a (2026-10-08):** `piece_hashes` is a **flat**
> `[]const u8` (concatenated SHA-1s, 20 bytes per piece; `piece_hashes.len ==
> 20 * piece_count`) rather than `[][20]u8`, and `announce_list` is the fixed
> `[8][]const u8` + `announce_count: u32` rather than `[][]const u8`. Reason:
> Z98 compiler defect **D2** (`examples/torrent_example_defects.md`) — a slice
> `[]T` emits its element's C name from the element's `name_id`, which is `0`
> for every *synthetic* type (slice/array/pointer/optional/tuple), so two
> different `[]synthetic` types collapse to one C typedef. **Rule:** a Z98
> slice `[]T` is safe only when `T` is a primitive or a *named* type
> (struct/union/enum); never `[]` a synthetic type — use flat bytes, a fixed
> `info_hash` semantics are unchanged.
>
> **Amendment — M2 Task 1 (2026-10-08):** the per-peer message buffer is **65536 bytes**
> (`read_buf: [65536]u8`), not 16384 — a `piece` message carrying a full 16 KB block has a
> 16393-byte body, which exceeds 16384 (`std_stream.MsgReader` returns `FrameTooLarge`
> when the declared length exceeds `buf.len`). Separately, `Message` gains an explicit
> `is_keep_alive: bool`; a BitTorrent keep-alive is a length-0 frame with no id, so
> `MsgType` remains the spec's 0..8 and is **not** extended.
>
> **Amendment — M3 (2026-10-08):** multi-peer scheduling requires per-peer runtime
> state to live in `Peer` (or a per-peer ctx) — the M2 single-peer code kept
> coroutine-live scratch at file scope (`peer.zig` globals `g_ps`/`g_io`/`g_hs`/
> `g_rhs`), which cannot be shared across N concurrent peers; M3 moves it into
> `Peer`. `Peer` therefore carries `bitfield: []u8` + per-peer request tracking
> (as listed in §6) and the peer loop handles `have` (updating `piece_rarest`) as
> well as `bitfield`. Plan-level types `AnnounceEvent = enum(u8){none,started,
> completed}` (M2 Task 2) and `RunCtx` (M2 Task 4) remain; `RunCtx` is generalized
> per peer with a shared `Scheduler`/driver.

## §7 Resume

Single-file only, so resume is one output file plus a small sidecar.

- **Disk policy (write-through):** on each received 16 KB block, `seek` to
  `piece_index*piece_length + block_begin` in the target file and write it
  immediately.
- **Verify-on-complete:** when all blocks of a piece are present, read the
  piece back, `sha1Init/sha1Update/sha1Final`, compare to the 20-byte slice
  `piece_hashes[i*20 .. i*20+20]`;
  match → `verified`; mismatch → `missing` (re-request) and drop the region.
- **Re-hash on start:** if the target file exists and its size equals
  `total_length`, SHA-1 each piece region and mark matches `verified`. This is
  the always-available fallback and needs no sidecar.
- **Fastresume sidecar `.z9torr.resume`** (bencode-encoded using
  `std_bencode`): `{ info_hash, total_length, mtime, completed_bits,
  `partial: [ { index, block_mask } ] }`. Written after each verified piece,
  whenever a block is written to a still-incomplete (partial) piece, and on
  clean completion (so the recorded `mtime` stays current and the partial
  `block_mask` is durable across a restart). On load it is trusted only if `info_hash`,
  `total_length`, and the output file's mtime all match; otherwise the re-hash
  result is used. This is what resumes a **half-downloaded piece** across a
  restart (the block mask says which 16 KB blocks are already on disk).
  The mtime is read via a `std_file` file-mtime capability added in M2
  (operator amendment lift, 2026-10-08; see the M2 plan).

- **Multi-peer corruption/retry (M3, 2026-10-08):** a piece that fails SHA-1
  (`Corrupt`), or is lost when its claiming peer disconnects, returns to
  `missing` (written-through blocks retained) and is re-requested — normally
  from a different peer. The run exits **4** only when no usable peer remains
  and pieces are still missing (spec §8). `Scheduler.release(peer)` returns that
  peer's claimed pieces to `missing` **without dropping their `block_mask`**, so
  the resume sidecar's `partial[]` survives claim/release.

## §8 Errors and exit codes

Per-module error sets (blueprint §3, kept): `BencodeError` (std),
`TorrentError`, `HttpError` (std), `TrackerError`, `PeerError`, `DiskError`,
`NetError` (std). `main` maps the first failure to an exit code:

```
0 = success (download complete and verified)
1 = usage error
2 = torrent parse / file error
3 = tracker/network error
4 = peer error (all peers failed) or hash failure that exhausted retries
5 = disk error
```

The user sees one human-readable line; detail goes to stderr under
`--verbose`.

## §9 Memory and determinism

- One `torrent_arena` (never reset), one `peer_arena` (reset when all peers
  disconnect), one `piece_arena` (per piece group). All std calls take the
  arena first.
- Peak budget: the example's own arenas must stay well under the 16 MB target;
  measured with `zig1 --markers --track-memory` (note: `--track-memory`
  requires `--markers`). A tier1/tier2 check records peaks.
- **`.torrent` metadata cap (M1a, 2026-10-08):** the metadata file is capped at
  `MAX_TORRENT_BYTES ≈ 3 MiB` (`3145728`; spec §9 arena-bound — the load arena
  is 4 MiB) and rejected with a distinct `z9torr: torrent too large` (exit 2)
  *before* `readAll`. `MAX_PIECES = MAX_TORRENT_BYTES / 20` follows from it. The
  **downloaded payload is unbounded** (`total_length`, streamed to disk), so
  this cap constrains only the small `.torrent` metadata, never the content.
- Determinism: `Z9TORR_SEED` (env) seeds the PRNG and therefore `peer_id` and
  `--mode` mock behaviour, so tests can assert exact wire bytes. Production
  seeds from `std.time.ticksMs` + pid.
- **Scheduler determinism (M3, 2026-10-08):** rarest-first ties break by **lowest piece index**, and eligible pieces are scanned in ascending index order, so a seeded run's request order is reproducible. `piece_rarest[i]` is updated on `bitfield`/`have`/disconnect in a fixed order.
- **Rate limits (M3 clarification, 2026-10-08):** the client is download-only (spec §13), so `--max-down` bounds received `piece` payloads via the global bucket; `--max-up` bounds only `request` bytes sent (handshake/`interested`/keep-alive are not rate-limited; there is no peer upload). `0` means unlimited.

## §10 Test infrastructure (repository conventions)

Everything lives under `examples/z98/z9torr/`. Adding `main.zig` makes the
example auto-join `scripts/corpus/list_corpus_dirs.sh`. (Doc-count updates in
`README.md:39,257` and the `docs/sf/QUICK_REF.md` baselines are optional
hygiene, not a gate.)

- **Fixtures/goldens:** `testdata/` holds deterministically generated torrents
  and their expected SHA-1 + info_hash text (committed; regenerating requires
  `tests/mkfixture.sh`, which the suite does not run). Text files require
  `git add -f` (`*.txt` is gitignored).
- **Reference checker:** `tools/ref_check.c` (C89) computes bencode decode,
  SHA-1, and info_hash; tier1 diffs its output against the Z98 result for the
  same input. The comparison is in `sh`, not in either implementation.
- **Mocks:** `tools/mock_tracker.zig` and `tools/mock_peer.zig` are separate
  Z98 binaries (not linked into the client) — the same socket/framing code
  paths, in reverse. They bind fixed ports declared in `testdata/ports.txt`
  and the tier scripts start them backgrounded with a `timeout` guard.
- **tier1.sh:** CLI shapes, bencode/torrent-parse round-trips vs `ref_check`,
  malformed inputs (typed error, no crash/loop).
- **tier2.sh:** start `mock_tracker` + `mock_peer`; download `t1` (1 MB) and
  `t2` (25 MB); verify the output file's SHA-1; run the **interrupt-and-restart
  resume** test (kill mid-download, re-run, confirm it finishes and both the
  completed pieces and the partial piece were reused — asserted via the
  client's own progress output and total bytes fetched).
- **Gates (per plan; operator amendment 2026-10-08; amended for the M2/M4 std
  lifts):** the **compiler** is not modified, so compiler-only gates (fixed
  point, dump-MD5, corpus classify) are intentionally not run. Std-lib changes
  ARE authorized in M2 (`std_file` file mtime) and M4 (64-bit file seek)
  (amendment lift, 2026-10-08) — those keep `scripts/stdlib/verify_stdlib.sh`
  green (M0 baseline 280 PASS). M1–M4's measure is the example's own
  `tests/tier1.sh` (parse/ref_check), `tests/tier2.sh` (download + resume), and
  `tests/tier4_wine.sh` (Wine smoke).

## §11 Milestones and plan index

| Milestone | Plan | Deliverable |
|---|---|---|
| **M0 — std prerequisites** | `docs/superpowers/plans/2026-10-08-z9torr-m0-std-prerequisites-plan.md` | `std_net` primitives + `std_bencode` + `std_http`, each with R7 fixtures, copy-list/QUICK_REF updates; measured by `verify_stdlib`. |
| **M1 — core (pure)** | `docs/superpowers/plans/2026-10-08-z9torr-m1-core-plan.md` | Example skeleton + CLI + torrent parse + testdata/ref_check/tier1; `z9torr <file>` reports torrent metadata. |
| **M2 — single-peer download + resume** | `docs/superpowers/plans/2026-10-08-z9torr-m2-single-peer-download-plan.md` | Protocol modules + mock peer/tracker + tier2; downloads a single-file torrent end-to-end with cross-restart resume. |
| **M3 — multi-peer** | `docs/superpowers/plans/2026-10-08-z9torr-m3-multi-peer-plan.md` | Rarest-first scheduler over N peers, rate limits, stats display. |
| **M4 — real-swarm compatibility** | `docs/superpowers/plans/2026-10-09-z9torr-m4-real-swarm-compat-plan.md` | MSE/PE encryption + UDP tracker (BEP 15) + DHT/PEX; `peer_id` fix; real-swarm best-effort. |
| **M5 — Win9x cross** | `docs/superpowers/plans/2026-10-08-z9torr-m5-win9x-plan.md` | mingw/Wine smoke via `scripts/win32_cross/`; documented Win98 procedure (was M4). |

Sequence: M0 → M1 → M2 → M3 → M4 → M5. M1 has no socket dependency; M2 depends on
M0's `std_http`/`std_net`/`std_bencode` and M1's `torrent.zig`. Each plan's
header names its predecessor/successor.

## §12 Risks and open items

1. **`std_async` + `std_stream` integration (blueprint Open Q1).** Already
   solved: `std_stream.SocketLineReader`/`MsgReader` + `std_async.suspendUntil`
   landed in the std-lib Plan D. M2 reuses them; if a peer coroutine's frame
   size is too large, keep state in `Peer` rather than coroutine locals.
2. **`std_net` non-blocking connect on Win9x** is inconsistent; `checkSoError`
   is mandatory after `select` reports writable (M4 verifies under Wine).
3. **`std.fmt` float formatting** for the stats line is limited; use integer
   arithmetic with a manual decimal point, or `std_parse.ftoa`.
4. **`@ptrCast` of `[]u8` → `[*]u8`** in the piece buffer: verify emission and
   that no bounds check is lost (pinned by a fixture if needed).
5. **Win9x `select` FD_SETSIZE (64).** 30 peers + listen + tracker < 40; fine,
   confirmed in M4.
6. **`std_http` `get` needs a live server** for a fixture; M0 fixtures drive
   the pure `parseUrl`/`percentEncode`/`parseResponse` seam and the full path
   is proven in M2.
7. **Large payloads (> 2 GiB) on the Linux host.** `std_file.seekHandle`
   rejects POSIX offsets > 2 GiB (`sf/src/std_file.zig:158-160`); write-through
   for a > 2 GiB payload fails on T1/T2 (Windows uses `SetFilePointerEx`, OK).
   M2's tests are ≤ 25 MB; **M4 is amended to add 64-bit file offsets**
   (operator amendment lift, 2026-10-08).
8. **Multi-peer slot reuse + address dedupe (M3).** A freed `Peer` slot is
   reused; a small ring of recently-seen `PeerAddr`s skips duplicate
   connections. This is behavior beyond the §6 `Scheduler` fields (detailed in
   the M3 plan).
9. **`tier1.sh` port hermeticity.** M1's `tier1` assumes `127.0.0.1:6969` is
   closed (it expects a tracker-failure exit 3); a leftover tracker yields exit
   4. M3's `tier2` guards its ports; either harden `tier1` the same way or
   document the dependency.

## §13 Out of scope

Multi-file torrents; seeding/upload; DHT/PEX/magnet/µTP; encryption/TLS; IPv6;
resume of a piece across a *different* torrent; a GUI. The blueprint's
`tests/` tree and `make tierN` targets are replaced by `tests/*.sh` per repo
convention.
