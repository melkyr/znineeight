# Self-Compile C-Emission Fix — Design

**Date:** 2026-08-20
**Branch:** `zig1_start`
**Status:** Approved (operator rulings inline)

## Goal

Fix the C-emission defects that prevent `zig1` from producing a *compilable* `zig1_5` (the self-compiled compiler), so that `build_zig1_5.sh` completes: `gcc -c` of the 40 self-emitted `.c` files yields **0 errors**, the binaries link, and both `zig1_5_clean` + `zig1_5_asan` smoke on `examples/z98/hello/main.zig` (rc=0, `.c` emitted).

## Background (why this plan exists)

The correctness plan (`2026-08-20-correctness-on-self-compilation-plan.md`) Task T2 discovered that, while `zig1 --dump-c89 sf/src/main.zig` succeeds (rc=0, 40 `.c`), the emitted C **does not compile** under the canonical multi-module recipe. `gcc -m32 -std=c89 -I sf/src/include -c *.c` fails with **1195 errors across 16 of 40 files**. The prior "self-compile FULLY GREEN" milestone verified rc + file count + zero compiler diagnostics — it never gcc-compiled the emitted C. This plan closes that gap.

### The 5 defect classes (from the failed `gcc -c`)

| # | Class | Approx count | Notes |
|---|-------|--------------|-------|
| 1 | `zG_<hash>_<kind>` enum-constant globals referenced-but-undeclared | ~190 | Dominant. e.g. `zG_8143F551_AstKind_7`, `zG_33EF6BFB_TypeKind`, `zG_EAC3E484_TokenKind_2`. Only a few indices get a definition line; most are used without definition. Macros `zT_...` exist in `zig_special_types.h`, so the global-enum-constant path is emitted inconsistently. |
| 2 | Duplicate local redeclarations (`redeclaration of '<var>' with no linkage`) | ~200 | `lhs`, `rhs`, `t`, `src`, `dst`, `result`, `op_r`, `op_r_box`, `lhs_val`, `rhs_val`, `flb2`, ... |
| 3 | Anonymous struct/enum assign type mismatches | — | e.g. assign `anon_39335` → `unsigned char`, `SwitchCase` → `anon_39461` |
| 4 | Wrong payload member access | — | `TaggedUnionPayload` has no `elems_start`/`elems_count` (meant `fields_start`/`fields_count`); `EnumPayload` has no `payload` |
| 5 | `void value not ignored` | 9 | void fn used as a value |

### Key emitter facts (verified)

- The `zG_`/`zT_`/`zF_` prefixes are constructed dynamically by kind in `nameManglerMangle` (`sf/src/c89_emit.zig:410-412`): kind 0/1/2 → `F`/`G`/`T`. So `zG_<TypeHash>_<Name>` = a **global** (kind 1) mangled identifier. Class 1 means enum constants are referenced as globals (`zG_`) but the emitter never emits a definition for most of them.
- The emitter is `sf/src/c89_emit.zig` (single large file). All 5 classes are emission-stage (post-lowering); they do NOT affect parsing/sema/lowering, which is why `--dump-c89` rc=0 (compiler-side clean) coexists with uncompilable output.

## Architecture

A single **D → R → I → F → GATE** pipeline (operator ruling: "Single D→R→I→F pipeline"). The D task discovers which of the 5 classes share a root cause (a class→root-cause→emitter-site map); R builds one minimal fixture per *independent* root cause; I pins the upstream-correct fix per root cause; F applies them; GATE reconciles docs.

- **D (discovery)** — read-only. Map all 5 classes to root causes and emitter sites; produce the class→root-cause table; identify shared vs distinct root causes. No code changes.
- **R (repro)** — one minimal fixture per independent root cause under `repro/mi_matrix/<name>_xmod/`, RED = reproduces the bad C emission (`gcc -c` fails) with the current `/tmp/fx_subfolder/zig1`.
- **I (investigate)** — read-only. Pin the upstream-correct fix for each root cause (the right emitter change, not a patch of the emitted text). STOP for an operator ruling if any design fork arises.
- **F (fix)** — apply the fixes to `sf/src/c89_emit.zig`. Gate: `build_zig1_5.sh` completes (rc=0, both binaries), smoke rc=0, and the byte-identity gate holds.
- **GATE** — reconcile `docs/sf/QUICK_REF.md` + `repro/mi_matrix/EXPECTED_FAIL.md`.

## Global Constraints

- **Emission-only.** Memory (AST-spill/I-O, 16 MB target) and the correctness plan's T3-T6 (determinism/runtime/memory comparison) are **separate, deferred** plans. Do NOT touch them.
- **Hard byte-identity gate** (see below) with a **runtime-priority override**.
- Branch `zig1_start`. `scripts/self_compile/build_zig1_5.sh` is committed first (`ee2cbef6`).
- Never touch/ls `sf/build/out_release/` (WEDGED); all compiler runs `timeout 120`.
- Rebuild via `bash sf/scripts/build_release.sh` (gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`), then reinstall std: `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`.
- `edit`/`fastedit` only (AGENTS.md §X.7). STOP on any issue/confusion.

### Byte-identity gate (operator ruling)

The 4 MD5 gates + corpus 287 + matrix 21/21 emit *correct* C today and must stay unchanged:

- **4 MD5 gates (byte-identical):**
  - `examples/z98/game_of_life/main.zig` → `9cf758d96f25d41980379564a5501bc8`
  - `examples/z98/lisp_interpreter_curr/main.zig` → `88dcb7f9abf215aa6420f63e0e67e9c3` (repo-root CWD)
  - `examples/z98/json_parser/main.zig` → `9720478c937409a29fe23ae0199821cf`
  - `examples/z98/mud_server/main.zig` → `a1d0dd55aada9c3fd904ae33f54de32e`
- **Corpus 287 dirs:** `OK=276 FAIL=7 ICE=0 CRASH=0 GREEN=4` (FAIL=7 = `field_store_drop`, `self_embed_optional_cycle`, `parsergap_selfblok_xmod`, `parsergap_slice_expr_xmod`, `parsergap_specifier_xmod`, `parsergap_strict_comma_xmod`, `strictzig_brace_if_xmod`; GREEN=4 = `eu_assign_incompat_payload`, `euvoid_val_catch`, `field_access_optional`, `var_declared_void`).
- **21-example matrix 21/21** dump/gcc/link OK.

**Runtime-priority override:** runtime behavior is the priority. If a fix changes an MD5 *but the emitted C is still correct and runtime-identical*, STOP and report to the operator, and **propose a re-baseline** for the operator's decision. If an MD5 changes with any runtime/correctness doubt, STOP without proposing.

## Success Gate

`bash scripts/self_compile/build_zig1_5.sh` → rc=0, `=== [zig1_5] Done: /tmp/zig1_5 ===`, both `zig1_5_asan` + `zig1_5_clean` produced; smoke both on `examples/z98/hello/main.zig` (rc=0, `.c` emitted); AND the 4 MD5s + corpus 287 + matrix 21/21 remain unchanged (subject to the runtime-priority override above).

## Out of Scope

- Memory optimization / AST spill / I-O paging (16 MB target) — separate plan.
- Determinism (T3), runtime-match (T4), memory-measurement (T5), report (T6) of the correctness plan — resume only after `zig1_5` builds.
- Any parser/sema/lowering fix — all 5 classes are emission-stage.
