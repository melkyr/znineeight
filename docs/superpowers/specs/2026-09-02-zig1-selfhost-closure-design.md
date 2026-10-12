# zig1 Self-Host Chain Determinism Closure + Advanced Examples — Design

**Date:** 2026-09-02
**Status:** DRAFT (awaiting operator approval)
**Branch:** zig1_start
**Baseline:** HEAD `a489d070` (bootstrap chain restored); reference zig1 `/tmp/fx_subfolder/zig1` (zig0-built), self-compiled `/tmp/zig1_5/zig1_5_clean`

## Goal

Prove the self-host chain is **deterministic and convergent** (zig1 → zig1_5 → zig1_5_self → zig1_5_self_self reach a byte-identical fixed point, and every hop passes the full correctness gate battery), measure compiler **performance** (including the `-s` spill-level RAM-vs-disk tradeoff), then write **advanced examples** that use the idiomatic z98 syntax zig1 supports but zig0's dialect forced us to avoid — demonstrating that zig1's descendants supersede zig0. This is the penultimate step before the migration plan (zig1 code to native cInclude-zig1-only) that closes the bootstrap cycle and detaches from zig0.

## Scope Decisions (operator-ruled 2026-09-02)

- **Determinism bar:** binary **md5 identity across the self-host hops** — `zig1_5_clean == zig1_5_self == zig1_5_self_self`. The zig0→zig1 hop is a *first-attempt* md5 check (zig0-built zig1 vs zig1_5_clean, currently both `0c09fe1a`) with the understanding that zig0's emission may differ structurally; if that md5 does NOT hold, the correctness bar falls back to **emission identity + runtime identity + gates**, never binary equality.
- **Chain hops to produce:** `zig1_5_self` (zig1_5_clean compiles `sf/src`) AND `zig1_5_self_self` (zig1_5_self compiles `sf/src`) — two self-host generations past the current one, to establish the md5 fixed point.
- **Performance:** full depth — wall + RSS + `pool=` for all four compilers (zig1, zig1_5_clean, zig1_5_self, zig1_5_self_self) on (a) self-compile and (b) the z98 ladder, at **every `-s` level 0..5** (quantifies the RAM-vs-disk spill tradeoff).
- **Modern constructs:** a read-only I task (U-INV) inventories the idiomatic/harmonic z98 constructs zig1 supports that the current examples avoid (quirk-avoiding to remain zig0-compilable); the U tasks consume that list. Rationale (operator m1590): today zig1's syntax is artificially narrow because zig0 must compile it; once zig0 is dropped, zig1 upgrades to richer z98 — and the **examples go first** to prove that richer syntax end-to-end.
- **Advanced example placement:** new sibling dirs `lisp_interpreter_upgraded`, `json_parser_upgraded`, `rogue_mud_upgraded` — the existing `lisp_interpreter_curr`/`json_parser`/`rogue_mud` stay as the compatibility baseline.
- **Plan granularity:** mostly small T (test) tasks; the final U (upgrade) tasks are the closing few, per operator direction.

## Background — measured facts (2026-09-02)

- The bootstrap chain (zig0 → zig1) was broken at `a1bfa260` (F-SIDE) and is now **restored** (commits `9087e5cb`/`5dfe77d6`/`85bf186c`, HEAD `a489d070`): `build_release.sh` is green, a fresh zig0-built zig1 passes the full battery.
- **Binary md5:** reference zig1 == zig1_5_clean == `0c09fe1a` (2,930,952 B, 32-bit ELF); zig1_5_asan == `f3c40259`. The zig0→zig1_5 md5 equality ALREADY holds at HEAD — the plan verifies it holds one and two more hops.
- **Self-compile recipe** (`scripts/self_compile/build_zig1_5.sh`): `zig1 --dump-c89 --output-dir $OUT/gen sf/src/main.zig` → gcc -m32 -c → link `zig_runtime.c`+`zig_pal.c`+`c_exit.c` → `zig1_5_clean` (no-asan) + `zig1_5_asan`. `--output-dir` must pre-exist; std lib copied to `$OUT/lib`.
- **Gate baselines (authoritative, must not move):** gol `302df36b` / lisp `3591bad9` / json `76056b97` / mud `4591fef0` (4 MD5, `--dump-c89 <entry> | md5sum`, repo-root CWD); golden 9/9 fixtures (`emission_assoc_chain_xmod`, `fn_ptr_struct_field`, `emission_lower_crash_xmod`, `tco_return_try`/`tco_defer`/`tco_factorial`, `quicksort`, `func_ptr_return`, `hello`); matrix 21/21; corpus (mi_matrix ~330 + top-level repro ~54) 0-asymmetric.
- **`-s` spill levels** (F-S, `cc5c37c1`): `-s0` all-Disk (default, `pool=14,857K` self-compile) through `-s5` all-Ram (`pool=72,970K`); `-s2..-s5` exceed the `-mm64` default → ICE rc=3 unless `-mm128`. RAM mode holds original source + spill simultaneously → higher RSS by design (the operator's expected tradeoff).
- **z98 examples:** 21 dirs (`days_in_month`, `fibonacci`, `func_ptr_return`, `game_of_life`, `heapsort`, `hello`, `json_parser`, `json_parser_workaround`, `lisp_interpreter`, `lisp_interpreter_adv`, `lisp_interpreter_curr`, `lzw`, `mandelbrot`, `mud_server`, `prime`, `quicksort`, `rogue_mud`, `sort_strings`, `tco_defer`, `tco_factorial`, `tco_return_try`). `lisp_interpreter_adv` is a prior (buggy) "advanced" attempt — NOT the target; the U tasks are fresh `_upgraded` dirs.

## Architecture — two phases

- **Phase T — verification (5 small T tasks):** T-RE-SELF (two more self-host hops + md5 fixed point), T-EMIT-DET (self-emission byte-identity), T-GATE (full battery on the new hops), T-PERF (wall/RSS/pool across compilers × `-s` levels × self/ladder), T-Z98-DET (emission + runtime determinism across the chain for all 21 examples).
- **Phase U — advanced examples (4 final U tasks):** U-INV (read-only inventory of idiomatic-z98 constructs), U-LISP/U-JSON/U-MUD (sibling `_upgraded` dirs using them, gated on all three self-host compilers), U-CLOSE (closure doc + docs GATE).

## Success criteria

- `zig1_5_clean`, `zig1_5_self`, `zig1_5_self_self` are **byte-identical** (md5); zig0-built zig1's md5 vs the chain is recorded (first-attempt check, emission+runtime fallback).
- Every self-host hop passes the full battery: 4 MD5 byte-identical, golden 9/9, matrix 21/21, corpus 0-asymmetric, self-compile 42 `.c` / 0 err / 0 PANIC, reference 0-warning.
- Perf report quantifies the `-s` RAM-vs-disk tradeoff (memory and wall) across all four compilers.
- The three `_upgraded` examples compile + run identically on zig1, zig1_5, zig1_5_self, zig1_5_self_self.

## Constraints

- Z98 dialect for any `.zig` changes (no anytype/@Type; `@intCast`; `switch` needs `else`; no method syntax; no pointer captures). The U examples may use richer-but-still-z98 idioms, never anything outside zig1's accepted dialect.
- `edit`/`fastedit` only; re-read before edit; bottom-to-top; never touch `sf/build/out_release/`.
- `timeout 120` on compiler/binary invocations; `timeout 900` on builds.
- Ledger: one line per task to `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory add --agent selfhostclosure-session --type <discovery|decision|pattern|success>`.
- Report file: `.superpowers/sdd/task-CLOSURE-report.md` (gitignored; `task-1-report.md` is TRACKED — never reuse).
- Pre-existing dirty files never staged: `docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `mnemoria/*`, untracked `build/`.
