# Phase 3 — Missing Libraries: zstd full RFC 8878 + read-only Git client — design

**Status:** approved 2026-11-04 by the operator (brainstorming + builder check complete).
**Plan:** `docs/superpowers/plans/2026-11-04-phase3-missing-libraries-plan.md`.

## Intent / why

Roadmap Phase 3 (`examples/roadmap.txt`, `examples/projects_phase3.txt`) supplies the two
library capabilities the Win98 ecosystem lacks and the Phase 5 D3D game needs: zstd
decompression for asset pipelines (Win98 tools cannot read `.zst`) and a read-only Git
client to fetch source/deps. Operator bar: **Project 5 = full RFC 8878** (the current
`std_zstd` is a subset — dictionaries are rejected). Work is split so shared std
foundations land first (Milestone 1) and the apps (Milestone 2) are thin consumers.

## State today (audit; supersedes the blueprint's stale claims)

- `sf/src/std_zstd.zig` (1203 lines): RFC 8878 frame decoder subset — raw/RLE/compressed
  blocks, predefined/RLE/FSE-compressed Huffman tables, 4-stream literals, FSE sequence
  tables, repeat modes, skippable frames, XXH64 content-checksum verification
  (`std_zstd.zig:1166`). Single-shot `zstdDecompress(src, dst, max_window_log) !u32`, no
  heap, history lives in `dst`. **Only gap vs full RFC 8878: dictionaries** (nonzero
  dictionary id → `error.Corrupt`).
- `sf/src/std_crypto.zig`: SHA-1/SHA-256/MD5/CRC32/RC4 present (Git object ids covered).
- `sf/src/std_tls.zig` + `std_x509.zig`: TLS 1.2/1.3 client with TrustStore certificate
  verification (HTTPS covered).
- `sf/src/std_http.zig`: GET-only over a caller-supplied mockable `HttpTransport`
  (read/write/close fn pointers), HTTP/1.1 `Connection: close`, identity + chunked response
  bodies, whole-body arena buffering with a 1 MiB hard cap (`std_http.zig:28`).
  **Gaps: POST; a streaming response sink.**
- **No deflate/zlib inflate anywhere** (`grep -ri deflate sf/src` empty). Git objects are
  zlib-compressed; zero shared code with zstd (the blueprint is correct here).
- House style: flat `std_*.zig` modules; L4 modules imported by path, not added to the
  `std.zig` barrel (so fixed point and 8 pins stay unmoved).
- Fixture tooling in the dev environment: system **libzstd 1.5.4** (headers + libs, for
  generating `.zst` fixtures incl. dictionary compression via a small gcc C helper), real
  **git 2.39** (for generating pack/idx fixtures and `git verify-pack` checks), python3,
  gcc. No `zstd` CLI.

## Goals

### Milestone 1 — std foundations (targeted std fixtures per task; full std battery at closeout)

1. **`std_zstd` dictionary support → full RFC 8878.** Parse the RFC 8878 §5.2 dictionary
   format (magic `0xEC30A437`, dictionary id, Huffman + FSE entropy tables, dictionary
   content). Semantics:
   - a frame's `Dictionary_ID` 0 means any dict; nonzero must equal the supplied dict's id,
     else `error.Corrupt`;
   - the dict's entropy tables become the initial tables — first-block `Repeat` mode
     resolves to dict tables when a dict is attached, else predefined tables;
   - dict content pre-seeds the history window — match offsets may reference the last
     `min(dict.len, window_size)` bytes of dict content before the frame start;
   - raw-content dictionaries (no header/id) are also accepted; they apply to
     dict-id-0 frames only;
   - frames with a nonzero dict id and no dict supplied stay `error.Corrupt` from the
     no-dict entry.
   API is additive: `zstdDecompress` unchanged (still rejects dict frames);
   `zstdDecompressDict(src: []const u8, dst: []u8, dict: []const u8, max_window_log: u8) !u32`.
   Encoder stays out of scope.
2. **`std_deflate` (new module, flat, path-imported).** Decompression only (read-only Git
   never compresses). RFC 1950 zlib wrapper (CMF/FLG validation incl. FCHECK, Adler-32
   verification) + RFC 1951 raw DEFLATE (stored/fixed/dynamic-Huffman blocks,
   length/distance codes, 32 KiB window, overlapping match copies byte-by-byte). `FDICT`
   preset-dictionary zlib streams → `error.Corrupt` (Git never emits them). No heap;
   caller-provided `dst`; internal fixed decode tables (single-level, same pattern as
   `std_zstd`). API: `inflateRaw(src: []const u8, dst: []u8, used: *usize) !u32` and
   `inflateZlib(src: []const u8, dst: []u8, used: *usize) !u32`. The `used` out-param is
   mandatory: pack idx synthesis needs zlib stream extents.
3. **`std_http` POST + streaming sink.**
   - `httpPostOver(arena, t, url, body, content_type, accept, out: *Response) !void`
     mirroring `httpGetOver` (same transport, `Connection: close`, identity + chunked
     response bodies, existing 1 MiB whole-body cap); empty `content_type`/`accept` →
     header omitted. Plus convenience `post(arena, url, body, content_type, accept, timeout_ms)`.
   - Streaming variant `httpPostStreamOver(arena, t, url, body, content_type, accept,
     sink, out_head) !void`: response **headers** land in `out_head` (body empty); the
     de-chunked body flows to a caller sink callback in bounded ~1 MiB chunks (fixed
     stream buffer; hardware is the cap). Needed by git-upload-pack negotiation and pack
     download (custom media types `application/x-git-upload-pack-request` / `-result`).

M1 gates: per task, new stdlib fixture dirs in `scripts/stdlib/expected_dirs.txt`
(`stdlib_zstd_dict_*`, `stdlib_deflate_*`, `stdlib_http_post_*`) run through
`verify_stdlib.sh`; at M1 closeout the **full std battery** (`verify_stdlib` +
`run_crosscheck`), 8 pins (expected unmoved — no barrel/interner change),
`check_emit_support.sh` 8/8, and seed rotation **v136** (fixed point expected unchanged;
`lib/` 51→52 with `std_deflate.zig`; `scripts/seed/build_from_seed.sh` + `archive_seed.sh`
copy lists updated).

### Milestone 2 — apps (house example pattern: `examples/z98/<name>/`, README + `tests/tier_*.sh` + committed fixtures; `-osw`/MinGW+Wine smoke tier for each)

4. **`z9zstddecomp`** — CLI decompressor for `.zst` on Win98.
   `z9zstddecomp <in.zst> <out> [--dict <file>] [--max-window-log <n>]`, `-h` help,
   documented exit codes. Exercises the full-RFC decoder incl. dictionaries. Tier
   `tests/tier_zstddecomp.sh` with committed `.zst` fixtures (generated at dev time with a
   libzstd helper: plain, 4-stream, RLE, skippable, checksum on/off, magic dict, raw dict,
   dict-id mismatch, corrupt/truncated).
5. **`z9git`** — read-only Git client. v1 commands: `z9git clone <url> [dir]
   [--max-down <KB/s>]`, `z9git log [ref]`, `z9git checkout <ref>`. Transports: `https://`
   (smart HTTP v0 over `std_tls` + `std_http`) and local path/`file://` (hermetic tests).
   `git://` and ssh: out of scope. Object store: pack v2 parse (varint type/size header,
   OFS_DELTA/REF_DELTA), idx v2 parse (fanout binary search, CRC32 table stride skip,
   31-bit offsets + large-offset table) **plus loose-object fallback**
   (`.git/objects/xx/yyyy…`, inflate + SHA-1 verify; REF_DELTA resolves across pack and
   loose) — everyday repos work, nobody is asked to run `git gc`. `clone` writes a
   git-compatible `.git` (packs, **loose objects copied verbatim**, refs, HEAD) and a
   worktree of HEAD; packs arriving over HTTP are **streamed to disk** and the `*.idx`
   synthesized (offsets + per-entry CRC32 via `used`). `log` = commit DAG walk (parents,
   author, subject). `checkout` = tree materialization. Delta reconstruction with a fixed
   memoized base cache (arena-bounded). Smart HTTP v0: GET
   `info/refs?service=git-upload-pack` (pkt-line ref discovery + capabilities), POST
   `git-upload-pack` with want/have pkt-lines and `done`; v1 does not enable sideband;
   response = ACK/NAK pkt-lines then the PACK stream. Sliding 1–4 MiB pack window via
   `std_file` seek/read. Download verification = pack SHA-1 trailer hashed on the stream,
   Adler-32 per object inside inflate, SHA-1 per object on materialize. pkt-line helpers
   live in the app (not std). `--max-down <KB/s>` paces the download (z9torr-style token
   pacing between chunks). Tier `tests/tier_git.sh`: committed fixture repos (generated at
   dev time with real `git init/commit/gc`, **plus one loose-object repo without gc**),
   local-path clone + log + checkout goldens; HTTPS covered by mocked-transport unit cases
   and a local smart-HTTP end-to-end case when `git http-backend` is available
   (skippable, never vacuous), plus an optional operator-run real clone.

M2 closeout: full battery with the **examples matrix 26→28** anchor updated, all tiers
green, docs (example READMEs + QUICK_REF + relevant manual pages), seed rotation only if
`lib/`/`sf/src` changed (apps alone do not force one).

### M2 extension — real GitHub/GitLab clones (T8b/T8c)

The v1 smart-HTTP client is fine for small/medium repos; real GitHub/GitLab use requires:

- **Bounded memory:** external-memory idx synthesis (two-pass pack walk, temp
  `(id, offset, crc)` records, external merge, streamed idx writer, per-entry object
  hashing, bounded base cache); `z9git --arena-mb` default **32**, min **16**, **no hard
  upper bound**, dynamically allocated (the OS may page), reset at phase boundaries;
  streaming object/checkout; file-backed base fallback for huge deltas; disk preflight
  (HTTP `Content-Length` when present, otherwise the PACK object count → free-space check)
  with specific errors; document Win9x/FAT32 2–4 GB and Linux 2.0/ext2 ~2 GB; POSIX
  `std_file` is 64-bit.
- **Resumable:** shallow/deepen (`--depth`, `fetch --deepen`, `.git/shallow`); partial
  clone `filter=blob:none` (GitHub) for the tip tree; prefix-pack + `have` fallback for a
  full-history pack; `.git/z9git-state`; re-running clone/fetch resumes; abort/retry tests.
- **GitHub/GitLab conformance:** standard smart HTTP v0 over HTTPS; redirects/`.git`; TLS
  trust store including both CAs; chunked; no sideband/thin-pack/gzip; `ofs-delta`; public
  repos only; the GitLab **git** endpoint is not Anubis-blocked (the web/API is); LFS out.
- **Sizes:** `git/git` full (324 MB repo) must-work; graphics Mesa (GitLab; ~1–2 GiB
  estimate, operator-measured) large; Linux kernel (6.45 GiB repo; ~5 GiB pack)
  shallow/partial on modem/old machines, full only on modern Linux; DeepSeek-V3 code
  (1.7 MiB) tiny and its Hugging Face LFS weights out; CI synthetic 50k–100k objects.
- **README/`-h`:** commands, flags, transports, exit codes, resume, arena, limits, trust
  store, public-only, LFS out.

M2 closeout (Task 9) follows T8b/T8c; Task 10 follows T9; the final whole-branch review
runs after T10; then the follow-on milestones below.

## Non-goals

zstd encoder; deflate compressor; git write operations (add/commit/push); `git://`/ssh
transports; delta *creation*; sideband/multi_ack_detailed negotiation; full `.git` index
file; credential helpers; GUI; LFS; private-repo auth (public only for now); HTTP/2
(milestone 3.3).

## Anti-goals

No compiler-pipeline changes; no `std.zig` barrel changes (path imports only); no heap/GC
on decode paths; no new diagnostic codes; nothing that MSVC 6 / OpenWatcom cannot compile
(Win9x tier must stay green); no corpus/gate edits beyond `expected_dirs.txt` fixture
additions and the examples-matrix count bump.

## Constraints

Z98 subset syntax (no generics/`anytype`; `for`-captures; `switch`; error unions;
module-level zero/BSS); C89 emission; 32-bit Win98 + Linux; arena/caller-buffer memory
discipline (fixed tables, no allocation on decode paths); house tool rules (edit/fastedit,
sequential zig1, STOP-on-ambiguity); battery anchors (frozen-1124 corpus md5
`518eca1a9b5d3e1cc5a48abce214abd8`, 8 pins, goldens, markers) must stay unmoved.

- **Arena:** `z9git --arena-mb` default 32, min 16, **no hard upper bound**; dynamically
  allocated (the OS may page); reset at phase boundaries; spill/stream to disk; a clear
  allocation-failure error; the README/`-h` documents it.
- **Large repos:** external-memory idx; streaming object/checkout; disk preflight; no
  O(pack) arrays; document the Win9x/FAT32 and Linux 2.0/ext2 limits; POSIX `std_file` is
  64-bit.
- **Transports:** GitHub/GitLab standard smart HTTP v0 over HTTPS; public; redirects; TLS
  trust incl. both CAs; shallow/deepen; partial `filter=blob:none`; prefix/`have` resume;
  `git://`/ssh/LFS/private out.
- **Follow-on:** 3.3 HTTP/2 then 3.5; HTTP/2 is not in this milestone.

## Approaches (decided)

- **One plan, two milestones** (M1 std foundations → M2 apps) — operator's choice over two
  separate plans or a git-first order: shared std first; small targeted std battery per std
  task; full std battery at M1 closeout.
- **Deflate bit-reader stays internal** to `std_deflate` rather than a shared `std_bits`
  streaming reader — zstd reads its bitstream backwards, deflate forwards; sharing would be
  a forced abstraction. `std_bits` keeps its bit-twiddling role.
- **Dict API additive** (second entry point) rather than widening `zstdDecompress`'s
  signature — existing callers unchanged.
- **Pack download = streaming to disk** (operator Q1 answer (b)): bounded buffer, chunked
  tee into `objects/pack/*.pack`, verification hashes on the flow, hardware as the cap;
  mirrors z9torr's not-all-in-RAM download style.
- **Loose objects fully supported** (operator Q2 answer (b)): asking a maintainer to run
  `git gc` is not acceptable; loose read fallback + verbatim copy is in v1 scope.
- **Names/locations** fixed by operator: `examples/z98/z9git`, `examples/z98/z9zstddecomp`.
- **Large repos = bounded memory, not a bigger arena:** external-memory idx + streaming;
  `--arena-mb` default 32/min 16/no hard max; the OS pages.
- **Resume = protocol-level, not byte ranges:** GitHub has no POST Range; shallow/deepen +
  partial `filter=blob:none` primary; prefix + `have` fallback; dumb-HTTP Range only for
  self-hosted static servers (not GitHub).
- **HTTP/2 = milestone 3.3:** not in this milestone; the std HTTP/2 requirements are in the
  follow-on section.
- **GitHub/GitLab standard:** the GitLab **git** endpoint is not Anubis-blocked; the
  web/API is; the Mesa size is operator-measured.

## Operator-settled calls (approved; recorded for traceability)

- `inflateRaw/inflateZlib(src, dst, used: *usize) !u32` — clone must synthesize `*.idx`
  (CRC32 + entry offsets) and zlib streams are not self-delimiting.
- `--dict` accepts **both** RFC 8878 magic dicts and raw-content dicts (magic-priority;
  raw dict ⇒ dict-id-0 frames only).
- Both apps get `-osw`/MinGW+Wine smoke tiers (they exist for Win98).
- `--max-down <KB/s>` pacing flag on `z9git clone` (z9torr-style).
- ~1 MiB streaming chunk buffer in `std_http`'s sink path.
- **Public GitHub/GitLab only** for now; private auth and LFS are out.
- **Shallow/deepen + partial clone** (`filter=blob:none`) are in scope, with the
  prefix/`have` fallback; the resume state is `.git/z9git-state`.
- **Arena:** `--arena-mb` default 32, min 16, no hard max; dynamic; the OS may page.
- **HTTP/2 deferred to 3.3; 3.5 compiler follows.**
- **The GitLab Mesa is the official graphics repo** (`gitlab.freedesktop.org/mesa/mesa`);
  the GitHub `mesa/mesa` is a different Python library; the Mesa size is operator-measured
  (the GitLab API is Anubis-blocked, the git endpoint is not).
- **The client README/`-h` documents the full usage and limits.**

## Left to the builder

Exact table struct layouts for dict/deflate decode tables; fixture corpus contents and
their generator scripts; tier case counts; exact pkt-line helper shape; per-module
error-enum spelling; README/tutorial depth. The large-repo work leaves: the external-idx
temp/sort layout and chunk size; the resume-state schema; the partial-clone on-demand blob
policy; the exact disk-preflight heuristics; the 3.3 HTTP/2 API/HPACK details (the 3.3
planning session).

---

## Follow-on milestones (after this design)

### 3.3 — HTTP/2 client (separate plan/spec; planning session next)

HTTP/1.1 is sufficient for GitHub/GitLab; HTTP/2 is deferred to 3.3. The 3.3 planning
session must produce a plan/spec covering what std needs:

- `std_tls`: ALPN in the ClientHello/`TlsConfig` (offer `h2`, fall back to `http/1.1`;
  selected-protocol plumbing; TLS 1.2/1.3).
- `std_http` HTTP/2: connection preface; SETTINGS/ACK; frames (HEADERS, CONTINUATION,
  DATA, RST_STREAM, WINDOW_UPDATE, GOAWAY, PING); stream states; connection/stream flow
  control; max frame/header-list sizes; GOAWAY; connection reuse/multiplexing mapped onto
  the existing `HttpTransport`/`Response`/`ResponseSink`.
- HPACK: static and dynamic tables + eviction; Huffman encode/decode; integer/string
  representations; indexing; `SETTINGS_HEADER_TABLE_SIZE`; max header list; never-indexed.
- Server push/priority: ignored.
- API/backward compatibility: HTTP/1.1 remains the default/fallback; the streaming GET/POST
  APIs work over either; callers unchanged.
- Tests: a local h2 server over TLS with ALPN (python `h2`/nghttp2 or the dev equivalent),
  flow-control/header/GOAWAY/RST cases, GitHub/GitLab opt-in h2, fallback-to-1.1; a
  separate seed when std lands.
- This section is the input to that planning session; the 3.3 plan/spec is written there,
  not here.

### 3.5 — compiler improvements

The existing `docs/superpowers/plans/2026-10-29-phase35-defects-plan.md` remains the
compiler-improvement plan; it runs after 3.3. Nothing in this Phase 3 design changes its
scope.

### Order

Phase 3 (this design/plan) → **3.3 HTTP/2** → **3.5 compiler improvements**.
