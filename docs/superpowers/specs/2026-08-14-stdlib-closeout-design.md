# Std-Lib Closeout Fixes Design Spec

**Date:** 2026-08-14
**Status:** Approved by operator (m0981, m0983, m0985). Ready for plan.

## 1. Goal

Close out the 8 actionable items from the std-lib builtins final review (`.superpowers/sdd/std-lib-builtins-FINAL-review.md`), plus commit the operator-authorized `/tmp` build-script redirects. D1 (`@import("std")` search path) is deliberately **excluded** — it has its own plan (`2026-08-14-stdlib-search-path`).

## 2. Problem Statement

The std-lib builtins plan final review found 3 Important latent items + 7 Minor items. Of these, the following are actionable in this plan (the rest are tracked or split out):

| # | Item | Class | Disposition |
|---|---|---|---|
| Imp-2 | **D2: `std_arena` at module-instance ≥1 emits incomplete-type C** — `_N` instance suffix on the struct typedef but not fn-signature type refs | real compiler bug | **FIX** |
| Min-3 | `std_io.printInt(INT_MIN)` panics (i32 `0 - n` overflow) | std-lib bug | **FIX** |
| Min-4 | `host_is_windows` hardcoded `= false`; Windows zig1 build must flip it | config | **FIX** (config-module const) |
| Min-1 | Spec §3 catalog socket rows differ from implemented signatures | doc | **FIX** (doc) |
| Min-2 | Spec catalog `@sleepMs` OpenWatcom arm not emitted | doc | **FIX** (doc) |
| Min-6 | `emitSocketSelect` omits the `#ifdef` guard net_runtime.c has | cosmetic | **FIX** |
| Imp-1 | Win32 WSAStartup gap (`std_net.init()` no-op) | latent (no Win toolchain) | **TRACK** |
| Imp-3 | Win32/OpenWatcom `#ifdef` arms untested | latent (no Win toolchain) | **TRACK** |
| Min-5 | ~19 duplicated std copies | feature (D1) | **SEPARATE PLAN** |

Plus: commit the uncommitted `/tmp` redirects in `build_release.sh` + `differential_test.sh` (wedged `out_release` workaround, operator-authorized m0713) and the `task-F4-stdlib-report.md` edit.

## 3. Architecture

**Phase 1 — R/I:** R1 creates the D2 repro (two modules sharing `std_arena` at module-instance ≥1). I1 (batched) confirms the D2 emitter site and the `host_is_windows` config-const point. Combined STOP for operator ruling.

**Phase 2 — F:** F1 (D2 fix), F2 (`host_is_windows` config const), F3 (printInt + doc fixes batch), F4 (gate sweep + tracking-entry refresh).

## 4. Tasks

### 4.1 T0 — Commit the pending /tmp redirects + report edit

Commit the operator-authorized uncommitted files: `sf/scripts/build_release.sh` (OUT_DIR → /tmp/fx_subfolder), `sf/scripts/differential_test.sh` (ZIG1 → /tmp/fx_subfolder/zig1), and `.superpowers/sdd/task-F4-stdlib-report.md` (48→47 correction). These are the wedged-`out_release` workaround.

### 4.2 R1 — D2 repro (`std_arena` module-instance ≥1)

Create `repro/mi_matrix/arena_multi_inst_xmod/`: two modules both `@import("std_arena.zig")` (so it's compiled at instance 0 and instance 1), one module calls `std_arena.create`, the other calls `std_arena.alloc`. Pre-fix: gcc-FAIL with `return type is an incomplete type` in the instance-≥1 module's emitted C. zig0 oracle: compiles clean. Post-F4 convention: local `std.zig`/`std_io.zig` copies; `std.io.printInt` for output.

### 4.3 I1 — D2 emitter site + host_is_windows config point (batched)

Confirm the exact emitter locus for the D2 instance-`_N` suffix defect (the `_N` module-instance suffix on struct typedefs vs. fn-signature type refs in `sf/src/c89_emit.zig` — find where instance suffixes are applied and where they're missed). Confirm the `host_is_windows` const site (`comptime_eval.zig:19`) and the cleanest config-module placement. Update tech doc `00_shared_infra.md` (or the doc covering the emitter's instance suffixing). No compiler code changes.

### 4.4 F1 — Fix D2 (module-instance ≥1 arena incomplete type)

Per I1 ruling. Make the fn-signature type references carry the same `_N` instance suffix the struct typedef gets, OR (operator alternative) emit an `extern`/fwd-declaration that resolves the incomplete type. Gate: `arena_multi_inst_xmod` dump/gcc/link/run rc=0.

### 4.5 F2 — `host_is_windows` config-module const

Introduce a config module (e.g. `sf/src/target.zig` or a documented const in `comptime_eval.zig`) exposing `pub const host_is_windows: bool = false;`, imported by the comptime-fold path. No CLI flag (operator m0983: config const avoids cmd-line bloat). Document that a Windows build flips the single const. Gate: `@isWindows()` still folds to 0; emitted C unchanged (byte-identical MD5s).

### 4.6 F3 — printInt(INT_MIN) + spec-catalog doc fixes + emitSocketSelect #ifdef

- `std_io.printInt`: fix the `0 - n` i32 overflow (the EXPECTED_FAIL-filed fix `0 - @intCast(u32, n)` was rejected at F4-review time because it breaks `-5`; use the i64-widened negation `@intCast(u32, 0 - @intCast(i64, n))` which was verified correct for both `-5` and INT_MIN).
- Spec doc: correct the `@socketCreate`/`@socketSelect` catalog rows to the implemented signatures.
- Spec doc: note the `@sleepMs` OpenWatcom arm disposition (2-way `_WIN32/#else`).
- `emitSocketSelect`: add the `#ifdef` guard matching net_runtime.c (identical arms).
Gate: `-5` still prints; INT_MIN via a throwaway /tmp test prints `2147483648`; 4 MD5s byte-identical (printInt isn't in gate emitted-C unless an example prints via it — verify).

### 4.7 F4 — Gate sweep + tracking-entry refresh

Full 21-example matrix, 4 MD5 gates, corpus sweep, test_analyzer_bin. Refresh EXPECTED_FAIL.md tracking entries for Win32 WSAStartup + Win-arm-untested (both stay latent, documented). EXPECTED_FAIL version bump + QUICK_REF baseline + tech docs.

## 5. Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — ⭐ SUBAGENT CHEAT-SHEET (lines 1-60). Copy exact commands; do not improvise flags.
- **Compiler under test:** `/tmp/fx_subfolder/zig1` (out_release WEDGED — hangs; **all bash commands touching out_release MUST have explicit timeouts**). Rebuild: `bash sf/scripts/build_release.sh`, gate on `=== [release] Done: /tmp/fx_subfolder/zig1 ===`.
- **4 MD5 gates byte-identical** UNLESS operator-approved re-baseline with runtime proof (AMENDMENT B): gol `ff47d18dc8ef00e9b8f92f5e0a14c34a`, lisp `c1cb748b423eef191b9c9ce7023ae2a0`, json `376fd6812ef751913bdad00de676ceb6`, mud `fd0fdaa42a419b0e72cfdb3226a54c4a` (mud NOT a gate).
- **Corpus:** 246 dirs, OK=239/FAIL=3/GG=4. FAIL=3 = field_store_drop, test_stub_0, self_embed_optional_cycle. FAIL must not increase.
- **RUNTIME gates mandatory** (AGENTS §2.5.3): every fixed repro must run rc=0 AND print expected output.
- **Tech-doc maintenance (AGENTS §1.1.1):** every I-task and source-changing F-task updates the covering tech doc — corrected line refs, `[updated: 2026-08-14]`.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region before each edit; bottom-to-top). NO sed/python/bulk transforms. NO scope creep.
- **The plan is the ONLY authority.** Plan says A → do A. If you believe X/Y is better, STOP and present.
- **I-tasks report then STOP for combined operator ruling.** F-tasks do NOT start until the ruling.
- **D1 (`@import("std")` search path) is OUT OF SCOPE here** — separate plan. Do NOT migrate std copies or touch the resolver.

## 6. Out of Scope

- D1 import-resolver search path (own plan)
- Win32 WSAStartup emission, Win/OpenWatcom arm testing (tracked, no Win toolchain)
- Any other EXPECTED_FAIL follow-ups (TU payload-read, scratch-arena, cross-module enum switch-case)
