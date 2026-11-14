# z9torr M2 — single-peer download + resume — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Download a single-file torrent end-to-end from one peer (via a Z98 mock tracker + mock peer), verify every piece by SHA-1, and **resume across a restart** — completed pieces reused from disk, a half-downloaded piece resumed from the fastresume sidecar.

**Architecture:** Add the wire, tracker, disk, resume, and peer/piece modules. `std_http` (M0) performs the tracker GET; `std_stream.MsgReader`/`std_net` read the peer socket; `std_crypto.sha1` verifies pieces; `std_bencode` serializes the resume sidecar. The peer runs as a coroutine yielded once per socket read/write under `std.async`.

**Tech Stack:** Z98 (`zig1`), C89, `gcc -m32`, `std_http`, `std_net`, `std_stream`, `std_async`, `std_crypto`, `std_bencode`, `std_file`, POSIX `sh`.

**Spec:** `docs/superpowers/specs/2026-10-08-z9torr-bittorrent-client-design.md` (binding; §3, §4.3, §6, §7, §8, §10).

**Sequence:** PREVIOUS: `docs/superpowers/plans/2026-10-08-z9torr-m1-core-plan.md`. NEXT: `docs/superpowers/plans/2026-10-08-z9torr-m3-multi-peer-plan.md`.

## Global Constraints

- **Depends on M0 + M1.** `std_http`/`std_net` additions and `torrent.load` must exist.
- **Wire endianness (binding).** Every multi-byte wire integer is big-endian. Provide `readU32BE`/`writeU32BE`/`readU16BE`/`writeU16BE` once (in `wire.zig`) and use them everywhere. Message length prefix and `have`/`request`/`piece`/`cancel` payloads are BE (spec/blueprint §3).
- **Message caps (binding).** Max message 64 KB; per-peer read buffer 64 KB (`read_buf: [65536]u8`; a 16 KB block `piece` body is 16393 bytes). A length prefix > 64 KB is a protocol error.
- **Message/keep-alive + buffer (operator ruling, M2 Task 1).** The per-peer message buffer is 64 KB (not 16 KB). Keep-alive is represented by `Message.is_keep_alive` (a length-0 frame with no id); `MsgType` stays the spec's 0..8 (no `keep_alive` member). `wire.zig` exposes both `readMessage` and `readMessageAsync` (the latter uses `std_stream.readMsgAsync` for the Task 4 coroutine).
- **RESUME (binding).** Write-through blocks + verify-on-complete + re-hash on start + `.z9torr.resume` sidecar. A restart must not re-fetch verified pieces, and must resume a partially-received piece (spec §7).
- **Build recipe / gitignore / edit rules / no-push / no-compression** as M1. **No compiler gate:** the compiler is untouched; gates are the example's own tier tests, not the fixed point / dump-MD5 / corpus classify.
- **Amendment lift — std change authorized (operator ruling, 2026-10-08).** The M0–M4 "example-only" restriction is lifted for **`sf/src/std_file.zig` + `sf/src/std_file_pal.zig`**: M2 adds a **file modification-time** capability (e.g. `pub fn mtime(path: []const u8) FileError!i64`; POSIX via `stat`/`fstat`, Windows via `GetFileAttributesExA`) so the resume sidecar's mtime validation (spec §7) is implementable. The compiler fixed point is still untouched, but because **std** changes, `scripts/stdlib/verify_stdlib.sh` MUST stay green — add a `repro/mi_matrix` fixture for the new capability and register it exactly as M0 did (`scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh`, `docs/sf/QUICK_REF.md`, `scripts/stdlib/expected_dirs.txt`).
- **Fixtures point at the mock tracker (operator ruling, 2026-10-08).** `tests/mkfixture.sh` now writes `announce='http://127.0.0.1:6969/announce'`, and the committed `testdata/*.torrent` were regenerated with it. `announce` is outside the `info` dict, so `expected/*.{sha1,infohash}` are **unchanged** (verified).
- **P3 (recorded; fixed in M5).** `std_file.seekHandle` rejects POSIX offsets > 2 GiB (`sf/src/std_file.zig:158-160`), so payloads > 2 GiB fail on the Linux host. M2's tests are ≤ 25 MB and unaffected; M5 is amended to add 64-bit file offsets.
- Reports under `.superpowers/sdd/2026-10-08-z9torr-m2-single-peer-download-plan/`.
- Z98 rules: no method syntax; no generics; strict `@intCast`; `switch` needs `else`; string literals via `var s: []const u8 = "x";`.

## File Structure

- Create: `examples/z98/z9torr/{wire.zig,tracker.zig,disk.zig,resume.zig,peer.zig,piece.zig}`
- Create: `examples/z98/z9torr/tools/{mock_tracker.zig,mock_peer.zig}`
- Create: `examples/z98/z9torr/tests/tier2.sh`
- Modify: `examples/z98/z9torr/main.zig`

---

### Task 0: Mock tracker + mock peer

**Files:**
- Create: `examples/z98/z9torr/tools/mock_tracker.zig`, `examples/z98/z9torr/tools/mock_peer.zig`
- Create: `examples/z98/z9torr/testdata/ports.txt`

**Interfaces:**
- Produces: `mock_tracker` listening on a fixed port (default 6969) returning a fixed bencoded announce response whose compact peer list points at `mock_peer`; `mock_peer` listening on a fixed port (default 6970) seeding a single-file fixture with `--mode normal|choke-after-n|disconnect-after-n|bad-bitfield-length|wrong-info-hash`.

- [ ] **Step 1: `mock_tracker.zig`.** A `std_net` TCP server (`createTcpServer`+`bindListen`+`accept`); read until `\r\n\r\n`; write `HTTP/1.1 200 OK\r\nContent-Length: <n>\r\nConnection: close\r\n\r\n<benbody>` where `<benbody>` is `d8:intervali1800e5:peers6:<ip><port>e` (compact, one peer) or read from `--response <file>`. Flags: `--port <n>`, `--peer <ip:port>`.
- [ ] **Step 2: `mock_peer.zig`.** Accept one connection; read the 68-byte handshake; if `--mode wrong-info-hash`, send a handshake with a mutated info_hash and close. Else send the handshake, then a `bitfield` with all bits set (`ceil(n_pieces/8)` bytes, spare bits `1`), then loop: on `request{index,begin,length}` read the corresponding bytes from the fixture file and send `piece{index,begin,bytes}`. Modes `choke-after-n`/`disconnect-after-n` close after N messages; `bad-bitfield-length` sends a wrong-length bitfield. Flags: `--port`, `--file <path>`, `--piece-length <n>`, `--mode`, `--seed` (via `Z9TORR_SEED` for determinism).
- [ ] **Step 3: Smoke-test both** against each other using a tiny Z98 or shell client and `std.net` (or verify via the M2 client in Task 4). Record ports in `testdata/ports.txt` (one per line).
- [ ] **Step 4: Commit.** `git add -f examples/z98/z9torr/tools examples/z98/z9torr/testdata/ports.txt && git commit -m "example(z9torr): add mock tracker + mock peer"`
- [ ] **Step 5: Report.** Ledger line.

---

### Task 1: Wire protocol (handshake + framing)

**Files:**
- Create: `examples/z98/z9torr/wire.zig`

**Interfaces:**
- Consumes: `std_net.send/recv`, `std_stream.MsgReader` (or raw BE reads).
- Produces: `Handshake = struct { pstr: [19]u8, reserved: [8]u8, info_hash: [20]u8, peer_id: [20]u8 }`; `MsgType` (spec §6); `Message = struct { id: MsgType, payload: []const u8, is_keep_alive: bool }`; `pub fn readU32BE/writeU32BE/readU16BE/writeU16BE`; `pub fn writeHandshake(sock, hs) !void`; `pub fn readHandshake(sock, expected_info_hash: []const u8, out: *Handshake) PeerError!void`; `pub fn readHandshakeAsync(sock, expected_info_hash: []const u8, out: *Handshake) PeerError!void` (non-blocking; suspends on `WouldBlock`); `pub fn readMessage(mr: *MsgReader, out: *Message) PeerError!void`; `pub fn readMessageAsync(mr: *MsgReader, out: *Message) PeerError!void`; `pub fn writeRequest/writeInterested/...`; `pub fn writePiece`. `expected_info_hash` is `[]const u8` length-checked `==20` (a `[20]u8` by-value parameter is un-emittable across the coroutine frame; operator ruling R1=A, 2026-10-08).

- [ ] **Step 1: Implement BE helpers + `readHandshake`/`writeHandshake`.** `pstrlen` is the single byte 19; `pstr` == `"BitTorrent protocol"`; reject non-zero `reserved` (BEP 10 signalling); reject `info_hash` mismatch with `PeerError.InfoHashMismatch`.
- [ ] **Step 2: Implement message framing.** Use `std_stream.MsgReader` (`readMsgSync`) for the u32-BE length prefix + body; length 0 = keep-alive (no id); length > 64 KB = `PeerError.BadMessage`. Provide typed constructors/serializers for `interested`, `request`, `cancel`, and a `piece` writer.
- [ ] **Step 3: Prove with a unit harness** against `mock_peer` (or a loopback server in the same program) — handshake + one `request`/`piece` round-trip with a known 16 KB block; assert byte-exact BE fields.
- [ ] **Step 4: Commit.** `git commit -m "example(z9torr): add peer wire handshake + framing"`
- [ ] **Step 5: Report.** Ledger line.

---

### Task 2: Tracker announce

**Files:**
- Create: `examples/z98/z9torr/tracker.zig`

**Interfaces:**
- Consumes: `std_http.get`, `std_http.percentEncode`, `std_bencode.decode`.
- Produces: `PeerId = [20]u8`; `PeerAddr = struct { ip_be: u32, port: u16 }`; `AnnounceEvent = enum(u8) { none=0, started=1, completed=2 }`; `AnnounceResult` (spec §6); `TrackerError = error{ HttpFailed, BadResponse, FailureReason, OutOfMemory }`; `pub fn announce(arena, t: Torrent, peer_id: PeerId, port: u16, event: AnnounceEvent, stats: Stats) TrackerError!AnnounceResult`.

- [ ] **Step 1: Build the query string.** `info_hash=` + `percentEncode`(raw 20 bytes) + `&peer_id=` + `percentEncode` + `&port=` + `&uploaded=` + `&downloaded=` + `&left=` + `&compact=1` + `&event=` from the `event` parameter (`started` / `completed`; omit the field when `event == .none`). Percent-encoding of the raw bytes is mandatory.
- [ ] **Step 2: Call `std_http.get`** on `torrent.announce + "?" + query`; parse the bencoded body with `std_bencode.decode`; if a top-level `failure reason` key exists → `TrackerError.FailureReason` (with the string).
- [ ] **Step 3: Parse compact peers.** `peers` must be a `bytes` value of length `6*N`; split into `{ip_be, port}` pairs (network-order IP + big-endian port). `interval`/`min_interval`/`complete`/`incomplete` from the dict; `tracker id` optional.
- [ ] **Step 4: Verify against `mock_tracker`.** A tier-2 micro-test starts the mock, calls `announce`, asserts one peer parsed at the mock peer's address.
- [ ] **Step 5: Commit.** `git commit -m "example(z9torr): add tracker announce (HTTP + bencode + compact peers)"`
- [ ] **Step 6: Report.** Ledger line.

---

### Task 3: Disk + resume

**Files:**
- Create: `examples/z98/z9torr/disk.zig`, `examples/z98/z9torr/resume.zig`
- Modify: `examples/z98/z9torr/main.zig` (wire resume load after parse)
- Modify (std, amendment lift): `sf/src/std_file.zig`, `sf/src/std_file_pal.zig` — add the file-mtime capability
- Create/register: `repro/mi_matrix/stdlib_file_mtime_xmod` fixture + seed-script/`QUICK_REF.md`/`expected_dirs.txt` registration (M0 pattern)

**Interfaces:**
- Consumes: `std_file` (`open/read/write/seek/size`), `std_crypto.sha1`, `std_bencode.encode/decode`.
- Produces: `disk.openTarget(arena, t) !File`; `disk.writeBlock(f, t, piece_index, block_begin, bytes) !void`; `disk.readPiece(f, t, index, out: []u8) !usize`; `resume.load(arena, t, out_file) ResumeState`; `resume.rehash(arena, t, f, state) !void`; `resume.save(arena, t, state) !void`; `ResumeState = struct { completed_bits: []u8, partial: []PartialPiece }`.

- [ ] **Step 0: Add the file-mtime capability to `std_file` (amendment lift).**
  `pub fn mtime(path: []const u8) FileError!i64` (seconds since epoch; POSIX `stat`/`fstat`, Windows `GetFileAttributesExA`/`GetFileTime`), with the PAL extern(s) in `std_file_pal.zig`. Add a `repro/mi_matrix` fixture that writes a file and asserts its reported mtime (and the missing-file error), plus the seed-script/`QUICK_REF.md`/`expected_dirs.txt` registration. `bash scripts/stdlib/verify_stdlib.sh` → green including the new fixture. Compiler untouched.
- [ ] **Step 1: Implement `disk.zig` (single-file).**
  - `openTarget`: create/open `t.name` (sanitized) in the output dir; ensure size `t.total_length` (seek to end-1 + write a zero, portable to FAT). Reject a `name` that is a directory or reserved/illegal on Win9x (already sanitized in M1) with `DiskError`.
  - `writeBlock`: `seek(piece_index * piece_length + block_begin)` then write. `readPiece`: `seek(index*piece_length)` then read `min(piece_length, total_length - index*piece_length)` bytes.
- [ ] **Step 2: Implement `resume.zig`.**
  - `rehash`: for each piece index not already `verified`, `readPiece` + `sha1` + compare to `piece_hashes[i]`; set `completed_bits[i]`.
  - Sidecar `.z9torr.resume` (bencode): `d10:info_hash20:<20>12:total_lengthi<n>e5:mtimei<n>e13:completed_bits<n>:<bits>7:partiall(d5:indexi<i>e10:block_mask<n>:<mask>e)…ee`. `load`: decode + validate `info_hash` == `t.info_hash` and `total_length` == `t.total_length` and the output file mtime equals the recorded mtime; on any mismatch, discard and rely on `rehash`.
  - `save`: re-encode and write the whole sidecar (cheap; called after each verified piece and on completion).
- [ ] **Step 3: Prove resume in isolation.** A small tier-2 harness: create a sparse target + a sidecar marking pieces 0–1 complete, call `load`+`rehash`, assert pieces 0–1 `verified` and 2+ `missing`; mutate one byte of piece 0 → assert it is re-flagged missing.
- [ ] **Step 4: Commit.** `git commit -m "example(z9torr): add single-file disk write-through + resume sidecar"`
- [ ] **Step 5: Report.** Ledger line.

---

### Task 4: Peer + piece exchange (single peer)

**Files:**
- Create: `examples/z98/z9torr/piece.zig`, `examples/z98/z9torr/peer.zig`
- Modify: `examples/z98/z9torr/main.zig`

**Interfaces:**
- Consumes: `wire.zig`, `disk.zig`, `resume.zig`, `tracker.zig`, `std_async`, `std_net`.
- Produces: `PieceState`, `Request`, `RequestQueue` (spec §6); `pub fn pieceInit(arena, t, state, index) !void`; `pub fn nextRequests(state, out: *RequestQueue) void` (depth 4, 16 KB blocks, last block length `piece_len - (n-1)*16384`); `pub fn onBlock(state, begin, bytes) enum{ Continue, Complete, Corrupt }` (writes-through via `disk`, and on complete reads the piece back + SHA-1 verifies); `pub fn peerRun(ctx, peer) void` — coroutine (no error return; the `@async*` step signature requires it) that reports its outcome via a `RunCtx`; connect (`std_net.connectToIp`), handshake via `wire.readHandshakeAsync(sock, t.info_hash, &hs)`, read `bitfield`/`have`, send `interested`, wait `unchoke`, pump `nextRequests`/`onBlock` until the piece set is complete, yielding via `std.async` on `WouldBlock`.

- [ ] **Step 1: Implement `piece.zig`.** Block bookkeeping per spec; `onBlock` writes the block through `disk.writeBlock`, and when all blocks of a piece are present, `disk.readPiece` + SHA-1 → `Complete` or `Corrupt` (mark `failed`, re-queue, disconnect from this peer).
- [ ] **Step 2: Implement `peer.zig`** as a coroutine. Non-blocking socket (`std_net.setNonBlocking`); on `WouldBlock`, `@asyncSuspend(null)`. Enforce keep-alive send after 120 s idle and disconnect an idle peer.
- [ ] **Step 3: Wire `main.zig`:** parse → resume → announce `event=started` → run one peer coroutine under `std.async` until all pieces verified → on completion announce `event=completed` → print a final one-line summary + exit 0. **Exit codes per spec §8** (`0` success; `2` parse/file; `3` tracker/network; `4` peer/hash; `5` disk) — a tracker/announce failure exits **3**, never `0`.
- [ ] **Step 4: Manual download test** against `mock_peer` serving `t1_single_1m.torrent`; `sha1sum` the output file and compare to `expected/t1_single_1m.sha1`.
- [ ] **Step 5: Commit.** `git commit -m "example(z9torr): add single-peer piece exchange with verify + resume"`
- [ ] **Step 6: Report.** Ledger line.

---

### Task 4b: Partial-piece resume + malformed-peer rejection + fetch metric

**Files:**
- Modify: `examples/z98/z9torr/peer.zig`, `examples/z98/z9torr/resume.zig`, `examples/z98/z9torr/main.zig`

**Interfaces:**
- Produces: partial-piece resume (persist/consume the sidecar `partial[]` `block_mask`), `bitfield` length validation (`ceil(n_pieces/8)`, else reject the peer), and a one-line fetched-bytes/request summary on stdout.

- [ ] **Step 1: Malformed-peer rejection (operator ruling B1=A).** On a `bitfield` message, require payload length `== ceil(n_pieces/8)`; otherwise reject/drop that peer so the run exits 4.
- [ ] **Step 2: Partial-piece resume (operator ruling B2=A).** Persist each in-flight piece's received-block mask in the sidecar `partial[]`; on load, seed those blocks as already-received and skip them, so only the missing 16 KB blocks are requested. Keep the sidecar `mtime` current by saving whenever a partial-piece block is written (spec §7 cadence amended 2026-10-08).
- [ ] **Step 3: Fetch metric (operator ruling B3=A).** Print a one-line fetched-bytes/request summary at exit (from `peer.up_bytes`) so tier2 can assert a resumed run re-fetches strictly fewer bytes than a cold start.
- [ ] **Step 4: Prove.** `bad-bitfield-length` peer → exit 4; a killed-then-restarted `t2` resumes the partial piece and re-fetches strictly fewer bytes; cold `t1`/`t2` downloads still match the goldens; `tier1.sh` 15/0. Commit `git commit -m "example(z9torr): partial-piece resume + malformed-peer rejection + fetch metric"`.
- [ ] **Step 5: Report.** Ledger line.

---

### Task 5: tier2 + closeout

**Files:**
- Create: `examples/z98/z9torr/tests/tier2.sh`, `examples/z98/z9torr/demo/README.md`
- Modify: `examples/z98/z9torr/NOTES.md`
- Record: `.superpowers/sdd/2026-10-08-z9torr-m2-single-peer-download-plan/task-5-report.md`

- [ ] **Step 1: Write `tests/tier2.sh`:**
  1. Build `z9torr`, `mock_tracker`, `mock_peer` (binding recipe). Refuse to run if the declared ports are already listening (`ports.txt`).
  2. Start `mock_tracker` + `mock_peer --mode normal` backgrounded with `timeout` guards.
  3. Download `t1_single_1m`; assert exit 0 and `sha1sum <output>` == `expected/t1_single_1m.sha1`.
  4. Download `t2_single_25m`; assert exit 0 and matching SHA-1.
  5. **Resume test:** start a download of `t2`, kill the client mid-way (after ≥1 verified piece and with a partial piece in flight), re-run, assert exit 0, matching SHA-1, and that the restart re-fetched strictly fewer bytes than a cold start (read the client's progress output / peer request count).
  6. Malformed-peer cases: `--mode wrong-info-hash` (client rejects, exits 4), `--mode bad-bitfield-length` (rejected).
- [ ] **Step 2: Run tier2.sh; all PASS.**
- [ ] **Step 3: Write `demo/README.md`** with exact commands, fixture SHA-1s, and the resume evidence; record the `--dump-c89` md5 in `NOTES.md`.
- [ ] **Step 4: Gate (example-only).** `bash examples/z98/z9torr/tests/tier2.sh` → all PASS (download t1/t2 + interrupt-restart resume + malformed-peer). No compiler-only gates (fixed point / dump-MD5 / corpus classify) — the compiler is untouched.
- [ ] **Step 5: Commit + report.** Ledger line.
- [ ] **Step 6: Next plan.** State that M3 (`2026-10-08-z9torr-m3-multi-peer-plan.md`) is next.

## Self-Review

- **Spec coverage:** §3 wiring → Tasks 1/4; §4.3 `std_http` in tracker → Task 2; §6 structs → Tasks 1/3/4; §7 resume → Task 3 (+ tier2 resume test); §8 errors/exit codes → Tasks 1/2/4; §10 mocks/tier2 → Tasks 0/5.
- **Placeholder scan:** no TBDs; every module has named signatures; the resume test asserts reused pieces, not just completion.
- **Type consistency:** `Handshake`/`MsgType`/`Message`, `PeerAddr`/`AnnounceResult`, `PieceState`/`Request`/`RequestQueue`, `ResumeState` match the spec and M1's `Torrent`.
- **D2 rule (M1a amendment, 2026-10-08):** M1's `Torrent.announce_list` is the fixed `[8][]const u8` + `announce_count: u32` (extras dropped), never `[][]const u8`. A Z98 slice `[]T` is safe only when `T` is primitive or a *named* type (struct/union/enum); never `[]` a *synthetic* type (slice/array/pointer/optional/tuple). M2's `[]PeerAddr`, `[]PieceState`, `[]BlockState` are slices of named structs (safe) — M2 adds no `[]synthetic` type.
