# Phase 3 Missing Libraries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship zstd dictionary support (full RFC 8878), a zlib/deflate inflater, and HTTP POST/streaming in the std library (Milestone 1), then two thin apps — `z9zstddecomp` and a read-only Git client `z9git` — under `examples/z98/` (Milestone 2), with `z9git` hardened for real GitHub/GitLab clones (large repositories, bounded memory, resumable downloads) before closeout. **Follow-on:** milestone **3.3 — HTTP/2 client**, then **3.5 — compiler improvements**, each with its own plan/spec.

**Architecture:** Flat `std_*.zig` modules imported by path (no barrel change → fixed point and 8 pins unmoved). `std_zstd` gains a dictionary path (additive entry point); `std_deflate` is a new no-heap inflate module reporting consumed input; `std_http` gains POST plus a streaming response sink so packs flow to disk in bounded chunks, plus the large-repo helpers the Git client needs (streaming GET, redirects, optional streaming request body). `z9git` layers an object store (pack v2 + idx v2 + loose fallback + delta reconstruction) under a small CLI (clone/log/checkout/fetch) speaking local-path, `file://`, and GitHub/GitLab standard smart HTTP v0 over `std_tls`; large packs are streamed to disk, the idx is synthesized with an external-memory pass, and clone/fetch can resume via shallow/deepen, partial clone (`filter=blob:none`), and a finalized-prefix + `have` fallback. HTTP/2 is deliberately out of this milestone (3.3).

**Tech Stack:** Z98 (Zig subset) compiled to C89 by `zig1`; std modules `std_zstd/std_deflate/std_http/std_crypto/std_tls/std_file/std_arena`; test fixtures generated with system libzstd 1.5.4 (gcc helper) and real git 2.39; Win9x verification via emitted MSVC/OWC/MinGW scripts + Wine tiers.

**Spec:** `docs/superpowers/specs/2026-11-04-phase3-missing-libraries-design.md`

## Global Constraints

- No compiler-pipeline changes; no `sf/src/std.zig` barrel changes (path imports only).
- No heap/GC on decode paths; caller-provided buffers; internal fixed decode tables.
- Emitted C must compile with MSVC 6 / OpenWatcom / MinGW; Win9x smoke tiers stay green; import whitelist (`scripts/win32_cross/check_win9x_imports.sh`) stays closed-world.
- Win9x CI smoke policy (operator rulings 2026-11-04): the apps' CI smoke uses the bare **`-osw`** 9x target with a MinGW **no-CRT** build and `check_win9x_imports.sh … 9x`; if a no-CRT app cannot link/run, STOP and present (no silent CRT/`nt` fallback). The static-CRT OpenWatcom/MSVC binaries remain operator-run for release. No new DLLs are allowed on 9x.
- Battery anchors unmoved by this work: frozen-1124 md5 `518eca1a9b5d3e1cc5a48abce214abd8` 0 movers; 8 pins exactly the `scripts/compiler/gate_lower_depth.sh` table; goldens 5/5; markers 3397 lines / 39012 B. Live corpus may grow only additively by new `repro/mi_matrix/stdlib_*` fixture dirs. Examples matrix moves 26→28 at Milestone 2 closeout only.
- API pins (do not vary):
  - `pub fn zstdDecompressDict(src: []const u8, dst: []u8, dict: []const u8, max_window_log: u8) !u32` (errors `Corrupt`, `OutputTooSmall`, `WindowTooBig`); `zstdDecompress` signature and no-dict behavior unchanged (dict frames still `Corrupt`).
  - Dict semantics: magic `0xEC30A437` dicts (RFC 8878 §5.2: id + Huffman/FSE tables + content) and raw-content dicts both accepted (magic-priority); frame dict-id 0 = any supplied dict, nonzero must match the magic dict's id else `Corrupt`; raw dicts apply to dict-id-0 frames only; dict entropy tables seed first-block `Repeat`; dict content pre-seeds history (last `min(dict.len, window)` bytes matchable).
  - `pub fn inflateRaw(src: []const u8, dst: []u8, used: *usize) !u32` and `pub fn inflateZlib(src: []const u8, dst: []u8, used: *usize) !u32` (errors `Corrupt`, `OutputTooSmall`); `used` = input bytes consumed; `FDICT` → `Corrupt`.
  - `pub fn httpPostOver(arena: *std.arena.Arena, t: *HttpTransport, url: []const u8, body: []const u8, content_type: []const u8, accept: []const u8, out: *Response) !void`; `pub fn httpPostStreamOver(arena: *std.arena.Arena, t: *HttpTransport, url: []const u8, body: []const u8, content_type: []const u8, accept: []const u8, sink: *ResponseSink, out_head: *Response) !void` (header-only `out_head`, de-chunked body to sink, fixed ~1 MiB stream buffer); `pub const ResponseSink = struct { state: *void, write_fn: fn (*void, []const u8) HttpError!void };` empty `content_type`/`accept` omit the header.
  - `z9git` CLI: `z9git clone <url> [dir] [--max-down <KB/s>] [--depth <n>] [--partial]`, `z9git fetch --deepen <n> [--max-down <KB/s>]`, `z9git log [ref]`, `z9git checkout <ref>`, `-h`; schemes `https://`, `http://`, `file://`, bare local path. Loose-object support is mandatory (no `git gc` demanded of anyone); REF_DELTA resolves across pack and loose; clone copies loose objects verbatim; HTTP-fetched packs stream to disk and get a synthesized `*.idx`.
  - `z9zstddecomp` CLI: `z9zstddecomp <in.zst> <out> [--dict <file>] [--max-window-log <n>]`, `-h`.
- Z98 subset syntax only; `zig1` runs sequential in fresh CWDs (`.zig1_*.tmp` collision); source/doc edits via `edit`/`fastedit` only (fixture **generator scripts** may be written as new files and run; no sed/perl/python/awk transforms of existing sources).
- House commits: `feat(std): …`, `example(z9git): …`, `test(…): …`, `docs(…): …`, `chore(seed): rotate v138 …`; explicit-path staging; no push.
- **z9git large-repo/resume scope (T8b/T8c):** GitHub and GitLab standard smart HTTP over HTTPS (public repos; redirects; TLS trust store incl. GitHub/GitLab CAs; chunked; protocol v0; `ofs-delta`; no sideband/thin-pack/gzip; shallow/deepen; partial `filter=blob:none`; prefix + `have` fallback; resume state). `git://`/ssh, LFS, and private auth are out. **HTTP/2 is not here — milestone 3.3.**
- **Arena policy:** `z9git --arena-mb <N>` default **32**, minimum **16**, **no hard upper bound**; dynamically allocated (`VirtualAlloc`/`mmap`/`malloc`) so the OS can page; reset at phase boundaries; spill/stream to disk (external-memory idx, object/checkout streaming, file-backed bases for huge deltas); a clear allocation-failure error. The README/`-h` documents it.
- **Real-size tiers:** `git/git` full (324 MB repo) is the must-work baseline; graphics Mesa (GitLab; ~1–2 GiB estimate, operator-measured) is the large case; Linux kernel (6.45 GiB repo; ~5 GiB pack) is shallow/partial on modem/old machines and full only on modern Linux; `deepseek-ai/DeepSeek-V3` code (1.7 MiB) is tiny and its Hugging Face LFS weights are out; the CI synthetic pack is 50k–100k objects. The GitHub API `size` is the repo size, not exactly the pack; the full clone `.git` is the same order.
- **Client README/`-h`:** every command (`clone`, `log`, `checkout`, `fetch --deepen`), flag (`--arena-mb`, `--depth`, `--deepen`, `--partial`, `--max-down`), transport, exit code, the resume state, the arena, the disk/pack/object limits, the trust store, public-only, and the LFS limitation.
- **Follow-on order:** this plan → **3.3 HTTP/2** (separate plan/spec + planning session) → **3.5 compiler improvements**.

## Review Focus

1. **Synthesized idx for streamed packs must be git-legal** (offsets, per-entry CRC32, sorted names, trailers) — a wrong extent or CRC silently corrupts the repo → Task 8 step runs `git verify-pack -v` on the synthesized idx and compares against the fixture's git-generated idx.
2. **`used` extents split across adjacent zlib streams in a pack** (next entry header starts exactly at `prev_used`) — off-by-one here desynchronizes every later entry → Task 2 `stdlib_deflate_used_xmod` plus Task 6 hybrid pack fixtures assert exact consumed counts.
3. **Dict history seeding is window-bounded** (offsets may reference only the last `min(dict.len, window)` dict bytes; `max_window_log` interplay) — unbounded reads are OOB → Task 1 `stdlib_zstd_dict_hist_xmod` covers boundary offsets at two window sizes.
4. **Chunked HTTP reassembly under adversarial splits** (chunk-size line split across transport reads, trailers, terminal chunk) — the streaming sink sees corrupt bytes otherwise → Task 3 mock-transport test feeds the response one byte per read.
5. **32-bit pack/delta arithmetic never wraps** (large-offset idx entries, delta src/len bounds, >2 GiB offset decode) — wrap = wrong offsets on Win98 → Task 6 unit case decodes a synthetic large-offset idx entry and asserts `Corrupt` (not wrap) on out-of-range delta src.
6. **Resume correctness** (a dropped modem must not corrupt the store or restart from zero) — the prefix/shallow/haves/state paths → Task 8c aborts a mock/real transfer mid-pack, retries, and verifies the final `git verify-pack`/worktree.
7. **Bounded large-repo memory** (no O(pack) arrays; the 32 MB default must work for the synthetic and `git/git`) — Task 8b external idx/streaming + disk preflight + a clear largest-object/base failure.
8. **GitHub/GitLab conformance** (redirects, TLS/trust, chunked, v0, shallow/partial) — Task 8b/8c opt-in real clones plus the Win9x no-CRT/9x smoke.

---

## Milestone 1 — std foundations

Per task: targeted std fixtures (new dirs + the pre-existing sibling dirs as regression). Milestone 1 closeout (Task 4): full std battery + pins + `check_emit_support` + seed v136.

### Task 1: `std_zstd` dictionary support (full RFC 8878)

**Files:**
- Modify: `sf/src/std_zstd.zig`
- Create: `repro/mi_matrix/stdlib_zstd_dict_basic_xmod/{main.zig,expected.txt,expected.rc}`, `repro/mi_matrix/stdlib_zstd_dict_hist_xmod/{main.zig,expected.txt,expected.rc}`, `repro/mi_matrix/stdlib_zstd_dict_raw_xmod/{main.zig,expected.txt,expected.rc}`, `repro/mi_matrix/stdlib_zstd_dict_mismatch_xmod/{main.zig,expected.rc,expected_error.txt}`
- Create: `scripts/fixtures/gen_zstd_fixtures.c` (dev-time generator, `gcc … -lzstd`; emits the byte-array literals used by the fixtures)
- Modify: `scripts/stdlib/expected_dirs.txt` (+4, lexicographically placed)

**Interfaces:**
- Consumes: `std_zstd.zig` internals — frame/header parse (`:1053-1091`), FSE/Huffman table builders, LZ77 executor, `xxh64`, `revInit` bitstream.
- Produces: `pub fn zstdDecompressDict(src: []const u8, dst: []u8, dict: []const u8, max_window_log: u8) !u32` for Task 5. `zstdDecompress` unchanged.

- [ ] **Step 1: write the generator and the failing fixtures**

`gen_zstd_fixtures.c` links `-lzstd`: emit (a) plain dict-compressed frame (`ZSTD_CCtx_loadDictionary` with an RFC-format dict from `ZSTD_trainFromBuffer`), (b) dict-content-heavy frame whose matches reference dict bytes near the window boundary, (c) raw-content dict frame, (d) frame whose dict id ≠ supplied dict id. Fixture `main.zig` files embed the bytes and call `zstdDecompressDict` (or `zstdDecompress` for the mismatch case) asserting exact decompressed output; the mismatch fixture asserts `error.Corrupt` (`expected_error.txt` pinned, force-add per `.gitignore` rule).

- [ ] **Step 2: run the fixtures to verify they fail (RED)**

Run each `main.zig` with a fresh built `zig1` (`scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t1_base`): dict cases must fail today (`error.Corrupt` from the dict-id reject at `std_zstd.zig:1091`). Record output in the task report.

- [ ] **Step 3: implement dictionary parsing and semantics in `sf/src/std_zstd.zig`**

Additive: a dict-parse helper (magic `0xEC30A437` → id + Huffman table + FSE tables + content; else raw content) and a decode path that (per Global Constraints dict semantics) matches frame dict-id, seeds first-block `Repeat` tables from the dict, and pre-seeds history with `dict.content` restricted to `min(dict.len, window_size)` trailing bytes. Keep the no-dict entry rejecting dict frames. Errors stay `Corrupt`/`OutputTooSmall`/`WindowTooBig`.

- [ ] **Step 4: run the fixtures to verify they pass (GREEN)**

All four new dirs pass; `scripts/stdlib/verify_stdlib.sh` run restricted to the new + `stdlib_zstd_*` dirs (targeted battery) shows 6/6 PASS; 32-bit-overflow discipline preserved (no new pointer end-arithmetic).

- [ ] **Step 5: regression + pins spot**

Existing `stdlib_zstd_basic_xmod` / `stdlib_zstd_cross_xmod` unchanged (byte-identical expected outputs); `bash scripts/compiler/gate_lower_depth.sh` case 5 pins unmoved.

- [ ] **Step 6: Commit**

```bash
git add sf/src/std_zstd.zig scripts/fixtures/gen_zstd_fixtures.c scripts/stdlib/expected_dirs.txt repro/mi_matrix/stdlib_zstd_dict_basic_xmod repro/mi_matrix/stdlib_zstd_dict_hist_xmod repro/mi_matrix/stdlib_zstd_dict_raw_xmod repro/mi_matrix/stdlib_zstd_dict_mismatch_xmod
git commit -m "feat(std): zstd dictionary support (RFC 8878 full)"
```

### Task 2: `std_deflate` zlib/deflate inflate

**Files:**
- Create: `sf/src/std_deflate.zig`
- Create: `repro/mi_matrix/stdlib_deflate_zlib_basic_xmod/{main.zig,expected.txt,expected.rc}`, `stdlib_deflate_raw_xmod/…`, `stdlib_deflate_dynamic_xmod/…`, `stdlib_deflate_used_xmod/…`, `stdlib_deflate_corrupt_xmod/{main.zig,expected.rc,expected_error.txt}`
- Create: `scripts/fixtures/gen_deflate_fixtures.py` (python3 `zlib` module; emits fixture byte arrays: stored/fixed/dynamic blocks, raw streams, concatenated streams for `used`, bad FCHECK / Adler / truncated corruptions)
- Modify: `scripts/seed/build_from_seed.sh` (module copy list += `sf/src/std_deflate.zig`), `scripts/seed/archive_seed.sh` (copy list + counts 51→52)
- Modify: `scripts/stdlib/expected_dirs.txt` (+5, lexicographically placed)

**Interfaces:**
- Consumes: nothing prior (self-contained, like `std_zstd`).
- Produces: `pub fn inflateRaw(src: []const u8, dst: []u8, used: *usize) !u32` and `pub fn inflateZlib(src: []const u8, dst: []u8, used: *usize) !u32` for Tasks 6 and 8 (pack entry extents, loose objects).

- [ ] **Step 1: write generator + failing fixtures (RED)**

`gen_deflate_fixtures.py` produces the five fixture dirs; the corrupt fixture pins `error.Corrupt`; `stdlib_deflate_used_xmod` embeds two concatenated zlib streams and asserts both exact output lengths and exact `used` values. Run with a built `zig1` — module missing → compile failure (RED).

- [ ] **Step 2: implement `sf/src/std_deflate.zig`**

RFC 1950 wrapper (CMF/FLG + FCHECK validation, FDICT → `Corrupt`, Adler-32 verify) around an RFC 1951 inflater (stored/fixed/dynamic blocks, code-length alphabet, length/distance tables, 32 KiB window, overlapping matches copied byte-by-byte). Internal fixed single-level decode tables; no heap; `used` counts all consumed input (wrapper bytes included); `error.Corrupt` for any malformed stream, `error.OutputTooSmall` when `dst` cannot hold the output.

- [ ] **Step 3: verify GREEN + targeted battery**

All five new dirs PASS; sibling `stdlib_lz4_*` / `stdlib_zstd_*` dirs unaffected. `used` values in `stdlib_deflate_used_xmod` exact (this pins Review Focus 2).

- [ ] **Step 4: commit**

```bash
git add sf/src/std_deflate.zig scripts/fixtures/gen_deflate_fixtures.py scripts/stdlib/expected_dirs.txt scripts/seed/build_from_seed.sh scripts/seed/archive_seed.sh repro/mi_matrix/stdlib_deflate_zlib_basic_xmod repro/mi_matrix/stdlib_deflate_raw_xmod repro/mi_matrix/stdlib_deflate_dynamic_xmod repro/mi_matrix/stdlib_deflate_used_xmod repro/mi_matrix/stdlib_deflate_corrupt_xmod
git commit -m "feat(std): std_deflate zlib/deflate inflater with consumed-input reporting"
```

### Task 3: `std_http` POST + streaming response sink

**Files:**
- Modify: `sf/src/std_http.zig`
- Create: `repro/mi_matrix/stdlib_http_post_xmod/{main.zig,expected.txt,expected.rc}`, `repro/mi_matrix/stdlib_http_post_stream_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt` (+2)

**Interfaces:**
- Consumes: existing `HttpTransport` fn-pointer transport, `parseResponse`, chunked-body reader (`std_http.zig:423`).
- Produces (Task 8): `httpPostOver`, `httpPostStreamOver`, `ResponseSink`, `post` exactly as pinned in Global Constraints.

- [ ] **Step 1: failing fixtures (RED)**

Both fixtures drive a mock `HttpTransport` (scripted read buffer). `stdlib_http_post_xmod`: POST request shape (request line, `Content-Type`, `Accept`, `Content-Length`, `Connection: close`) + small identity response. `stdlib_http_post_stream_xmod`: chunked response **fed one byte per `read_fn` call**, split chunk-size lines and a chunk-data boundary across reads, terminal `0\r\n\r\n` trailer; sink receives the exact de-chunked body (hash-compared); `out_head` carries status/headers with empty body. RED: `httpPostOver`/`httpPostStreamOver` undefined.

- [ ] **Step 2: implement in `sf/src/std_http.zig`**

`httpPostOver` mirrors `httpGetOver` (same URL parsing, `Connection: close`, identity + chunked response bodies, existing 1 MiB whole-body cap, empty `content_type`/`accept` omit headers). `httpPostStreamOver` reuses the request builder but routes de-chunked body bytes to `ResponseSink.write_fn` through a fixed ~1 MiB stream buffer; headers land in `out_head` (body empty). Convenience `post(arena, url, body, content_type, accept, timeout_ms)` mirrors `get`. Buffered variant keeps its 1 MiB cap; the streaming variant is unbounded (hardware-capped).

- [ ] **Step 3: verify GREEN + targeted battery**

Both fixtures PASS (the byte-split chunked case pins Review Focus 4); `stdlib_http_*` sibling dirs unaffected.

- [ ] **Step 4: commit**

```bash
git add sf/src/std_http.zig scripts/stdlib/expected_dirs.txt repro/mi_matrix/stdlib_http_post_xmod repro/mi_matrix/stdlib_http_post_stream_xmod
git commit -m "feat(std): std_http POST and streaming response sink"
```

### Task 4: Milestone 1 closeout — full std battery + seed v136

**Files:**
- Modify (docs): `docs/sf/QUICK_REF.md`, `STD_README.MD`, `sf/docs/std_lib/` pages for `std_zstd`/`std_deflate`/`std_http` (update existing or create per `_template.md`)
- Modify (seed): `release/seed/CHANGELOG.md`, `release/seed/zig1-seed.tgz`, `release/seed/zig1_seed_w9.zip` via `scripts/seed/archive_seed.sh`

- [ ] **Step 1: full std battery**

`bash scripts/stdlib/verify_stdlib.sh <built-zig1>` → all fixtures PASS (count grows from 342 by the +14 of Tasks 1-3: T1 +5, T2 +7, T3 +2 → 356) and `run_crosscheck` 10/10.

- [ ] **Step 2: anchor gates**

`scripts/compiler/gate_lower_depth.sh` case 5 pins 8/8 unmoved; `scripts/check_emit_support.sh` 8/8; frozen-1124 md5 spot (new dirs are additive only); `git diff --check` clean.

- [ ] **Step 3: seed v136 rotation**

`bash scripts/seed/archive_seed.sh <bin> <gen> release/seed/zig1-seed.tgz --update-changelog --win9x-zip release/seed/zig1_seed_w9.zip`; verify archive md5 / zip md5 / `lib/` 52 / manifest; rebuild-from-archive closure (fixed point expected **unchanged** — no compiler source change; if it moves, STOP and report). CHANGELOG v136 must state the exact std additions and battery numbers.

- [ ] **Step 4: docs truth-up + commit**

QUICK_REF/STD_README module counts 51→52 and the three module pages match the pinned APIs; manual by-path module tables (`docs/sf/manuals/en/vol2-17-stdlib.html`, `vol4-18-stdlib.html`) gain the `std_deflate` row/section alongside `std_zstd`/`std_http` updates. Commit `chore(seed): rotate v136 (std_deflate + zstd dicts + http post/stream)` and `docs(sdd)`.

---

## Milestone 2 — apps

### Task 5: `z9zstddecomp` CLI + tiers

**Files:**
- Create: `examples/z98/z9zstddecomp/{main.zig, README.md}`, `examples/z98/z9zstddecomp/tests/{tier_zstddecomp.sh, gen_fixtures.c, fixtures/*.zst}`
- Modify: `sf/src/std_zstd.zig` (new public `zstdFrameContentSize(src) ?u64` helper, shared by the decoder and the app so the app no longer duplicates frame/block parsing), `sf/docs/std_lib/zstd.md`, `docs/sf/QUICK_REF.md`, `release/seed/CHANGELOG.md`, `release/seed/zig1-seed.tgz`, `release/seed/zig1_seed_w9.zip` (seed **v137** rotation after the helper lands; fixed point expected unchanged, lib stays 52). Operator ruling 2026-11-04: the battery target is the **`stdlib_zstd_*` set**, not the full compiler/std battery.
- Modify: (closeout handles matrix counts) none

**Interfaces:**
- Consumes: `sf/src/std_zstd.zig` — `zstdDecompress`, `zstdDecompressDict`, and the new `zstdFrameContentSize` (path import, no barrel).
- Produces: standalone example; CLI contract in Global Constraints. Exit codes: `0` ok, `1` usage, `2` input open/read error, `3` decode error (Corrupt/WindowTooBig), `4` output write error, `5` output exceeds `--max-output` (default 16 MiB; a declared frame content size is used exactly when present via `zstdFrameContentSize`, else grow-and-retry doubling to the cap; a declared size larger than the app's arena capacity is rejected at argument validation with rc1; a lying declared size maps to `Corrupt` → rc3).

- [ ] **Step 1: failing tier skeleton (RED)**

`gen_fixtures.c` (libzstd) writes `tests/fixtures/`: plain, 4-stream, RLE, skippable+payload, checksum-on, magic-dict, raw-dict, dict-mismatch, truncated. `tier_zstddecomp.sh` asserts per-fixture exit codes and output bytes (golden md5s), `-h` usage rc 0, bad-args rc 1. RED: example dir absent.

- [ ] **Step 2: implement `main.zig` + README**

CLI per contract; reads input whole via `std_file`, decodes via `zstdDecompress`/`zstdDecompressDict` (`--dict` loads the file: magic dict or raw), writes output via `std_file`. README = house `## Building with zig1` block (Linux + Windows 9x) + usage/exit codes. Imports: `std_zstd.zig`, `std_file.zig`, `std_str.zig`/`std_fmt.zig` only (no barrel).

- [ ] **Step 3: tier GREEN + Win9x smoke**

`tests/tier_zstddecomp.sh`: Linux build/run all fixture cases (including the lying-declared-size FCS=1/FCS=0 regressions, the missing/unreadable `--dict` rc2, the grow-path `--max-output` rc5, and the arena-capability rc1 case); then bare **`-osw`** emit + MinGW **no-CRT** build + Wine run of two cases (plain + magic-dict) + `check_win9x_imports.sh … 9x` PASS (if the no-CRT link/run fails, STOP and present; no silent CRT/`nt` fallback). Compile RSS recorded (<16 MiB). Additionally: implement the `zstdFrameContentSize` helper and use it in the decoder/app, run the targeted `stdlib_zstd_*` fixtures + crosscheck 10/10 (operator: std_zstd-only target, not the full battery), and rotate seed **v137** (fixed point unchanged; lib 52) with truthful CHANGELOG/QUICK_REF/zstd.md updates.

- [ ] **Step 4: commit**

Logical commits:
```bash
# std helper (lib change; targeted std_zstd battery only)
git add sf/src/std_zstd.zig sf/docs/std_lib/zstd.md
git commit -m "feat(std): expose zstd frame content size"

# example + tier + fixtures + README
git add examples/z98/z9zstddecomp
git commit -m "example(z9zstddecomp): zstd decompressor CLI with dictionary support"

# seed rotation after the helper (fixed point unchanged)
git add release/seed/CHANGELOG.md release/seed/zig1-seed.tgz release/seed/zig1_seed_w9.zip docs/sf/QUICK_REF.md
git commit -m "chore(seed): rotate v137 (zstd content-size helper)"
```

### Task 6: `z9git` object store (pack/idx/loose/delta)

**Files:**
- Create: `examples/z98/z9git/{objects.zig, pack.zig, delta.zig}`
- Create: `examples/z98/z9git/tests/{unit_store.sh, store_test.zig, gen_repos.sh, testdata/{packed_repo, loose_repo, hybrid_repo}/…}` (fixture repos committed; `gen_repos.sh` documents regeneration with git 2.39)

**Interfaces:**
- Consumes: `inflateRaw`/`inflateZlib` (Task 2), `std_crypto` `sha1*`/`crc32*`, `std_file` seek/read, `std_arena`.
- Produces (Tasks 7-8):
  - `pub const ObjectId = [20]u8;` `pub const ObjType = enum(u8) { commit, tree, blob, tag };` `pub const TypedObject = struct { ty: ObjType, data: []const u8 };`
  - `pub fn storeOpen(arena: *std.arena.Arena, git_dir: []const u8, s: *Store) !void` — scans `objects/pack/*.idx` + loose layout.
  - `pub fn storeReadTyped(arena: *std.arena.Arena, s: *Store, id: ObjectId, out: *TypedObject) !void` — decompressed + SHA-1 verified; `error.NotFound` / `error.Corrupt`.
  - `pub fn storeWriteLoose(git_dir: []const u8, id: ObjectId, zlib_bytes: []const u8) !void` — verbatim loose copy (clone).
  - `pub fn deltaApply(base: []const u8, delta: []const u8, out: []u8) !void` — copy/insert reconstruction (RFC-documented Git delta format).

- [ ] **Step 1: fixture repos + failing unit harness (RED)**

`gen_repos.sh` (run once, results committed): `packed_repo` (commits/trees/blobs/tags + `git gc` → pack v2 + idx v2, incl. OFS_DELTA chain and REF_DELTA), `loose_repo` (no `gc`, loose objects only), `hybrid_repo` (delta in pack whose base is loose). `store_test.zig` asserts: packed lookup vs `git cat-file` goldens, loose lookup, hybrid REF_DELTA across pack/loose, OFS_DELTA chain reconstruction, `storeWriteLoose` round-trip, not-found `error.NotFound`, malformed idx/pack `error.Corrupt`, synthetic large-offset idx entry decode (and `Corrupt` — never wrap — on out-of-range delta src). RED: modules absent.

- [ ] **Step 2: implement `pack.zig` (pack v2 + idx v2 parse)**

idx v2: fanout table binary search, sorted 20-byte names, CRC32 stride skip, 31-bit offsets with MSB-large-offset indirection, 8-byte offset table, trailer checksums. Pack v2: `PACK` header, varint type/size entry headers (commit/tree/blob/tag/OFS_DELTA/REF_DELTA), OFS_DELTA relative-offset varint exactly per Git spec, zlib payloads reported with `used` to find the next entry. Sliding 1–4 MiB window over the pack fd (`std_file` seek/read) — never map the whole pack.

- [ ] **Step 3: implement `delta.zig` + `objects.zig`**

Delta apply (copy bitmask 7 bytes, insert 1-127, no delete; source/target length varints) with bounds checks (`error.Corrupt` on overrun). `objects.zig`: store scan + lookup (pack then loose), recursive base resolution with a fixed memoized base cache (arena-bounded, e.g. 16 entries), SHA-1 verify (`type len\0data`) on every materialized object, Adler-32 inside inflate.

- [ ] **Step 4: unit harness GREEN + pins spot**

`tests/unit_store.sh` all cases PASS; `bash scripts/compiler/gate_lower_depth.sh` case 5 pins unmoved; `git diff --check` clean.

- [ ] **Step 5: commit**

```bash
git add examples/z98/z9git/objects.zig examples/z98/z9git/pack.zig examples/z98/z9git/delta.zig examples/z98/z9git/tests
git commit -m "example(z9git): pack/idx/loose object store with delta reconstruction"
```

### Task 7: `z9git` CLI — local clone, log, checkout

**Files:**
- Create: `examples/z98/z9git/{main.zig, cli.zig, repo.zig, README.md}`
- Modify: `examples/z98/z9git/tests/tier_git.sh` (new; local-path cases)

**Interfaces:**
- Consumes: Task 6 store API (`storeOpen`, `storeReadTyped`, `storeWriteLoose`, `deltaApply`).
- Produces (Task 8): `repo.zig` clone-local (`cloneLocal(arena, src_path, dest_dir) !void`) reused by the network path; `cli.zig` arg parsing + exit codes (`0` ok, `1` usage, `2` transport error, `3` protocol error, `4` object-store error, `5` io error).

- [ ] **Step 1: failing tier cases (RED)**

`tier_git.sh` local-path cases: `clone packed_repo` (`.git` layout: copied pack+idx, refs, HEAD; worktree matches `git ls-tree -r` goldens), `clone loose_repo` (loose objects copied verbatim; sha1 names preserved), `log` golden (`<short-id> <author> <date> <subject>` walking parents from HEAD), `checkout <branch>` golden (worktree updated; files absent from the target tree but tracked in the previous HEAD tree are removed; untracked untouched), `-h` rc 0 / bad args rc 1. RED: example absent.

- [ ] **Step 2: implement `cli.zig` + `repo.zig` + `main.zig`**

Per contract in Global Constraints + exit codes above. `cloneLocal` reads the source store (pack + loose), writes dest `.git/objects/pack/*` (packs copied, idx copied when present else synthesized from `used` extents), `refs/`, `HEAD`, and checks out HEAD. README = house `## Building with zig1` block + command reference + transports table.

- [ ] **Step 3: tier GREEN + Win9x smoke**

`tier_git.sh` all local cases PASS (goldens byte-exact); bare **`-osw`** + MinGW **no-CRT** build + Wine smoke (`clone`+`log` on `packed_repo`) + `check_win9x_imports.sh … 9x` PASS (same 9x policy as Task 5; if the no-CRT link/run fails, STOP and present — no silent CRT/`nt` fallback).

- [ ] **Step 4: commit**

```bash
git add examples/z98/z9git/main.zig examples/z98/z9git/cli.zig examples/z98/z9git/repo.zig examples/z98/z9git/README.md examples/z98/z9git/tests/tier_git.sh
git commit -m "example(z9git): local clone, log and checkout"
```

### Task 8: `z9git` smart HTTP streaming clone + pacing

**Files:**
- Create: `examples/z98/z9git/{httpgit.zig, pkt.zig}`
- Modify: `examples/z98/z9git/{main.zig, cli.zig}`, `examples/z98/z9git/tests/tier_git.sh`

**Interfaces:**
- Consumes: `httpPostStreamOver`/`ResponseSink` (Task 3), `std_tls` session + `std_x509.TrustStore`, `std_net` TCP (TLS transport glue stays in the app), Task 2 `inflateZlib` (`used` for idx synthesis), Task 6 store/format knowledge.
- Produces: `pkt.zig` — pkt-line encode/decode; `httpgit.zig` — `pub fn httpClone(arena: *std.arena.Arena, url: []const u8, dest_dir: []const u8, max_down_bps: u32) !void` (ref discovery → want/have → streaming pack download → idx synthesis → refs/HEAD → worktree checkout).

- [ ] **Step 1: failing cases (RED)**

Add to `tier_git.sh`: (a) pkt-line unit (encode/decode round-trip, len-prefixed edge values, flush pkt), (b) mocked-transport smart-HTTP case (scripted `info/refs` + `git-upload-pack` responses; asserts request bytes incl. `Content-Type: application/x-git-upload-pack-request`, `Accept: application/x-git-upload-pack-result`; pack streamed to disk; `git verify-pack -v` PASS on the synthesized idx), (c) end-to-end local smart-HTTP case via `git http-backend` behind a tiny python3 CGI server (skippable with explicit notice when `git http-backend` is absent; never vacuous otherwise), `clone http://127.0.0.1:<port>/r.git` worktree identical to the file:// clone golden, (d) `--max-down 1` pacing smoke (download duration floor). RED: modules absent.

- [ ] **Step 2: implement `pkt.zig` + `httpgit.zig`**

pkt-line v0 (4-hex length prefix, flush packet). Ref discovery: GET `info/refs?service=git-upload-pack`, parse refs + capabilities (ignore unknown; no sideband). Negotiation: POST want lines (all refs for v1 clone) + `done`; parse ACK/NAK lines; remaining bytes = PACK stream. Pack download: `httpPostStreamOver` sink tees to `objects/pack/<name>.pack` while hashing SHA-1 on the flow; verify the 20-byte pack trailer; synthesize `*.idx` by walking entries (`inflateZlib` `used` extents, per-entry CRC32 of raw bytes, object ids `SHA-1(type len\0data)`), write fanout/names/crc32/offsets/trailers. `http://` = plain TCP transport; `https://` = `std_net` TCP + `std_tls` handshake with `std_x509.TrustStore` (failure = transport error rc 2). Pacing: sleep between sink chunks to honor `--max-down` (z9torr-style). Then reuse Task 7 refs/HEAD/worktree steps.

- [ ] **Step 3: tier GREEN + Win9x smoke**

All `tier_git.sh` cases PASS including `git verify-pack -v` on synthesized idx (pins Review Focus 1); Win9x smoke: bare **`-osw`** + MinGW **no-CRT** build + Wine run of the mocked-transport case + `check_win9x_imports.sh … 9x` PASS (expect KERNEL32/USER32/WSOCK32; no MSVCRT; no new DLLs — if a new import appears, STOP and present the whitelist delta). If the no-CRT link/run fails, STOP and present; no silent CRT/`nt` fallback.

- [ ] **Step 4: commit**

```bash
git add examples/z98/z9git/pkt.zig examples/z98/z9git/httpgit.zig examples/z98/z9git/main.zig examples/z98/z9git/cli.zig examples/z98/z9git/tests/tier_git.sh
git commit -m "example(z9git): smart HTTP streaming clone with pacing"
```

### Task 8p: `z9git` performance/RAM profile (measure-only)

**Files:**
- Create: `examples/z98/z9git/tests/profile_small.sh` (the ~1 MB real-repo harness) and the small local mirror/fixture selection; the report `task-8p-report.md`.
- Modify (temporary only, removed before commit): the app's phase timers if needed for the per-phase breakdown.
- No std/compiler/seed changes; no fixes.

**Interfaces / measurement contract:**
- Select a real ~1 MB remote repo; record the URL/size (GitHub API) and use the same repo for system git/curl and the app; optionally a local mirror of it.
- Build the app `-ffast` only first. If `-ffast` is considerably slower than the local tool, profile `-ffast` and **do not run `-fsafe` first**; use `-fsafe` only later if needed for OOB/UB or the conservative measurement.
- System baseline: `git clone` local and HTTPS, `git ls-remote`, `curl` the archive; `time -v` wall + max RSS; network bytes.
- App: clone local and HTTPS with `time -v`; peak RSS; `--arena-mb 32` (and 16 if relevant); per-phase wall (TLS handshake, ref discovery, pack download, idx synthesis, checkout) with temporary instrumentation; `valgrind`/`perf`/`gprof`/`callgrind` (whatever is installed); `strace -c`.
- Report: the numbers table (app vs system, local vs HTTPS), top functions, std-lib vs app split, RAM drivers, the data-backed fix list; no fixes.

- [ ] **Step 1: select the ~1 MB repo + local mirror; record the size/URL.**
- [ ] **Step 2: build the app `-ffast` with the profile flags; baseline system git/curl.**
- [ ] **Step 3: run the app (local + HTTPS), capture wall/RAM and the profile; profile `-ffast` first.**
- [ ] **Step 4: report the numbers/top hotspots; no fixes; the T8b fix list.**
- [ ] **Step 5: commit the harness/report only.**

### Task 8b: `z9git` large-repo memory (bounded idx, streaming, limits)

**Files:**
- Modify: `examples/z98/z9git/{pack.zig, objects.zig, repo.zig, httpgit.zig, main.zig, cli.zig, README.md}`, `examples/z98/z9git/tests/tier_git.sh` (+ `gen_large_pack.py`, the real-remote tier)
- Modify: `sf/src/std_http.zig` (streaming GET; optional streaming request body; Range/extra-header GET for non-GitHub static servers)
- Modify if the std surface changes further: `sf/docs/std_lib/http.md`, `docs/sf/QUICK_REF.md`, seed copy lists; **v138 already carries the std_http helpers** — rotate again only if the std surface changes after v138.

**Interfaces:**
- Bounded idx reader: `pack.idxLoad` becomes an `Idx` opened over the idx file — fanout in memory, names/CRC/offsets/large-offset read on demand (`readAt`/`mmap`, binary search), no whole-idx arena load; `storeOpen`/`objects.zig` consume it; the external-memory idx synthesis (two-pass, temp `(id, offset, crc)`, external merge sort, streamed output, per-entry hashing) remains.
- `z9git --arena-mb <N>`: default **32**, min **16**, **no hard upper bound**; dynamically allocated (`VirtualAlloc`/`mmap`/`malloc`), reset at phase boundaries (ref discovery, each pack/prefix, idx, per checkout directory/file); the OS may page; a clear allocation-failure error.
- `objects.zig` bounded store cache + per-file checkout scratch + cache invalidation + streaming object read to a sink (`storeReadTo`) so checkout writes each entry without a whole-object arena copy; file-backed delta base; documented largest-object/base ceiling.
- Symlink/gitlink checkout policy (`repo.zig`): POSIX symlink -> symlink; Windows/Win9x -> a regular file containing the target text (documented); gitlink/submodule (mode 160000) -> empty directory, never fetched (submodules out of scope; `git/git` has `sha1collisiondetection`).
- Disk preflight: in `httpgit.zig`, pass the HTTP `Content-Length` when present (else the PACK object count) into `repo.diskPreflight` before the download/idx/checkout; estimate pack + idx + temp + worktree; free-space check; `DiskFull` rc5 before committing. Document Win9x/FAT32 (2–4 GB) and Linux 2.0/ext2 (~2 GB); POSIX `std_file` is 64-bit.
- README/`-h`: the full client usage, flags, transports, exit codes, resume state, arena, limits, trust store, public-only, LFS out, symlink/gitlink policy.
- Large-repo acceptance: the 100k synthetic + a **smaller real remote** (`melonDS-emu/melonDS`, 12.1 MB, real HTTPS; `git/git` 324 MB only at the final app check); the app's working/functional tier builds **`-ffast`**; the **memory measurement uses `-fsafe`** (conservative), switching to `-fsafe` for suspected OOB/UB; record peak RSS + wall time.
- `git/git` is used only at the final app check (the final part), not in the routine tier.

- [ ] **Step 1: failing large cases (RED)**
  Add the 100k-object synthetic tier and the smaller real-remote case; the current in-memory idx must fail/OOM at the 32 MB default, and the checkout must fail on the O(idx)/O(object) retention.
- [ ] **Step 2: implement the bounded idx reader + objects streaming + arena + preflight**
  Keep the T6/T7 store/CLI behavior and the existing `tier_git.sh` green; the objects/commits stay byte-identical.
- [ ] **Step 3: std_http large-repo helpers**
  `httpGetStreamOver` and the optional streaming request body (the want list); the v138 std_http change is already rotated; run the targeted `stdlib_http_*` + crosscheck; rotate again only if the surface changes.
- [ ] **Step 4: GREEN + memory limits + symlink/gitlink**
  The synthetic large pack and the smaller real remote pass within the 32 MB default; `git verify-pack`; the symlink/gitlink policy; record the peak RSS (`-fsafe` measurement) and wall time (`-ffast` work); the existing tier; Win9x no-CRT/9x unchanged; the README/`-h` updated; the `git/git` final check only at the final part.
- [ ] **Step 5: commits**
  `feat(std): streaming GET/request-body helpers` (already in v138), `perf(z9git): bounded idx reader`, `perf(z9git): streaming checkout and object store`, `feat(z9git): symlink/gitlink checkout policy`, `feat(z9git): Content-Length disk preflight`, the real-remote tier, `docs(sdd)`.

### Task 8c: `z9git` resumable clone (GitHub/GitLab)

**Files:**
- Modify: `examples/z98/z9git/{httpgit.zig, pkt.zig, main.zig, cli.zig, repo.zig, README.md}`, `examples/z98/z9git/tests/tier_git.sh` (+ tests)

**Interfaces:**
- `z9git clone [--depth <n>]`, `z9git fetch --deepen <n>`: shallow/deepen, `.git/shallow`, log stops at the boundary.
- Partial clone `filter=blob:none` (GitHub): commit/tree pack; on-demand blob fetch; checkout integration.
- Prefix + `have` fallback: checkpoint the last complete entry; finalize a prefix pack + idx on disconnect (truncate, trailer SHA-1, idx); retry with `have` for commits with a complete closure; multiple packs; document the pack-order caveat.
- Resume state `.git/z9git-state`: refs, shallow boundary, completed packs/prefixes, offsets; re-running clone/fetch resumes; temp cleanup.
- Redirect/`.git` normalization for GitHub/GitLab; TLS trust store; public-only; Win9x no-CRT/9x unchanged.

- [ ] **Step 1: failing resume cases (RED)**
  The smart HTTP tier cannot resume: add mock/`git http-backend` abort-mid-pack and retry cases, a shallow/deepen case, and GitHub/GitLab opt-in probes (the GitHub `octocat/Hello-World` redirect/TLS; a GitLab smart-HTTP probe — the GitLab **git** endpoint is not Anubis-blocked; the web/API is).
- [ ] **Step 2: implement shallow/deepen + partial + prefix + state**
  Keep the T8 HTTP/1.1 path; no sideband/thin/gzip; `ofs-delta`.
- [ ] **Step 3: GREEN**
  The interrupted clone resumes and finishes; the final idx/worktree match; the pacing; the local/HTTP/mock tiers; the GitHub/GitLab opt-in; Win9x no-CRT/9x.
- [ ] **Step 4: docs**
  README/`-h` for `--depth`, `--deepen`, resume, the partial clone, and the modem/partial recommendations.
- [ ] **Step 5: commit**
  `example(z9git): resumable clone (shallow/partial/prefix)` + `docs(sdd)`; seed only if std changed.

### Task 8c fix round — root corrections (operator 2026-11-05)

**Position:** after review of `1f3baae3`, before Task 9. This supersedes
patch-level fixes for the Task 8c review findings.

**Files (in addition to the Task 8c files):**
- Modify: `sf/src/std_http.zig` (EOF flush), `release/seed/*`,
  `docs/sf/QUICK_REF.md`, `STD_README.MD`, `release/seed/CHANGELOG.md`.
- Tests: `examples/z98/z9git/tests/{tier_git.sh,mock_http.zig}`; targeted
  `stdlib_http_*` + crosscheck for the std_http change.
- No compiler-pipeline changes; no heap/GC on std decode paths.

**Approved root fixes:**

1. **Closure/have/ref-install subsystem.** One helper owns `localRefs()`,
   `closureComplete(tip, shallow, partial)`, `collectHaves()`, and
   `filterRefsForInstall()`. Haves come only from local refs/verified state,
   never from the server advertisement. A tip in a complete pack is trusted; a
   prefix-pack tip is traversed. `.git/shallow` boundaries are terminal for
   traversal. Partial mode ignores blobs. Traversal overflow returns
   “incomplete” (no have/install), never `Protocol`. Install only refs whose
   closure is complete; `state` haves are recomputed/verified, not blindly
   trusted. Fixes the Critical false-have ref install and the shallow-resume
   have gap.
2. **Pack transaction.** Separate wire depth from local depth:
   `clone --depth n` sends absolute `deepen n`; `fetch --deepen n` sends
   `deepen n` with `deepen-relative` and updates local depth only on success.
   Reuse the prefix-finalize transaction for commit/tree and blob packs, with a
   `PackRequest`/state key. Add a real mock `:abort` mid-pack test (>1 MiB) and
   assert prefix install/state/retry `have`; assert the deepen wire line.
3. **Per-directory on-demand partial blob fetch.** Replace the global
   `missingBlobsForRef` tree walk with a `BlobFetcher` callback used during
   checkout: collect missing blobs for one directory, fetch a bounded batch,
   write, continue. No 65,536-tree hard cap; no O(trees) app-arena retention.
   Blob packs use the same prefix/resume transaction.
4. **Transactional state/temp cleanup.** Write `z9git-state.tmp` and rename;
   validate URL/format on load; use `.git/shallow` as the authoritative shallow
   list (remove the duplicate 4096-entry truncation); centralize pack/prefix/blob
   temp cleanup on success and failure.
5. **`std_http` EOF flush.** Flush the stream buffer to the sink before
   returning on early transport EOF, so a tiny (<1 MiB) pack tail is not lost.
   Add a tiny-pack raw-EOF test. This changes `std_http`, so rotate seed
   **v141** and update the seed docs.
6. **CLI/docs.** `--partial` is authorized in the CLI pin, README/`-h`, and the
   Task 8c docs; document `fetch --deepen` as HTTP-only and the partial
   checkout trust-store behavior.

**RED/GREEN tests:** moved-ref fetch (no false `have`/missing objects), shallow
dropped resume with `have`, deepen wire value, real abort-mid-pack, tiny-pack
raw EOF, partial large-tree/per-directory fetch, state atomic/URL, temp
cleanup, `--partial`, full `tier_git.sh` twice, GitHub/GitLab opt-in, Win9x
no-CRT/`9x` + Wine. Targeted `stdlib_http_*` + crosscheck for the std_http
change; full battery remains Task 9. No measured git re-profile.

**Commit(s):** new commits, no amend:
- `fix(z9git): verify have closures and resume shallow fetches`
- `fix(z9git): per-directory partial blob fetch and transactional state`
- `fix(std): flush streaming sink on early EOF`
- `chore(seed): rotate v141 (std_http EOF flush)`
- `docs(sdd): Task 8c report`

### Task 8c fix round 2 — A/B corrections + end-of-round melonDS measurement (operator 2026-11-05)

**Position:** after the Task 8c root fix and docs/provenance review, before
Task 9. Base `9e6b9038`. This round fixes the remaining Task 8c re-review
findings and the authorized out-of-scope quick wins. No std/compiler/seed
change; v141 stays.

**Files:** `examples/z98/z9git/{httpgit.zig,repo.zig,README.md}`,
`examples/z98/z9git/tests/{tier_git.sh,mock_http.zig}`,
`.superpowers/sdd/2026-11-04-phase3-missing-libraries-plan/task-8c-report.md`.

**A. Remaining Task 8c findings:**

1. **No 4096 shallow truncation.** Replace the fixed `SHALLOW_MAX` shallow
   parser storage with a growable/`dynAlloc` list; never silently drop a
   boundary. Write `.git/shallow` atomically where the platform allows; keep
   `.git/shallow` authoritative. Test >4096 shallow lines and verify every
   boundary and `log` stop.
2. **Trust complete packs.** Record pack completeness in state (complete vs
   prefix; unknown = verify). `closureComplete` short-circuits for a tip in a
   complete pack (full mode: complete; partial: ignore blobs). Prefix/loose/
   unknown tips still traverse. Traversal checks blob leaves with `storeHas`
   instead of inflating every blob. `filterRefsForInstall`/`collectHaves` use
   the same helper; haves remain local-ref only. Tests: moved-ref fetch,
   complete-pack no-full-traversal, prefix verification, shallow/partial.
3. **Preserve `.git/shallow` on incomplete prefix.** Track whether the shallow
   section is complete (reached NAK/ACK). On an incomplete prefix with unknown
   shallow, keep the existing `.git/shallow`; only commit a new list when
   known-complete; only delete on a complete known-empty result. Test abort
   before shallow lines with an existing file.

**B. Authorized out-of-scope quick wins:**

4. **Preserve local HEAD on fetch.** `chooseHead` retains its clone fallback,
   but fetch never falls back to another `refs/heads/*`. Keep the current
   symbolic target if present in new refs; keep detached HEAD detached; leave
   HEAD unchanged if the old target is missing/filtered. Test filtered/missing
   advertised HEAD, normal branch fetch, detached fetch.
5. **Bound per-directory missing-blob IDs.** `fetchMissingInTree` must allocate
   the directory ID list with `pack_mod.dynAlloc` or a reusable scratch buffer
   and free/reset after `fetch_fn`; no app-arena O(total missing blobs). Test
   many nested directories at 32 MiB.
6. **Remove stale report text** saying tiny-pack EOF flush is outside this task;
   it is implemented in `std_http` and shipped in v141.

**Verification:** focused RED/GREEN tests for A1-A3/B1-B2; full `tier_git.sh`
once; Win9x no-CRT/`9x` + Wine where touched; `git diff --check`. No seed
rotation.

**End-of-round melonDS measurement (no pre-fix run):**
- Build from v141: `-ffast` and `-fsafe` app binaries, `build_target.sh linux`,
  CA store beside the binary.
- Run sequentially over HTTPS:
  `timeout 1800 <prog> clone https://github.com/melonDS-emu/melonDS.git <dir> --arena-mb 32`.
- Record `/usr/bin/time -v` elapsed + max RSS + exit code; `git verify-pack`,
  `git fsck`, HEAD/worktree; GitHub `ls-remote` throughput.
- Comparable timeout is **1800** for both modes. If `-fsafe` still times out,
  record rc124; do not silently call it a pass or retry longer without a new
  operator ruling.
- Compare with pre-fix Task 8b re-review: `-ffast` 6:04.03/5:55.03, RSS
  ~76.3 MB; `-fsafe` 30:00 timeout rc124; synthetic large 5.50 s / 1:05.69.
- Record the measurement in `task-8c-report.md`; no code changes from the
  measurement.

**Commit(s):**
- `fix(z9git): trust complete packs and bound shallow/fetch memory`
- `docs(sdd): record Task 8c fix round and melonDS timing`

**Then:** scoped re-review from `9e6b9038` over A1-A3/B1-B3 and the
measurement evidence. Do not re-review unrelated code.

### Task 9: Milestone 2 closeout — docs + full battery + (conditional) seed

**Files:**
- Modify (docs): `docs/sf/QUICK_REF.md` (examples matrix 26→28 + app entries), `README.md` (examples count), `STD_README.MD` if module counts quoted, `sf/docs/tech_docs/` only if pipeline docs reference module counts (they do not — verify), example READMEs already written in Tasks 5/7.
- Touch `release/seed/` **only if** `lib/`/`sf/src` changed since **v141** (the Task 8c std_http EOF-flush rotation; expected none after Task 8c).

- [ ] **Step 1: full battery**

Corpus live (expect additive growth by the new stdlib fixture dirs only; T1-T3 +14 plus any T8b std_http fixtures), frozen-1124 `518eca1a…` 0 movers, goldens 5/5, 8 pins 8/8, markers 3397/39012, examples **28/28**, stdlib full + crosscheck 10/10, `check_emit_support` 8/8, `gate_win_compat.sh`, `tier_zstddecomp`, `tier_git` (2 runs each for the Wine tiers), the Task 8b synthetic large pack + `git/git` opt-in, the Task 8c abort/retry + shallow/deepen + GitHub/GitLab opt-in, `tier_gfx`/`tier_edit` sanity not required (untouched areas) — record scope in the report.

- [ ] **Step 2: docs truth-up**

QUICK_REF/README examples counts and app entries accurate; example READMEs match shipped CLIs (commands, flags `--arena-mb`/`--depth`/`--deepen`/`--partial`/`--max-down`, exit codes, transports table incl. GitHub/GitLab smart HTTP, resume state, arena, disk/pack/object limits, trust store, public-only, LFS out, and the `-h` usage for `z9git`/`z9zstddecomp`).

- [ ] **Step 3: seed decision + commits**

If `git diff --stat v141-rotation..HEAD -- sf/src lib` is non-empty → rotate and verify closure; else record "no lib change, no rotation" in the report. Commit `docs(…)` (and `chore(seed): rotate v142 …` only if rotation ran).

- [ ] **Step 4: hand back for final review**

Hand back to the controller; Task 10 (TLS demo HTTPS POST closing enhancement) follows, then the final whole-branch review over the full milestone range with the deferred-minor list from the task reports; fix wave only for Critical/Important. The follow-on milestones (3.3 HTTP/2, then 3.5 compiler) are separate plans/specs — see the follow-on section below.

---

## Closing enhancement

### Task 10: `tls_demo` HTTPS POST mode

**Files:**
- Modify: `examples/z98/demo/tls_demo/main.zig`
- Modify: `examples/z98/demo/tls_demo/README.md`
- Modify: `examples/z98/demo/tls_demo/tests/tier_tls.sh`
- Create: `examples/z98/demo/tls_demo/tests/https_echo.py` (python3 HTTPS POST echo server for the hermetic case)

**Interfaces:**
- Consumes: `std_http.httpPostOver(arena, t, url, body, content_type, accept, out)` (Task 3); the demo's existing `openTls`/`Conn` `HttpTransport` (`main.zig:628-633`), `loadStore`, `printStatus`, `printBody`, `printResource`.
- Produces: demo CLI:
  - `tls_demo [url] [store] [clock_override_unix]` — existing GET form, unchanged.
  - `tls_demo --post <url> --body <file> [--content-type <ct>] [--accept <a>] [--store <path>] [--clock <unix>]` — POST; body file read into the arena (cap 1 MiB); empty content-type/accept omit the header.
  - `-h` / `--help` — usage, rc 0; bad args rc 1.

- [ ] **Step 1: failing tier cases (RED)**

Extend `tests/tier_tls.sh`: `-h` rc 0; bad POST args rc 1; a hermetic HTTPS POST against `tests/https_echo.py` (python3 `HTTPServer` + `ssl.SSLContext` using the committed `tests/certs/localhost.pem`/`.key`; `do_POST` echoes the request body) asserting status, the echoed body bytes, and `bytes`; keep the existing GET/local/Win9x cases green. RED: `--post` is not recognized.

- [ ] **Step 2: implement the POST mode**

In `main.zig`: keep the positional GET path; add a small flag parser for `--post`, `--body`, `--content-type`, `--accept`, `--store`, `--clock`, `-h/--help`. Read the body file into the arena (reject >1 MiB with a clear bad-args error); after `openTls`/`loadStore`, build the same `HttpTransport` and call `httpPostOver` (NOT the redirect-following `post` convenience), then print the same status/body/resource lines. No redirect following (documented, matches GET). No `std_*`/compiler changes.

- [ ] **Step 3: README + limits**

Add the POST form, the 1 MiB body cap and 1 MiB buffered-response cap, and the no-redirect / no-custom-header / no-gzip caveats; fix the stale Win9x `1790000000` clock example (system clock is the default; the override is only for a dead RTC); note the streaming variant is not used by the demo (it is exercised by `z9git`, Task 8).

- [ ] **Step 4: verify + commit**

`bash examples/z98/demo/tls_demo/tests/tier_tls.sh` (local GET + POST cases; the existing `check_win9x_imports.sh … 9x` stays green — no new imports expected; if a new import appears, STOP and present the whitelist delta); `git diff --check`. No seed rotation, no battery (T9 already ran; this is example-only and the examples matrix stays 28/28). Commit:

```bash
git add examples/z98/demo/tls_demo/main.zig examples/z98/demo/tls_demo/README.md examples/z98/demo/tls_demo/tests/tier_tls.sh examples/z98/demo/tls_demo/tests/https_echo.py
git commit -m "example(tls_demo): HTTPS POST mode with hermetic echo tier"
```

This is the last task of this plan; the final whole-branch review runs after it.

---

### Task 11: z9torr post-plan optimization (example) — before 3.3 HTTP/2

**Position:** after Task 10; before the 3.3 HTTP/2 follow-on. This is a post-plan
example optimization. Do not start 3.3 until this task is complete or explicitly
deferred.

**Files:** `examples/z98/z9torr/{piece.zig,peer.zig,scheduler.zig,wire.zig,main.zig,resume.zig,README.md}`
and the relevant `tests/*`; `sf/src/std_crypto.zig` only if the MSE `modpow`
step is separately approved.

**Objective:** remove z9torr's measured hot paths, not speculative ones. The
committed std SHA-1 optimization already speeds piece verification, resume
rehash and MSE key derivation.

- [ ] **Step 0: baseline profile**
  Build `-ffast`; use a large local torrent (512 MiB–1 GiB; 256 KiB and 1 MiB
  piece lengths) with 1 and 16 mock peers, plaintext and MSE. Record wall/CPU/
  peak RSS and a phase breakdown: startup rehash, MSE DH, `pickPiece`,
  `saveResume`, SHA-1 verify, disk write-through, stats loop. Use
  callgrind/gprof when available. Record the output-file SHA-1.

- [ ] **Step 1: bounded piece verification (recorded defect)**
  `piece.onBlock` allocates the whole piece from the 1 MiB `work_arena`
  (`main.zig:49`, `piece.zig:181`) while `MAX_PIECE_LENGTH` is 16 MiB
  (`torrent.zig:48`). Fix by reading/hashing the piece in fixed bounded chunks
  (16 KiB or the existing block size) so no full-piece allocation is needed.
  Keep the exact SHA-1 and output bytes. Add a targeted test with a piece
  length >1 MiB.

- [ ] **Step 2: `saveResume` constant factors**
  Keep the spec-mandated write frequency (after every written block / verified
  piece). Replace `hasReceived` scans with `received_count`; maintain an
  incremental per-piece block mask; avoid full-block scans in `fillMask`; keep
  the sidecar I/O measured and reduce open/stat/write overhead if the profile
  confirms it. Do not change resume semantics.

- [ ] **Step 3: scheduler**
  Replace the O(n_pieces) `pickPiece` scan with a deterministic rarest-first
  structure (bucket or heap keyed by `(rarest, lowest index)`), preserving the
  spec’s tie-break order. Make `release` O(1) by releasing the peer’s single
  claimed piece. Add unit tests for order, duplicate/corrupt/requeue, and
  `removePeer`.

- [ ] **Step 4: encrypted wire prefix**
  Only if the profile confirms it: batch the 4-byte frame-length read/RC4
  instead of one byte at a time, preserving stream order and deadlines.

- [x] **Step 5: MSE `modpow` decision checkpoint (STOP) — DECLINED as unneeded for z9torr**
  Before implementing, present to the operator: the current double-and-add
  `std_crypto.modpow` cost; the proposed fixed-window Montgomery or
  constant-time ladder; timing side channels on the secret DH exponent;
  unauthenticated MSE/MITM context; that modpow arithmetic itself is not an RCE
  vector (RCE risk would come from parser/memory-safety bugs, not this
  arithmetic); the Win9x demo context; and that only pure Z98 is allowed.
  Do not implement `modpow` without explicit operator approval. If approved,
  add RFC/MSE vectors, state the constant-time decision, and rotate the seed.

  **Decision (2026-11-06): declined as unneeded for z9torr.** The measured
  `modpow` cost is under 1% of the peer path, so it does not justify a
  `std_crypto` change and seed rotation for this scope. No `modpow` code was
  written, `sf/src` was not changed, and the seed was not rotated. This is a
  performance/scope decision, not a security fix: the variable-time exponent
  timing caveat and the unauthenticated-MSE/MITM caveat remain as documented;
  security hardening, if wanted, is a separate task.

- [ ] **Step 6: reprofile + tiers**
  Repeat the Step 0 profile and compare. Run the z9torr tiers
  (`tier1_unit`, `tier1`, `tier2`, `tier3_encrypted`, `tier_dht`, `tier_pex`,
  `tier_mse_diag`, `tier_stall`, `tier_fallback`, Win9x as applicable) with
  unchanged output SHA-1; `git diff --check`.

- [ ] **Step 7: commits**
  Example-only commits for Steps 1–4. Step 5 was declined, so there is no
  `sf/src/std_crypto.zig` commit and no seed rotation. Then **STOP**;
  3.3 HTTP/2 is the next separate planning session.

## Follow-on milestones (after this plan)

### 3.3 — HTTP/2 client (separate plan/spec; planning session next)

The HTTP/1.1 client is sufficient for GitHub/GitLab; HTTP/2 is deferred to 3.3. The 3.3 planning session must produce a plan/spec covering what std needs:

- `std_tls`: ALPN in the ClientHello/`TlsConfig` (offer `h2`, fall back to `http/1.1`; selected-protocol plumbing; TLS 1.2/1.3).
- `std_http` HTTP/2: connection preface; SETTINGS/ACK; frames (HEADERS, CONTINUATION, DATA, RST_STREAM, WINDOW_UPDATE, GOAWAY, PING); stream states; connection/stream flow control; max frame/header-list sizes; GOAWAY; connection reuse/multiplexing mapped onto the existing `HttpTransport`/`Response`/`ResponseSink`.
- HPACK: static and dynamic tables + eviction; Huffman encode/decode; integer/string representations; indexing; `SETTINGS_HEADER_TABLE_SIZE`; max header list; never-indexed.
- Server push/priority: ignored.
- API/backward compatibility: HTTP/1.1 remains the default/fallback; the streaming GET/POST APIs work over either; callers unchanged.
- Tests: a local h2 server over TLS with ALPN (python `h2`/nghttp2 or the dev equivalent), flow-control/header/GOAWAY/RST cases, GitHub/GitLab opt-in h2, fallback-to-1.1; a separate seed when std lands.
- This section is the input to that planning session; the 3.3 plan/spec is written there, not here.

### 3.5 — compiler improvements

The existing `docs/superpowers/plans/2026-10-29-phase35-defects-plan.md` remains the compiler-improvement plan; it runs after 3.3. Nothing in this Phase 3 plan changes its scope.

### Order

Phase 3 (this plan, incl. Task 11 z9torr post-plan optimization) → **3.3 HTTP/2** → **3.5 compiler improvements**.

---

## Appendix — Task 8p results, T8b WIP, and resume state (2026-11-05)

### Task 8p — PASS WITH CHANGES (measure-only; commit `4794a5a2`)
Repo `jwiegley/git-from-the-bottom-up`, GitHub 1203 KB, pack 1,237,697 B, 328 objects, HEAD `02d22a0`; app `-ffast` only (no `-fsafe`), callgrind/gprof/valgrind.

- HTTPS: app **3.14 s / 8.7 MB** vs system git **0.99 s / 17.4 MB**; app RX **1.27–1.29 MB** = system 1.27 MB (network is not the bottleneck).
- Local: app **0.28 s / 5.6 MB** vs system **0.01 s / 5.8 MB**.
- CPU: HTTPS **AES-GCM/GHASH ~80%** (`ghashMulX` 50.7%, `ghashMulX4` 20.2%, `ghashMulH` 8.1%); local **SHA-1 ~72%** (`sha1Block` 29.5%, `rotl32` 22.6%, `mask` 14.1%).
- Phases: TLS 0.42 s, refs install **0.11–0.30 s** (report said `<1 ms`), pack 2.0 s, idx 0.37–0.56 s, checkout 0.31–0.55 s.
- RAM: 1 MiB `std_http` + 1 MiB pack window; checkout arena +2.55 MB local / +3.62 MB HTTPS.
- Over-fetch: app fetches every advertised ref incl. `refs/pull/*` → **382 vs 328 objects** (+16%, +16.9 KB).
- Caveat: app built `-O0`; no `-O2` measurement.

**Task 8p fix subtask (review's PASS WITH CHANGES):** correct the refs-install number; pin `SRC`/`COMMIT` + clean-tree in `profile_small.sh`; medians in-script or state post-processed; gprof provenance; ECC label; memcheck gate (`|| true` currently swallows); automate pack/idx/object/HEAD/verify-pack facts; remove the "reproduces all" overstatement.

### Task 8b — fix scope (item 1 `-O2` DISCARDED)
**Discarded `-O2`** (operator): real-world apps build with **OWC/MSVC**; a gcc `-O2` proposal delays items 2–8, which are the real cure.

**Items 2–8 (data-backed; priority order):**
2. **GHASH table-driven** (`std_cipher` AES-GCM / `std_tls`) — 80% HTTPS CPU; affects every TLS program; **seed v139**.
3. **SHA-1** (`std_crypto`) — 72% local CPU; affects every program using SHA-1; **seed v139**.
4. **O(objects) streaming checkout** (`objects.zig`/`repo.zig`) — per-file scratch/bounded cache/`storeReadTo`; removes the 40 MB blow-up.
5. **`refs/pull/*` filter** (`httpgit.zig`) — stop the 382-vs-328 over-fetch.
6. **Bounded idx reader** (`pack.zig`) — file-backed `Idx`, fanout resident only.
7. **Whole-pack SHA-1 at store open** (`pack.zig`/`objects.zig`) — stream it, don't block.
8. **1 MiB buffer sizing** (`std_http`/`pack`) — size to the stream.

Plus the T8b remaining: symlink/gitlink policy, Content-Length preflight.

**Testing:** the T8p harness vs system git/curl; `tier_git.sh`; 100k synthetic; melonDS real HTTPS (`Z98_NET=1`); `git verify-pack`/`fsck`; Win9x no-CRT/`9x`; targeted `stdlib_http_*` + crosscheck; `-ffast` for work, `-fsafe` only for measurement/OOB-UB; re-profile after the fixes; **seed v139** (std GHASH/SHA-1).

### Current T8b uncommitted work (keep; do not discard)
HEAD `4794a5a2`; base `1442f8ad`. The T8b WIP is **uncommitted in the main worktree** and was **not** measured by Task 8p (which used a detached `1442f8ad`). `git status`/`git diff --stat`:

- `examples/z98/z9git/pack.zig` **+422/−**: file-backed `Idx` (fanout in memory; names/CRC/offset read via `readAt`), `idxLoad`/`packOpen` out-params, `readEntryBig`/`dynAlloc`/`dynFree`, `Inflated.big`/`RawEntry.big`, big-delta path, `idxSynthesize` big.
- `examples/z98/z9git/objects.zig` **+75**: `storeReadTo`, `cache_buf` slices, `Resolved.big`, cache/resolve changes.
- `examples/z98/z9git/repo.zig` **+225**: `diskPreflightEstimate`, gitlink-aware `preflightTree`/`removeAbsent`, `parseTreeCopy`, `writeLink` (POSIX symlink; Windows regular file with target text), gitlink empty dir, `materializeTree` scratch + `writeObjectToFile` streaming, `checkoutScratchAlloc`, scratch in `cloneLocal`/`checkoutHead`/`checkoutRef`.
- `examples/z98/z9git/httpgit.zig` **+77**: inspect on resume (likely Content-Length preflight/streaming sink integration).
- `examples/z98/z9git/tests/tier_git.sh` **+157**: `-ffast` work build + `-fsafe` measurement build; 128 MiB RSS bound; 100k `-fsafe`; melonDS real HTTPS (`Z98_NET=1`, 1800 s, verify-pack/fsck/HEAD/worktree, `-fsafe` RSS).

**Next session rule:** inspect the WIP (`git diff`), build, run the tier/Win9x/verify-pack, keep/complete/commit it; **do not discard**. Re-run the profile on the WIP; the base `1442f8ad` numbers are not the WIP.

### T8-post-opt — std-lib best-in-class portable-C optimization (mandatory before resuming git)

**Authorization:** operator 2026-11-05. These tasks run before the remaining T8b/git work.

**Purity / target constraints (binding):**
- Pure Z98 only: no `@cInclude`, no `extern` C-library calls, no `@cImport`, no inline assembly, no compiler intrinsics (`__builtin_*`, `_rotr64`, `bswap`), no C macros.
- Manual source-level unrolling and file-scope `const` tables are allowed.
- Target is best portable C89 on 32-bit x86 without AES-NI/SHA-NI/PCLMUL/SSE4.2. Absolute asm/SOTA is not expressible under Z98 purity; “best” means best pure-Z98 portable C against OpenSSL/zlib/reference algorithms translated to Z98.
- `-ffast` for the runtime benchmark; `-fsafe` for correctness/default-mode runs. Rotations must pre-mask for `-fsafe`.
- No z9git/tier_git re-measurement in these tasks.

**Precondition:** inspect and commit the correct T8b WIP first. No git re-measure.

#### T8-post-opt-A1 — SHA-512/384 + CRC32
- Modify: `sf/src/std_crypto.zig` only.
- Baseline: seed build; targeted fixtures `stdlib_hash_sha384_512_xmod`, `stdlib_crypto_crc32_xmod`, plus `stdlib_x509_parse_xmod`, `stdlib_rsa_verify_xmod` and the hash/crypto regression set; temporary pure-Z98 benchmark; 5-run median wall time.
- Implement: OpenSSL-style SHA-512 16-word circular schedule + 16-round blocks, static `K512`, pure byte-assembled input loads; zlib-style braided CRC-32 (Kadatch–Jenkins) with a fixed N/W bake-off, W=4, static tables.
- Verify: same fixtures; post median must be below pre median with a real measured reduction; inspect emitted C; `-fsafe` correctness; `git diff --check`.
- Commit: `perf(std): optimize SHA-512/384 and CRC32` (only `std_crypto.zig`).

#### T8-post-opt-A2 — deflate + adler32
- Modify: `sf/src/std_deflate.zig` only.
- Baseline: all seven `stdlib_deflate_*` fixtures; temporary benchmark repeated inflate; 5-run median.
- Implement: zlib-style Adler-32 (`NMAX=5552`, 16-byte unroll, deferred modulo); 32-bit `bFill` refill path when ≥4 input bytes remain; keep the 32K decode table.
- Verify: all deflate fixtures; post median lower than pre; inspect emitted C; `-fsafe`; `git diff --check`.
- Commit: `perf(std): speed up deflate and adler32` (only `std_deflate.zig`).

#### T8-post-opt-B — remaining safe hash/cipher wave
- Modify: `sf/src/std_crypto.zig` and `sf/src/std_cipher.zig`.
- SHA-256: 16-word circular schedule + 16-round blocks + static K.
- BLAKE2s: manually unrolled reference G/ROUND (10 rounds) + static sigma/IV.
- ChaCha20: manually unrolled QR/double-round (20 rounds) + constant pre-masked rotations.
- MD5: unrolled 64 rounds + static K/shift tables, only if its benchmark is not flat.
- Verify: `stdlib_crypto_sha256_xmod`, `stdlib_crypto_md5_xmod`, `stdlib_crypto_prf_xmod`, `stdlib_chacha_poly_xmod`, `stdlib_wireguard_cross_xmod`, `stdlib_tls_record_xmod`, `stdlib_crypto_stress_xmod`; per-algorithm 5-run benchmarks; require measured reductions; `-fsafe`; `git diff --check`.
- Commit per logical group (hash wave; ChaCha wave) or one `perf(std): optimize SHA-256, BLAKE2s and ChaCha20`.

#### T8-post-opt final gate
After A1, A2, and B: full `verify_stdlib` + crosscheck 10/10 + `examples/z98/demo/wireguard_demo/tests/tier_wireguard.sh` + `examples/z98/demo/tls_demo/tests/tier_tls.sh` + seed **v140** rotation. Only then resume the T8b/git work.

**Not authorized:** T8-post-opt-C (SHA-1/GHASH v2) unless the operator explicitly adds it.

**Updated resume order:** 0) commit correct T8b WIP; 1) T8-post-opt-A1; 2) A2; 3) B; 4) final gate + seed v140; then the existing next-steps list below (with the git re-profile/8p/remaining T8b after the authorized post-opt work).

### Task 8b fix round 1b — P0/P1 before whole-task re-review (operator 2026-11-05)

**Position:** after `a4671f89` (fix round 1) and before the Task 8b whole-task
scoped re-review. P2/P3 are deferred; do not implement them in this round.

**Files:**
- Modify: `examples/z98/z9git/{repo.zig,objects.zig,pack.zig,httpgit.zig,README.md}`,
  `examples/z98/z9git/tests/tier_git.sh` (+ `unit_store.sh` only if a unit case is
  the right coverage).
- No std/compiler/seed changes; no measured git re-profile.

**P0 (must fix in this round):**

1. **`copyFile` per-file 64 KiB arena growth.** `repo.zig:345-367` allocates a
   64 KiB buffer from the passed arena for every file; `copyLoose`
   (`repo.zig:605-634`) and `copyTree` (`repo.zig:637-651`) call it per loose
   object/ref and never reset it. Use one static/reused buffer or a per-copy
   scratch so a local clone of many loose objects/refs is O(1) buffer memory,
   not O(files) arena growth. Add a tier case with 4,000 loose objects (and many
   refs) at `--arena-mb 32`; no OOM, correct bytes.

2. **Big loose-object mapping ownership.** `objects.zig:569-581` marks the body
   slice `big`, but `objects.zig:78-82` `freeTyped` and `storeReadTo` free from
   that slice; `pack.zig:51-57` `dynFree` needs the original mapping
   base/length. Track the base/length (or return a full mapping plus payload
   offset) and free exactly once. Add a case with multiple large loose objects;
   check no address-space/pagefile growth.

**P1 (must fix in this round; P2/P3 deferred):**

3. **Checkout scratch cap.** `repo.zig:1059-1063` allocates
   `arena.capacity` (8–64 MiB) as checkout scratch. Use a fixed 8 MiB or
   `min(8 MiB, arena.capacity/2)`; retest the 4k/deep-tree case and the 100k
   synthetic at 32 MiB. Record peak RSS.

4. **Periodic free-space guard for HTTP pack download.** `httpgit.zig:743-761`
   passes `pack_bytes=0` when `Content-Length` is absent; a chunked pack can
   pass preflight and fill the disk. Check free space every N MiB written
   (1–8 MiB; small enough for 32/64 MB) against the current pack estimate +
   idx/temp/worktree + slack; return `DiskFull` rc5 and remove temp pack/idx.
   Add a no-`Content-Length`/chunked mock case; no final pack without idx.

5. **Local loose-object preflight.** `copyLoose` (`repo.zig:605-634`) has no
   preflight and streams every loose object. Sum loose sizes before copy or
   check free space per file; map a full disk to the existing rc5 path without
   leaving a partial clone if practical. Add a focused case or deterministic
   check.

6. **Windows file-backed large-object/delta-base mapping.** Replace the
   `VirtualAlloc`-only fallback in `pack.zig:60-64` with a
   `CreateFileMappingA`/`MapViewOfFile` temp-file mapping where available,
   falling back to `VirtualAlloc` on failure. The plan requires file-backed
   bases; Win9x supports file mapping. If this needs a new
   `check_win9x_imports.sh` whitelist entry, STOP and present the delta
   (Global Constraints: closed-world whitelist). Test under Wine/Win9x.

**Verification:** seed v140 compile+link; `unit_store.sh`; full `tier_git.sh`;
focused P0/P1 cases; Win9x no-CRT/`9x` + Wine; `git diff --check`. Do not run a
measured git re-profile (operator constraint); use the existing Task 8p
numbers.

**Commit(s):** new commits, no amend:
- `fix(z9git): bound loose copy and mapping ownership`
- `perf(z9git): cap checkout scratch and guard pack downloads`
- `feat(z9git): file-backed large-object mapping on Windows`
(or a single cohesive `fix(z9git): ...`; do not mix P2/P3).

**Then:** scoped re-review from `e27399ac` (the head the previous review saw)
over the three Important findings plus these P0/P1 items. Do not re-review
P2/P3 or unrelated code.

### Next steps (resume order)
1. Inspect + test + commit the T8b WIP (5 files; `tier_git.sh`; 9x; `Z98_NET=1` melonDS; review).
2. Task 8p harness/report fixes.
3. Task 8b items 2–8 + the remaining; seed v139 for the std GHASH/SHA-1.
4. Re-profile (same build; small repo; system baseline) to prove the gain.
5. Task 8b fix round 1b (P0/P1) then the whole-task scoped re-review from `e27399ac`.
6. Task 8c (resumable/shallow/partial/GitHub-GitLab/state).
7. Task 9 (full battery; examples 28; docs; seed since v139).
8. Task 10 (tls_demo POST).
9. Final whole-branch review; then 3.3 HTTP/2 planning; then 3.5.

### State / files
- HEAD `4794a5a2`; T8b core `1442f8ad`; seed **v138** (`cf68f192…`; archive `9aef8a6a…`; zip `067fb8f…`; lib 52; manifest `df2a1196…`).
- Plan: `docs/superpowers/plans/2026-11-04-phase3-missing-libraries-plan.md` (untracked); spec: `docs/superpowers/specs/2026-11-04-phase3-missing-libraries-design.md` (untracked); SDD `.superpowers/sdd/2026-11-04-phase3-missing-libraries-plan/`.
- Untracked: the plan/spec, `lin_bin/`, the other plans. Modified: the T8b WIP (5 files), `task-4-report.md`, `2026-10-29-phase35-defects-plan.md`, `2026-10-24-phase2-toolchain-design.md`.
- Memory: the Task 8p intent/decision entries; the WIP/next steps.
