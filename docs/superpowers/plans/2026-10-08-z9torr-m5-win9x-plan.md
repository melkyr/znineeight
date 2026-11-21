# z9torr M5 — Win9x cross — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `z9torr.exe` for Win9x with mingw and smoke-test it under Wine against a Z98 mock on the Linux host, then document the manual Win98 procedure.

**Architecture:** Emit a windows tree with `zig1 -o <dir> -osw` (or the documented `--dump-c89` + `-osw` recipe), cross-compile with `scripts/win32_cross/`, run under 32-bit Wine with the mocks on Linux, and record a PARITY-style smoke result. No source rewrite: Win9x seams (`WSAStartup`, `select` nfds, non-blocking connect + `getsockopt`, `GetTickCount`) already live in the std modules.

**Tech Stack:** Z98 (`zig1`), `-osw` Windows emission, `mingw-w64`, 32-bit `wine`, `scripts/win32_cross/{cross_build_run.sh,cross_net.sh,cross_parity.sh}`, POSIX `sh`.

**Spec:** `docs/superpowers/specs/2026-10-08-z9torr-bittorrent-client-design.md` (binding; §12 risks 2/5).

**Sequence:** PREVIOUS: `docs/superpowers/plans/2026-10-09-z9torr-m4-real-swarm-compat-plan.md`. NEXT: none (final milestone).

## Global Constraints

- **Does not gate on real hardware.** T4 = Wine smoke; T5 = documented manual Win98 procedure with expected output. The Win98 VM is outside the repo.
- **No compiler/source changes** unless a Win9x seam is genuinely broken; any such fix is a STOP-present with evidence (spec §12 risk 2).
- **Amendment lift — std change authorized (operator ruling, 2026-10-08).** The M0–M5 "example-only" restriction is lifted for **`sf/src/std_file.zig` + `sf/src/std_file_pal.zig`**: M5 adds **64-bit file offsets** (POSIX `lseek64`/`_llseek`/`pread64`; Windows already uses `SetFilePointerEx` i64) so payloads > 2 GiB work on the Linux host (spec §12 risk 7). Compiler fixed point untouched; `scripts/stdlib/verify_stdlib.sh` MUST stay green — add a `repro/mi_matrix` fixture + the M0-style registration.
- **parity checks are LF-normalized** (`cross_parity.sh` semantics).
- Build/counts/gitignore/edit/no-push/no-compression rules as M1. Reports under `.superpowers/sdd/2026-10-08-z9torr-m5-win9x-plan/`.
- Z98 rules: no method syntax; no generics; strict `@intCast`; `switch` needs `else`.

## File Structure

- Create: `examples/z98/z9torr/tests/tier4_wine.sh`
- Create: `examples/z98/z9torr/demo/win9x_README.txt` (manual T5 procedure)
- Modify: `examples/z98/z9torr/NOTES.md`, `README.md`

---

### Task 0: 64-bit file offsets in `std_file` (amendment lift)

**Files:**
- Modify (std, amendment lift): `sf/src/std_file.zig`, `sf/src/std_file_pal.zig`
- Create/register: `repro/mi_matrix/stdlib_file_seek64_xmod` fixture + seed-script/`QUICK_REF.md`/`expected_dirs.txt` registration (M0 pattern)

- [ ] **Step 1: Add 64-bit seek.** Widen `seekHandle`/`sizeHandle` to 64-bit offsets: POSIX use `lseek64`/`_llseek` (or `pread64`) and drop the 2 GiB rejection at `sf/src/std_file.zig:158-160`; Windows already uses `SetFilePointerEx` (i64) / `GetFileSizeEx`. Keep the same `seek`/`size` API (no signature change).
- [ ] **Step 2: Fixture + gate.** A `repro/mi_matrix` fixture seeks past the 2 GiB mark (sparse, no payload written) and asserts `size`/`seek` report the 64-bit offset; register it; `bash scripts/stdlib/verify_stdlib.sh` → green. Compiler untouched.
- [ ] **Step 3: Commit + report.** `git commit -m "feat(std_file): 64-bit file offsets (amendment lift)"`

---

### Task 1: Windows emission + mingw build

**Files:**
- Create: `examples/z98/z9torr/tests/tier4_wine.sh` (build half)

- [ ] **Step 1: Emit the Windows tree.**
  `timeout 120 "$ZIG" -osw -o /tmp/z9torr_win examples/z98/z9torr/main.zig`
  Expected: emit rc 0; the tree contains the module `.c/.h` + the Windows link scripts (`build_target.bat`, `build_owc.bat`) and `net_prelude.h`.
- [ ] **Step 2: Cross-compile with mingw.** Use the `scripts/win32_cross/` recipe (verify against the committed `cross_build_run.sh`); the mingw branch passes `-lwsock32`. Produce `z9torr.exe`.
- [ ] **Step 3: Sanity.** `file z9torr.exe` reports a PE32 executable; `nm`/`objdump -p` shows imports of `wsock32`.
- [ ] **Step 4: Commit + report.** `git commit -m "example(z9torr): add tier4 windows emission + mingw build script"`

---

### Task 2: Wine smoke against host mocks

**Files:**
- Modify: `examples/z98/z9torr/tests/tier4_wine.sh` (run half)

- [ ] **Step 1: Start mocks on the Linux host** (`mock_tracker` + `mock_peer`, ports from `ports.txt`) as in tier2.
- [ ] **Step 2: Run under Wine.**
  `wine /tmp/z9torr_win/z9torr.exe --torrent <(rehosted t1 path) ...` (Wine sees the Linux loopback as `127.0.0.1`; translate any path argument to a Wine-visible path).
- [ ] **Step 3: Assert.** The downloaded output SHA-1 matches `expected/t1_single_1m.sha1`; the client exits 0. Record `PARITY=OK`-style evidence (Wine rc, output hash).
- [ ] **Step 4: Non-blocking connect + `select` check.** Confirm `checkSoError` normalizes `WSAEWOULDBLOCK`/completion correctly under Wine (the mock peer connects and serves). If Wine's `select` reports writable before connect completes and the client mis-detects, STOP-present (risk 2).
- [ ] **Step 5: Commit + report.** `git commit -m "example(z9torr): add tier4 wine smoke against host mocks"`

---

### Task 3: Manual Win98 procedure + docs

**Files:**
- Create: `examples/z98/z9torr/demo/win9x_README.txt`
- Modify: `examples/z98/z9torr/NOTES.md`, `README.md`

- [ ] **Step 1: Write the T5 procedure.** Exact steps: copy `z9torr.exe` + the mock binaries (or use a Linux peer), a `.torrent`, run `z9torr.exe file.torrent`, and the expected console output (including the `\r` progress line and the `GetFileType` line-per-refresh fallback when redirected). Note the FAT no-sparse-file write behaviour (zeros up to the offset) and the `MAX_PATH`/reserved-name handling already enforced in M1.
- [ ] **Step 2: NOTES.md/README.md.** Record the `-osw` emit md5, the mingw build command, and that T4 is a Wine smoke (T5 manual).
- [ ] **Step 3: Gate (example-only).** Confirm the Linux `tier1.sh`/`tier2.sh` still PASS; `cross_nocrt.sh`-style no-CRT cleanliness if applicable. No compiler-only gates (fixed point / dump-MD5 / corpus classify) — the compiler is untouched.
- [ ] **Step 4: Commit + report.** Ledger line; declare M5 complete and the `z9torr` example delivered.

## Self-Review

- **Spec coverage:** §12 risk 2 (non-blocking connect on Win9x) → Task 2 Step 4; risk 5 (`FD_SETSIZE`) → Task 2 Step 2/4; risk 7 (> 2 GiB POSIX seek) → Task 0; T4/T5 tiers → Tasks 2–3.
- **Placeholder scan:** no TBDs; the smoke has an explicit hash assertion.
- **Type consistency:** no new public types; reuses M2/M3 modules.
