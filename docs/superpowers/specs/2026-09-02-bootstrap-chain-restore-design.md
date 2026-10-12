# Restore & Preserve the Bootstrap Chain (zig0 → zig1) — Design

**Date:** 2026-09-02
**Status:** DRAFT (awaiting operator approval)
**Branch:** zig1_start
**Baseline:** HEAD `d95c2938` (emergency .bak commit); reference zig1 `/tmp/fx_subfolder/zig1` == zig1_5_clean (md5 `0c09fe1a`); stale bootstrap `build/zig0` (08-27, type checker identical to a fresh rebuild — `src/bootstrap/type_checker.cpp` unchanged since 2026-05-11)

## Goal

Recover the `zig0 → zig1` bootstrap chain (last green at `2206177e`, broken at `a1bfa260`) by rewriting the offending constructs into zig0-compatible form, so `build_release.sh` works again — with a documented, separately-planned fallback if recovery proves impossible.

## Scope Decisions (operator-ruled 2026-09-02)

- **Boundary:** last-good `2206177e` (its `sf/src` = `40d72e04` F-TABLE state), first-bad `a1bfa260` (F-SIDE). Recorded in a README note.
- **Root cause (established):** bootstrap drift. All self-compile-era fixes went into zig1's `semantic_analyzer.zig`; zig0's `type_checker.cpp` (C++ bootstrap) was never updated (unchanged since 2026-05-11). zig0 can no longer type-check constructs added after 08-27.
- **The offending construct (bisect-pinned):** `ast.zig` value-pool cache slice — `p.cache_buf[ @intCast(usize,v)*BLOCK .. @intCast(usize,v)*BLOCK + BLOCK ]` (ast.zig:592 at a1bfa260 / :581 at HEAD) — a slice of a `[*]u8` **struct field** with a **computed (non-literal) start**. zig0 reports `type mismatch`. The zig0-accepted pattern (S-AST, good) is `nraw[0..N]` / `praw[0..N]` (literal `0` start, simple bound).
- **Investigation method:** minimal-repro harness — tiny `.zig` snippets run through the stale `build/zig0` front-end (valid oracle: type checker identical to a fresh rebuild) to pin the exact inference gap + root-vs-cascade classification.
- **Goal framing:** "controlled deattachment from bootstrapping" — preserve the chain while the only fully-tested compiler (zig0) is still capable. If preservation is impossible, fall to an ultra-gate + separate merge plan.
- **5 source commits after the break** map the investigation: `a1bfa260` (F-SIDE, root), `eb8730c8` (F-FMT), `89c310a7` (F-SBackend, spill_store — suspected 2nd root), `16d28337` (F-MM), `cc5c37c1` (F-S). GATE `ff5e3633` + the two `.bak` commits change no source.

## Background — measured facts

- **Last zig0-green:** `build_release.sh` (zig0→zig1) last succeeded 08-27. Everything after (memory-refactor S-series 09-01, allocator F-series, spill F-series 09-02) was kept alive only via the self-host chain (zig1_5 compiling sf/src → new zig1).
- **Bisect result (automated, stale-zig0 oracle, monotone):** `a1bfa260` = first bad; `2206177e` = last good. 7 commits after the first bad.
- **At a1bfa260, zig0 errors:** `ast.zig:592:25 type mismatch` (the value-pool slice) + `ast.zig:600/601 unable to infer` + `c89_emit:1681` / `comptime_eval:55` / `front_resolution:158` unable-to-infer. The last three are OLD constructs (introduced 08-27/07-09/08-19) that compiled at `2206177e` → **suspected cascades** of the ast.zig:592 break, not independent roots.
- **At HEAD, zig0 errors add** `spill_store.zig:183/213` (`var end = off + @intCast(u32, bytes.len)`, from `89c310a7`) — suspected independent root, to be confirmed (may itself be a cascade).
- **`AstValuePool` fields** (ast.zig:306-330): `head_buf: [*]u8`, `cache_buf: [*]u8`, `slot_block: [VALUE_POOL_SLOTS]u32`, `spill: SpillStore`.
- **Good slice idiom present in the tree** (ast.zig:782/784, S-AST): `spillReadAt(&store.spill, entry.disk_off, nraw[0..@intCast(usize, AST_BLOCK_NODE_BYTES)])`.
- **Compatible-idiom hypothesis:** hoist the computed slice base into a local — `var base = p.cache_buf + off; spillReadAt(..., base[0..len])` (matches the `[0..len]`-on-a-simple-expression pattern), and/or use explicit `var x: T = …` annotations where inference alone fails. Verified empirically by the I-BOOT harness, never assumed.
- **Emergeny backups at HEAD** (committed, untouched): `build/zig1_5_clean.bak` (0c09fe1a), `build/zig1_5_asan.bak`, `build/zig1_reference.bak`, `build/zig1_5_bin.bak.tar.gz`, `build/zig1_5_src.bak.tar.gz` (source bundle; gcc-only rebuild proven byte-identical).
- **Gates (unchanged baselines):** gol `302df36b` / lisp `3591bad9` / json `76056b97` / mud `4591fef0`; golden 9/9; self-compile 42 `.c` / 0 err / 0 PANIC; corpus 404 dirs 0-asymmetric.

## Architecture

- **Task 0 — README note (docs).** Record the boundary + drift risk.
- **Task I-BOOT (read-only investigation).** Minimal-repro harness over construct shapes → root-vs-cascade classification → zig0-compatible idiom per root → recoverable/impossible verdict → STOP-present.
- **Task F-BOOT (gated on recoverable, executed on HEAD).** F-BOOT-1 rewrite the ast.zig value-pool slice root; F-BOOT-2 rewrite spill_store roots if independent; F-BOOT-3 end-to-end `build_release.sh` green + full gate battery on the zig0-built zig1.
- **Fallback (conditional → separate plan).** If I-BOOT = impossible: ultra-gate zig1+zig1_5 against mi_matrix/corpus/full battery; README note "chain ends at `2206177e`"; second plan to merge `zig1_start → main` (w98 emission untested — unknown territory).

## Success criterion

`build_release.sh` (zig0 → zig1) succeeds from HEAD, and the produced zig1 passes the full battery: 4 MD5 byte-identical (gol `302df36b`/lisp `3591bad9`/json `76056b97`/mud `4591fef0`), golden 9/9, self-compile 42 `.c` / 0 err / 0 PANIC, corpus 404 dirs 0-asymmetric, ref 0-warning. This proves the zig0-built zig1 is behaviorally identical to the current zig1_5-derived reference (the oracle), with the bootstrap chain intact.

## Constraints

- F-BOOT rewrites are **source-only and behavior-preserving**: byte-identity of the 4 MD5 gates must NOT move (no re-baseline). The reference zig1 (`/tmp/fx_subfolder/zig1`, 0c09fe1a) is the oracle.
- `build_release.sh` is the acceptance gate — first exercise since 08-27; `timeout 900`; WIPES `/tmp/fx_subfolder` → reinstall std lib after each run.
- The minimal-repro harness uses the stale `build/zig0` front-end (valid: type checker identical to fresh); test snippets + outputs live under `/tmp/boot_diag/`.
- Z98 dialect; `edit`/`fastedit` only; never touch `sf/build/out_release/`; never touch the committed `.bak` files.
- Ledger `.superpowers/sdd/progress.md`; reports `.superpowers/sdd/task-BOOTSTRAP-report.md` (gitignored; task-1-report.md TRACKED, never reuse). Mnemoria agent `bootstraprestore-session`.
- Pre-existing dirty files never staged: `docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `mnemoria/*`, untracked `build/`, `.zig1_*.tmp`.
