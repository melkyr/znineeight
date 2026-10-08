# z9torr M0 — std prerequisites — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the three std-lib modules the z9torr client needs — `std_net` socket primitives, `std_bencode`, `std_http` — each with R7 fixtures and the required copy-list/doc updates, leaving the compiler fixed point **unmoved**.

**Architecture:** Each module is a new/edited `sf/src/std_*.zig` (never imported by the compiler, so no fixed-point movement) plus one or more `repro/mi_matrix/stdlib_<module>_<name>_xmod/` fixtures. Every module is registered in the two seed copy lists and the QUICK_REF inventory in the **same commit** that adds it, and each new fixture dir is added to `scripts/stdlib/expected_dirs.txt`.

**Tech Stack:** Z98 (`zig1`), C89 emission, `gcc -m32`, the seed-built `zig1_5_clean` + sibling `lib/`, `scripts/stdlib/run_fixtures.sh`, `scripts/corpus/classify`.

**Spec:** `docs/superpowers/specs/2026-10-08-z9torr-bittorrent-client-design.md` (binding; §4 defines the exact signatures).

**Sequence:** PREVIOUS: none. NEXT: `docs/superpowers/plans/2026-10-08-z9torr-m1-core-plan.md`.

## Global Constraints

- **Seed model.** At execution start, read the head of `release/seed/CHANGELOG.md` for the current seed and fixed point. Build the compiler-under-test with `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_m0_seed` **without** `FIXED_POINT_MD5`; the two-hop closure (`hop1 == hop2`) must hold. The result is `/tmp/z9_m0_seed/zig1_5_clean`; its sibling `lib/` is what fixture runs use.
- **Fixed point UNMOVED (binding).** The compiler imports zero std modules. If any std addition moves the self-compile fixed point, **STOP and present** — do not re-baseline.
- **Conventions.** std-lib R1–R8 (`2026-09-17-std-lib-extension-program-design.md` §5). Every allocating function takes `arena: *std.arena.Arena` first; one named error set per module; modules are imported by path, **not** added to `std.zig`.
- **Copy-list discipline.** Adding a module requires appending it to the `lib/` copy list in **both** `scripts/seed/build_from_seed.sh` (line ~145) and `scripts/seed/archive_seed.sh` (line ~115, and the doc comment ~28–35), and to the `docs/sf/QUICK_REF.md` inventory (~line 152) — same commit.
- **Fixture pin.** Every new `repro/mi_matrix/stdlib_*` dir must be added to `scripts/stdlib/expected_dirs.txt`, or `run_fixtures.sh` discovery mode FAILS.
- **Fixture harness (binding).** `bash scripts/stdlib/run_fixtures.sh /tmp/z9_m0_seed/zig1_5_clean <dir>` compiles `-ffast -o <tmp>`, then the binding gcc flag-set, then `sh build_target.sh linux`, runs 3× and diffs `expected.txt`/`expected.rc`. Capture goldens with `--capture`, then review against the fixture's GREEN contract before committing. Fixtures that bind a port declare it in `<dir>/ports.txt`.
- **Edits** via `edit`/`fastedit` only (AGENTS.md X.7: re-read the region before each edit; bottom-to-top; INSERT = replace the anchor line with [new content + original line]).
- **No push. Compression FORBIDDEN during the build session.** Reports under `.superpowers/sdd/2026-10-08-z9torr-m0-std-prerequisites-plan/`, committed with `git add -f`.
- Z98 rules: no method syntax; no generics; strict `@intCast`; `switch` needs `else`; string literals via `var s: []const u8 = "x";`.

## File Structure

- Create: `sf/src/std_bencode.zig`, `sf/src/std_http.zig`
- Modify: `sf/src/std_net.zig` (append primitives)
- Create: `repro/mi_matrix/stdlib_net_resolve_xmod/{main.zig,expected.txt,expected.rc}`, `stdlib_net_connectto_xmod/…`, `stdlib_net_soerror_xmod/…`, `stdlib_net_shutdown_xmod/…`
- Create: `repro/mi_matrix/stdlib_bencode_decode_xmod/…`, `stdlib_bencode_encode_xmod/…`, `stdlib_bencode_limits_xmod/…`, `stdlib_bencode_dictspan_xmod/…`, `stdlib_bencode_oom_xmod/…`
- Create: `repro/mi_matrix/stdlib_http_parseurl_xmod/…`, `stdlib_http_percentencode_xmod/…`, `stdlib_http_parseresponse_xmod/…`, `stdlib_http_parseresponse_chunked_reject_xmod/…`, `stdlib_http_badurl_xmod/…`
- Modify: `scripts/stdlib/expected_dirs.txt`, `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh`, `docs/sf/QUICK_REF.md`

---

### Task 0: Preflight and baseline

**Files:**
- Record: `.superpowers/sdd/2026-10-08-z9torr-m0-std-prerequisites-plan/task-0-report.md`

**Interfaces:**
- Produces: the baseline fixed point, `verify_stdlib` result, corpus classify baseline, and the 8 dump-MD5 pins for later tasks.

- [ ] **Step 1: Read the current seed.** Record `release/seed/CHANGELOG.md` head: seed version, HEAD, fixed point, archive md5.
- [ ] **Step 2: Build the compiler under test.**
  `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_m0_seed`
  Expected: `[seed] two-hop closure OK: hop1 == hop2 == <fixed point>` and `=== [seed] Done: /tmp/z9_m0_seed ===`.
- [ ] **Step 3: Record baselines.**
  `bash scripts/stdlib/verify_stdlib.sh /tmp/z9_m0_seed/zig1_5_clean` → expect `STDLIB GATE OK` and `<N> PASS / 0 FAIL`.
  `bash scripts/corpus/classify /tmp/z9_m0_seed/zig1_5_clean /tmp/z9_m0_corpus.txt` → record the totals (expect the current baseline).
- [ ] **Step 4: Report.** Status, seed/fixed point/md5, the stdlib count, corpus totals, concerns. Ledger line.

---

### Task 1: `std_net` primitives

**Files:**
- Modify: `sf/src/std_net.zig`
- Create: `repro/mi_matrix/stdlib_net_resolve_xmod/`, `…connectto_xmod/`, `…soerror_xmod/`, `…shutdown_xmod/`
- Modify: `scripts/stdlib/expected_dirs.txt`, `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh`, `docs/sf/QUICK_REF.md` (only if the module is new — `std_net` already exists, so **no** copy-list change needed for this task; the copy-list edits belong to Tasks 2–3 for the new files)

**Interfaces:**
- Consumes: existing `std_net` `Socket`, `NetError`, `mapErr`, `lastErr`, `setNonBlocking`, `select`.
- Produces (exact, per spec §4.1): `pub fn resolve(host: []const u8) NetError!u32`; `pub fn tcpSocket() NetError!Socket`; `pub fn connectToIp(s: Socket, ip_be: u32, port: u16, timeout_ms: u32) NetError!void`; `pub fn checkSoError(s: Socket) NetError!void`; `pub fn shutdown(s: Socket, how: i32) void`.

- [ ] **Step 1: Write the four fixtures and their GREEN contracts.**
  - `stdlib_net_resolve_xmod/main.zig`: `resolve("localhost")` must yield the loopback address; print `resolve ok <hex>` where `<hex>` is the network-order u32 in `%08x`. Contract: `resolve ok 0100007f` (little-endian host printing of `127.0.0.1` in network order — verify on the host and record the true bytes).
  - `stdlib_net_connectto_xmod/main.zig`: create a listening socket via `createTcpServer(port)` + `bindListen`, then `tcpSocket` + `connectToIp(127.0.0.1, port)`, `accept`, `send` "hi", `recv` it back, print `connectto ok`. Declare the port in `ports.txt`.
  - `stdlib_net_soerror_xmod/main.zig`: `connectToIp` to a closed loopback port must return an error; print `soerror refused`.
  - `stdlib_net_shutdown_xmod/main.zig`: connect loopback, `shutdown(client, 1)` (send side); server `recv` returns 0; print `shutdown ok`. Declare the port.
- [ ] **Step 2: Run each fixture to verify it fails/needs capture.**
  `bash scripts/stdlib/run_fixtures.sh /tmp/z9_m0_seed/zig1_5_clean repro/mi_matrix/stdlib_net_resolve_xmod`
  Expected: FAIL (no `expected.txt` yet) — confirms discovery.
- [ ] **Step 3: Implement the primitives in `sf/src/std_net.zig`.**
  - `resolve`: `extern "c"`/`"stdcall"`-style declare `gethostbyname(name: [*]const u8) ?*HostEnt`; copy `h_addr_list[0]`'s 4 bytes into a `u32` before any other libc call; map null/`h_addrtype != 2` to `error.ResolveFailed` (or reuse an existing member). If a numeric host is passed, `gethostbyname` returns it directly.
  - `tcpSocket`: `socket(2, 1, 6)` via the existing `socket_os`; map `<0` through `mapErr`.
  - `connectToIp`: build a `SockAddrIn` with `sin_family=2`, `sin_port=htons(port)`, `sin_addr=ip_be`; `setNonBlocking`; call `connect_os`; on immediate 0 return; on would-block, `select` on the write set with `timeout_ms`, then `checkSoError`; close + `error.Timeout` on timeout.
  - `checkSoError`: `getsockopt(SOL_SOCKET, SO_ERROR)` (declare `getsockopt` extern), read the i32, normalize 0 → ok, else through `mapErr`.
  - `shutdown`: declare `shutdown_os(fd, how)` extern; call it.
  - Reuse the existing `SockAddrIn`/`WSAData` layout constants; do not duplicate endian helpers.
- [ ] **Step 4: Capture and review goldens.**
  `bash scripts/stdlib/run_fixtures.sh --capture /tmp/z9_m0_seed/zig1_5_clean repro/mi_matrix/stdlib_net_resolve_xmod repro/mi_matrix/stdlib_net_connectto_xmod repro/mi_matrix/stdlib_net_soerror_xmod repro/mi_matrix/stdlib_net_shutdown_xmod`
  Review each `expected.txt` against the contract in Step 1, then re-run without `--capture` and confirm `4 PASS / 0 FAIL`.
- [ ] **Step 5: Add the fixture dirs to the pin.** Append the four dirs to `scripts/stdlib/expected_dirs.txt` (sorted position). Re-run discovery mode:
  `bash scripts/stdlib/verify_stdlib.sh /tmp/z9_m0_seed/zig1_5_clean` → expect `STDLIB GATE OK` and `<old+4> PASS / 0 FAIL`.
- [ ] **Step 6: Proving-tree gate + commit.** Rebuild `/tmp/z9_m0_seed2` and confirm `hop1 == hop2 == <baseline fixed point>` (unmoved). Commit `sf/src/std_net.zig`, the four fixture dirs, and `expected_dirs.txt`:
  `git add sf/src/std_net.zig repro/mi_matrix/stdlib_net_* scripts/stdlib/expected_dirs.txt && git commit -m "feat(std_net): add resolve/connectToIp/checkSoError/shutdown (+fixtures)"`
- [ ] **Step 7: Report.** Status, files, fixture PASS lines, fixed-point evidence, concerns. Ledger line.

---

### Task 2: `std_bencode` decode

**Files:**
- Create: `sf/src/std_bencode.zig` (decode half)
- Create: `repro/mi_matrix/stdlib_bencode_decode_xmod/`, `…limits_xmod/`
- Modify: `scripts/stdlib/expected_dirs.txt`, `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh`, `docs/sf/QUICK_REF.md`

**Interfaces:**
- Produces: `Value`, `Entry`, `Span`, `BencodeError` (spec §4.2); `pub fn decode(arena, bytes) BencodeError!Value`; `pub fn dictValueSpan(bytes, key) BencodeError!?Span`.

- [ ] **Step 1: Write the fixtures.**
  - `stdlib_bencode_decode_xmod/main.zig`: decode a nested fixture string (`d1:ai1e1:b3:xyzl1:iee` style) and print each field; contract is a deterministic multi-line report ending `decode ok`.
  - `stdlib_bencode_limits_xmod/main.zig`: feed `i04e`, `i-0e`, `i99999999999999999999e`, a duplicate-key dict, a 101-deep list, a string whose length exceeds remaining input; each must return the documented error (print the error name); contract ends `limits ok`.
- [ ] **Step 2: Verify FAIL (uncaptured)** as Task 1 Step 2.
- [ ] **Step 3: Implement decode.** Recursive-descent over the byte slice with an out-of-band depth counter (cap 100), key count per dict (cap 1024), per-value cap 32 MB, total 64 MB; reject duplicate keys; check string length ≤ remaining; `i64` via `std_parse.parseInt64` with overflow → `Overflow`. Track each value's start/end offsets for `dictValueSpan`. Arena-allocate lists/dicts/`Value` arrays.
- [ ] **Step 4: Implement `dictValueSpan`.** Walk only the top-level dict: parse `d`, then repeatedly parse a key string and skip its value while recording the top-level `info` value's start/end; return `Span{start,end}` with `u32` offsets (reject inputs > 4 GB). Must not allocate.
- [ ] **Step 5: Capture goldens + review; run PASS.**
- [ ] **Step 6: Register the module (same commit).** Append `sf/src/std_bencode.zig` to the `lib/` copy lists in `scripts/seed/build_from_seed.sh` and `scripts/seed/archive_seed.sh` (and the archive_seed doc comment), and add a row to the `docs/sf/QUICK_REF.md` std inventory. Add the two fixture dirs to `expected_dirs.txt`.
- [ ] **Step 7: Proving-tree gate + commit.** Rebuild, confirm fixed point unmoved. Commit `sf/src/std_bencode.zig`, both fixture dirs, `expected_dirs.txt`, both seed scripts, `QUICK_REF.md`:
  `git commit -m "feat(std_bencode): add bencode decode + dictValueSpan (+fixtures)"`
- [ ] **Step 8: Report.** Ledger line.

---

### Task 3: `std_bencode` encode

**Files:**
- Modify: `sf/src/std_bencode.zig`
- Create: `repro/mi_matrix/stdlib_bencode_encode_xmod/`, `…oom_xmod/`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes: Task 2's `Value`/`Entry`/`BencodeError`.
- Produces: `pub fn encode(arena, value) BencodeError![]u8`.

- [ ] **Step 1: Write the fixtures.**
  - `stdlib_bencode_encode_xmod/main.zig`: build a `Value` tree, `encode` it, print the hex or the raw bytes, and assert canonical equality against a hand-written expected; contract ends `encode ok`.
  - `stdlib_bencode_oom_xmod/main.zig`: a 64-byte arena must return `OutOfMemory` on a value needing more; contract ends `oom ok`.
- [ ] **Step 2: Verify FAIL (uncaptured).**
- [ ] **Step 3: Implement `encode`.** Recursive writer over a `std_buf.Buf`-style arena buffer: `i<n>e`, `<len>:<bytes>`, `l…e`, `d…e`; integers via `std_parse.itoa64` (handle negatives). Keys emitted in stored order.
- [ ] **Step 4: Capture goldens + review; PASS.**
- [ ] **Step 5: Add the two dirs to `expected_dirs.txt`; full `verify_stdlib` PASS.**
- [ ] **Step 6: Proving-tree gate + commit.**
  `git commit -m "feat(std_bencode): add bencode encode (+fixtures)"`
- [ ] **Step 7: Report.** Ledger line.

---

### Task 4: `std_http`

**Files:**
- Create: `sf/src/std_http.zig` (with the `DEFERRED` module-header note)
- Create: `repro/mi_matrix/stdlib_http_parseurl_xmod/`, `…percentencode_xmod/`, `…parseresponse_xmod/`, `…parseresponse_chunked_reject_xmod/`, `…badurl_xmod/`
- Modify: `scripts/stdlib/expected_dirs.txt`, `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh`, `docs/sf/QUICK_REF.md`

**Interfaces:**
- Consumes: Task 1's `std_net.resolve/tcpSocket/connectToIp/shutdown/send/recv/close`.
- Produces: spec §4.3 API (`Url`, `Header`, `Response`, `HttpError`, `parseUrl`, `percentEncode`, `parseResponse`, `get`).

- [ ] **Step 1: Write the fixtures.**
  - `stdlib_http_parseurl_xmod/main.zig`: `http://host:PORT/path?query`, no-port default 80, empty path → `/`, rejects `https://`; print each parsed field.
  - `stdlib_http_percentencode_xmod/main.zig`: encode 20 raw bytes including `\0`, `/`, `+`, space, and `0x80`; print the encoded string.
  - `stdlib_http_parseresponse_xmod/main.zig`: parse a raw `HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabc`; print status + one header + body.
  - `stdlib_http_parseresponse_chunked_reject_xmod/main.zig`: a `Transfer-Encoding: chunked` response must return `BadResponse`; print `chunked rejected` (documents the deferral).
  - `stdlib_http_badurl_xmod/main.zig`: `https://x`, `://x`, empty → `BadUrl`.
- [ ] **Step 2: Verify FAIL (uncaptured).**
- [ ] **Step 3: Implement `parseUrl` + `percentEncode`.**
  - `parseUrl`: split `scheme://host[:port]/path[?query]`; scheme must be `http`; default port 80; path defaults to `/`.
  - `percentEncode`: for each byte, pass `[A-Za-z0-9._~-]`, else emit `%` + uppercase hex; required for raw `info_hash`/`peer_id`.
- [ ] **Step 4: Implement `parseResponse` (pure).** Split at `\r\n\r\n`; parse the status line and case-insensitive headers; if `Content-Length` present, body = next N bytes; else body = the rest; if `Transfer-Encoding: chunked` appears, return `BadResponse`. Enforce header-block 8 KB and body 1 MB.
- [ ] **Step 5: Implement `get`.** `parseUrl` → `resolve(host)` → `tcpSocket` → `connectToIp(ip, port, timeout_ms)` → send `GET <path>[?query] HTTP/1.1\r\nHost: <host>\r\nConnection: close\r\n\r\n` in one write → read to EOF into a bounded buffer → `parseResponse`; follow one redirect (301/302/303/307: re-parse `Location` as a new URL, once).
- [ ] **Step 6: Module-header DEFERRED note (binding).** The first comment block of `sf/src/std_http.zig` MUST state: `HTTP/1.1, no TLS. DEFERRED: chunked transfer-encoding and keep-alive are not implemented; requires Content-Length or a close-delimited body.`
- [ ] **Step 7: Capture goldens + review; PASS.**
- [ ] **Step 8: Register the module (same commit).** Append `sf/src/std_http.zig` to both seed copy lists (+ archive_seed doc comment) and the QUICK_REF inventory; add the five dirs to `expected_dirs.txt`; full `verify_stdlib` PASS.
- [ ] **Step 9: Proving-tree gate + commit.**
  `git commit -m "feat(std_http): add HTTP/1.1 GET client (+fixtures; chunked/keep-alive deferred)"`
- [ ] **Step 10: Report.** Ledger line.

---

### Task 5: M0 closeout

**Files:**
- Modify: `docs/sf/QUICK_REF.md` (std inventory final reconcile)
- Record: `.superpowers/sdd/2026-10-08-z9torr-m0-std-prerequisites-plan/task-5-report.md`

- [ ] **Step 1: Full battery.** Rebuild clean; `verify_stdlib` `<old+13> PASS / 0 FAIL`; corpus classify totals unchanged except any expected movement; 8 dump-MD5 pins unchanged (gol/lisp/json/mud × `-fsafe`/`-ffast`); `scripts/check_emit_support.sh` 7/7.
- [ ] **Step 2: Fixed point UNMOVED.** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9_m0_close` → `hop1 == hop2 == <Task 0 fixed point>`. If moved, **STOP-present**.
- [ ] **Step 3: QUICK_REF reconcile.** Confirm all three modules appear in the copy list and inventory; note the `std_http` defers.
- [ ] **Step 4: Report + commit.** Commit the QUICK_REF reconcile and the report. Ledger line.
- [ ] **Step 5: Next plan.** State that M1 (`2026-10-08-z9torr-m1-core-plan.md`) is next.

## Self-Review

- **Spec coverage:** spec §4.1 → Task 1; §4.2 → Tasks 2–3; §4.3 → Task 4; §9 determinism/memory → fixtures are deterministic (3×) and `oom` fixtures cover the arena gate; §10 conventions → copy-list/pin updates in Tasks 2/4.
- **Placeholder scan:** no TBDs; every fixture has a named GREEN contract and exact command; every registration touchpoint is named.
- **Type consistency:** `resolve`/`connectToIp`/`checkSoError`/`shutdown`, `Value`/`Entry`/`Span`/`BencodeError`/`decode`/`encode`/`dictValueSpan`, `Url`/`Header`/`Response`/`HttpError`/`parseUrl`/`percentEncode`/`parseResponse`/`get` are used identically here and in the spec.
