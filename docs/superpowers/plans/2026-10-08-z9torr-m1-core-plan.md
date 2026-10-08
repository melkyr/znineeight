# z9torr M1 — core (pure) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `examples/z98/z9torr` and make `z9torr <file.torrent>` parse a single-file torrent and print a verified metadata summary (name, length, piece length, piece count, info_hash), with a C89 reference checker and a tier1 test script — no sockets.

**Architecture:** A new example dir with `main.zig` + focused modules. It consumes M0's `std_bencode` and `std_crypto.sha1`. `info_hash` is SHA-1 of the **exact** `info` dictionary bytes obtained via `std_bencode.dictValueSpan` (never re-encoded). Testdata torrents + a C89 `ref_check.c` cross-check the Z98 output.

**Tech Stack:** Z98 (`zig1`), C89 emission, `gcc -m32`, `std_bencode`, `std_crypto`, POSIX `sh`.

**Spec:** `docs/superpowers/specs/2026-10-08-z9torr-bittorrent-client-design.md` (binding; §5, §6, §8, §10).

**Sequence:** PREVIOUS: `docs/superpowers/plans/2026-10-08-z9torr-m0-std-prerequisites-plan.md`. NEXT: `docs/superpowers/plans/2026-10-08-z9torr-m2-single-peer-download-plan.md`.

## Global Constraints

- **Depends on M0.** `/tmp/z9_m0_seed/zig1_5_clean` (or a fresh seed build) must include `std_bencode.zig`/`std_http.zig`/the `std_net` additions in its sibling `lib/`.
- **Example build recipe (binding).** `timeout 120 "$ZIG" -ffast -o <tmp> examples/z98/z9torr/main.zig`, then the binding gcc flag-set `-m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <tmp> -c`, then `sh <tmp>/build_target.sh linux <tmp>/prog`.
- **Corpus (discovery only).** Adding `examples/z98/z9torr/main.zig` auto-joins `scripts/corpus/list_corpus_dirs.sh` (the example becomes discoverable). Doc-count updates (`README.md:39,257`, QUICK_REF baseline) are optional hygiene and NOT a gate. Do NOT run the corpus classify — it is a compiler-regression gate and the compiler is untouched.
- **INFO_HASH (binding).** `info_hash = sha1(exact info bytes)`; no re-encode, no normalize. Fixtures rejected if this differs.
- **Sample of record.** Existing reference programs under `examples/z98/` are the pattern (`main.zig` + `NOTES.md` required; `README.md` conventional; `demo/` goldens).
- Text files (`*.txt`) are gitignored — commit goldens/fixtures with `git add -f`.
- Edits via `edit`/`fastedit` only. **No push. Compression FORBIDDEN during the build session.** Reports under `.superpowers/sdd/2026-10-08-z9torr-m1-core-plan/`.
- Z98 rules: no method syntax; no generics; strict `@intCast`; `switch` needs `else`; string literals via `var s: []const u8 = "x";`.

## File Structure

- Create: `examples/z98/z9torr/main.zig`, `cli.zig`, `torrent.zig`
- Create: `examples/z98/z9torr/tools/ref_check.c`
- Create: `examples/z98/z9torr/tests/mkfixture.sh`, `tests/tier1.sh`
- Create: `examples/z98/z9torr/testdata/{t1_single_1m.torrent,t2_single_25m.torrent,t5_unicode_name.torrent,expected/*.sha1,expected/*.infohash}`
- Create: `examples/z98/z9torr/NOTES.md`, `README.md`, `demo/README.md`
- Modify: `README.md`, `docs/sf/QUICK_REF.md` (counts)

---

### Task 0: Example skeleton + corpus join

**Files:**
- Create: `examples/z98/z9torr/main.zig` (stub), `NOTES.md`, `README.md`

**Interfaces:**
- Produces: a buildable entry point discoverable by the corpus.

- [ ] **Step 1: Create the minimal entry.**
  `main.zig`: `pub fn main() void { std.io.write("z9torr\n"); }` importing `std_io` via `@import("std.zig")` or the path form used by sibling examples. (Check `examples/z98/hello/main.zig` for the exact import convention and mirror it.)
- [ ] **Step 2: Verify it builds and runs.**
  `timeout 120 /tmp/z9_m0_seed/zig1_5_clean -ffast -o /tmp/z9_m1_hello examples/z98/z9torr/main.zig && (cd /tmp/z9_m1_hello && sh build_target.sh linux ./prog) && /tmp/z9_m1_hello/prog`
  Expected: prints `z9torr`.
- [ ] **Step 3: Confirm discovery.** `bash scripts/corpus/list_corpus_dirs.sh | grep z9torr` → `examples/z98/z9torr/`.
- [ ] **Step 4: NOTES.md + README.md skeletons** using the standard header (Status, Entry file, Working commit, MD5 `--dump-c89`, Build Recipes, Expected Output, Notes).
- [ ] **Step 5: Commit.** `git add -f examples/z98/z9torr && git commit -m "example(z9torr): add skeleton entry, notes, readme"`
- [ ] **Step 6: Report.** Ledger line.

---

### Task 1: CLI parsing

**Files:**
- Create: `examples/z98/z9torr/cli.zig`
- Modify: `examples/z98/z9torr/main.zig`
- Create: `examples/z98/z9torr/tests/tier1_cli.sh`

**Interfaces:**
- Produces: `Args = struct { torrent_path: []const u8, max_peers: u32, max_up: u32, max_down: u32 }`; `pub fn parseArgs(argc: i32, argv: [*][*]u8) Args` (M1a: many-pointer, no `[]synthetic` — D2); `pub fn usage() void`; `pub fn exitCodeFor(e: anyerror) u8` (or a fixed mapping per spec §8).

- [ ] **Step 1: Write the tier1 CLI test first.** `tests/tier1_cli.sh` builds the program, then runs 6 shapes:
  `--help` → exit 0 + usage on stdout; no args → exit 1; unknown flag → exit 1; `--max-peers 101` → exit 1; valid `file.torrent` (missing file) → exit 2; `--max-down 70000` → exit 1. Assert exit codes with `test $? -eq N`.
- [ ] **Step 2: Run it; expect FAIL** (unimplemented).
- [ ] **Step 3: Implement `cli.zig`.** Parse `argv[1..]`: first non-flag token is the torrent path; `--help/-h`, `--max-peers N` (reject > 100), `--max-up N`, `--max-down N` (reject > 65535). No allocation (stack `Args`). Note the Win9x argv caveat in `NOTES.md`.
- [ ] **Step 4: Implement `exitCodeFor`** per spec §8 (0 success, 1 usage, 2 torrent/file, 3 tracker/net, 4 peer, 5 disk).
- [ ] **Step 5: Run tier1_cli.sh; expect PASS.**
- [ ] **Step 6: Commit.** `git commit -m "example(z9torr): add CLI parsing + tier1_cli"`
- [ ] **Step 7: Report.** Ledger line.

---

### Task 2: Torrent parsing

**Files:**
- Create: `examples/z98/z9torr/torrent.zig`
- Modify: `examples/z98/z9torr/main.zig`

**Interfaces:**
- Consumes: `std_bencode.decode`, `std_bencode.dictValueSpan`, `std_crypto.sha1Init/Update/Final`.
- Produces: `Torrent` (spec §6, single-file: `announce`, `announce_list: [8][]const u8` + `announce_count: u32` (M1a, D2-safe; extras dropped — never `[][]const u8`), `info_hash: [20]u8`, `name`, `piece_length: u32`, `piece_hashes: []const u8` (flat, 20 B/piece — amended 2026-10-08), `total_length: u64`); `TorrentError = error{ MalformedBencode, MissingField, BadInfoHash, BadPieceCount, BadFilePath, TooLarge, OutOfMemory }`; M1a adds `MAX_TORRENT_BYTES = 3145728` (3 MiB metadata cap) and derives `MAX_PIECES = MAX_TORRENT_BYTES / 20`; `load` rejects oversized metadata with `TooLarge`; `pub fn load(arena, file_bytes) TorrentError!Torrent`.

- [ ] **Step 1: Implement `load`.**
  - `decode` the whole file to a `Value`; require a top-level dict with `announce` (bytes), `info` (dict), optional `announce-list`.
  - `info_hash`: `dictValueSpan(file_bytes, "info")` → SHA-1 over `file_bytes[span.start..span.end]`. (Never re-encode.)
  - From `info`: `name` (bytes; pass through), `piece length` (int → `u32`), `pieces` (bytes; split into `[20]u8` entries), `length` (int → `u64`) for single-file.
  - Checks: `piece_hashes.len == 20 * ceil(total_length / piece_length)` (flat, 20 B/piece); `piece_length` in a sane range (e.g. 16 KiB..16 MiB); reject `length` absent (single-file only) with `MissingField` (multi-file is out of scope).
  - Path safety: reject `name` containing `/`, `\`, `..`, or a leading `/` (single-file output name).
- [ ] **Step 2: Wire `main.zig`** to load the file (`std_file.readAll` / `std.io` read) and print a summary: `name`, `length`, `piece length`, `pieces`, `info_hash` (40 hex, using a small hex helper or `std_hex.encodeLower` if importable by path).
- [ ] **Step 3: Manually verify** against a hand-made torrent (see Task 3) and a known info_hash.
- [ ] **Step 4: Commit.** `git commit -m "example(z9torr): add single-file torrent parsing + info_hash"`
- [ ] **Step 5: Report.** Ledger line.

---

### Task 3: Testdata + reference checker

**Files:**
- Create: `examples/z98/z9torr/tools/ref_check.c`
- Create: `examples/z98/z9torr/tests/mkfixture.sh`
- Create: `examples/z98/z9torr/testdata/*.torrent`, `testdata/expected/*`

**Interfaces:**
- Produces: three deterministic fixtures + committed `expected/<name>.sha1` and `expected/<name>.infohash`.

- [ ] **Step 1: Write `ref_check.c`** (C89): decode bencode, compute SHA-1, and print `infohash <40hex>` for `ref_check --infohash <file>`; build with `gcc -std=c89 -O0 -Wall`.
- [ ] **Step 2: Write `tests/mkfixture.sh`** (POSIX sh + awk, no Python): generate deterministic content (`awk` seeded sequence), split into pieces, compute piece SHA-1s and the info hash via `ref_check`, and assemble a bencoded `.torrent` with a shell-built byte stream. Produces `t1_single_1m` (1 MB, 4 pieces), `t2_single_25m` (25 MB, 100 pieces), `t5_unicode_name` (small, UTF-8 `info.name`). It writes `testdata/expected/<name>.{sha1,infohash}`.
- [ ] **Step 3: Generate the fixtures once and commit them.** The suite does **not** regenerate (a corrupted fixture is caught, not silently recreated).
- [ ] **Step 4: Cross-check.** For each fixture, `ref_check --infohash` and the z9torr summary must agree; `t1`'s full-file `sha1sum` is recorded too.
- [ ] **Step 5: Commit** (with `git add -f` for the `.txt`/bencode fixtures as needed).
  `git commit -m "example(z9torr): add testdata fixtures + C89 ref_check + mkfixture"`
- [ ] **Step 6: Report.** Ledger line.

---

### Task 4: tier1 end-to-end + demo golden

**Files:**
- Create: `examples/z98/z9torr/tests/tier1.sh`, `demo/README.md`

**Interfaces:**
- Consumes: Tasks 1–3.

- [ ] **Step 1: Write `tests/tier1.sh`:**
  1. Build `z9torr` via the binding recipe.
  2. For each fixture: run `z9torr <fixture>`; assert the printed `info_hash` equals `testdata/expected/<name>.infohash` and matches `ref_check`.
  3. Malformed-input cases: truncated file, bad piece count, mutated `info` byte (info_hash mismatch) each expected exit 2 with a typed message.
  4. Determinism: run each fixture 3×, outputs byte-identical.
- [ ] **Step 2: Run tier1.sh; expect all PASS.**
- [ ] **Step 3: Write `demo/README.md`** documenting the exact commands + the `--dump-c89` md5 and info_hashes.
- [ ] **Step 4: Commit.** `git commit -m "example(z9torr): add tier1 end-to-end + demo golden"`
- [ ] **Step 5: Report.** Ledger line.

---

### Task 5: M1 closeout

**Files:**
- Modify: `README.md`, `docs/sf/QUICK_REF.md`, `examples/z98/z9torr/NOTES.md`
- Record: `.superpowers/sdd/2026-10-08-z9torr-m1-core-plan/task-5-report.md`

- [ ] **Step 1: Docs.** Record the `--dump-c89` md5 in `NOTES.md`; optionally update `README.md:39,257` and the QUICK_REF examples baseline (24 → 25).
- [ ] **Step 2: Gate (example-only).** `bash examples/z98/z9torr/tests/tier1.sh` → all PASS (bind-recipe build + parse/round-trip/ref_check/malformed/determinism). `bash scripts/corpus/list_corpus_dirs.sh | grep z9torr` lists the dir. `verify_stdlib` unchanged from M0 (the example does not touch std). No compiler-only gates (fixed point / dump-MD5 / corpus classify) — the compiler is untouched.
- [ ] **Step 4: Report + commit.** Commit docs + report. Ledger line.
- [ ] **Step 5: Next plan.** State that M2 (`2026-10-08-z9torr-m2-single-peer-download-plan.md`) is next.

## Self-Review

- **Spec coverage:** §5 layout → Tasks 0–4; §6 `Torrent`/`Args` → Tasks 1–2; §8 exit codes → Task 1; §10 fixtures/ref_check/tier1 → Tasks 3–4; §10 counts → Task 5.
- **Placeholder scan:** no TBDs; every script has named assertions and exit codes; fixtures have exact sizes and committed hashes.
- **Type consistency:** `Args`/`parseArgs`/`usage`/`exitCodeFor`, `Torrent`/`TorrentError`/`load` are used identically here and in the spec.
