# Labeled-Block Break + Self-Compiled Lowering Crash — Design

**Date:** 2026-08-25
**Status:** APPROVED (operator-ruled design decisions)
**Branch:** zig1_start

## Goal

Fix two residuals of the (complete) fidelity-gap plan:

- **Phase A:** `break :blk` on a labeled block silently drops at runtime (prints wrong value, no diagnostic).
- **Phase B:** the self-compiled `zig1_5` binary SEGVs (rc=139) in lowering for std-importing programs — a previously-masked self-emission fidelity gap.

## Scope Decisions (operator-ruled)

- Single combined spec + plan covering both phases.
- **Phase B traces ONE locus; STOP and present if it reveals a broad self-emission class** rather than a single defect.
- Correctness bar = **runtime behavior** (program prints the expected value), NOT byte-identity vs zig0 (zig0's emission is "lifted and transformed"; architecture is not comparable).
- No `sf/src` changes outside the pinned fix loci; 4 MD5 byte-identity gates must hold.

## Background (triple-verified prior work)

### Phase A — labeled-block break silent drop

- `break_stmt`/`continue_stmt` lowering (`sf/src/lower.zig:5018-5069`) resolve labels ONLY against `loop_stack`.
- `loop_stack` is pushed solely by `while_stmt` (`lower.zig:4604`) and `for_stmt` (`lower.zig:4703/4757`).
- `labeled_stmt` lowering (`lower.zig:4441-4447`) only sets `current_label`; it NEVER pushes `loop_stack` → `break :blk` hits `loop_stack.len == 0 → return` (`:5019`) or `exit_target == 0 → return` (`:5037`) → break silently dropped. Runtime prints `2` (falls through `a=1; a=2`) instead of `1`. All rc=0, no diagnostic.
- `LoopInfo` struct (`lower.zig:73-78`): `{ header_bb: u32, exit_bb: u32, scope_depth: u32, label_id: u32 }`.
- Labeled while/for break+continue ARE green (loop_stack pushed). Fixture `repro/mi_matrix/emission_labeled_ctrl_xmod` documents the literal shape A RED (`3\n6\n10` output; shape A alone prints `2` vs expected `1`).

### Phase B — self-compiled zig1_5 lowering crash

- With the enum-switch fix (`5ec13efb`), the self-compiled `zig1_5` now reaches lowering and crashes rc=139 SEGV at `lower.zig:2261-2269` (ident_expr path): `types_items[garbage]` where `garbage` is a stale id from `resolvedTypeTableGet(node_idx)`.
- Reproduces on std-importing programs INCLUDING those with zero switches (`binexpr_test.zig`, `t_simple.zig`). Reference `/tmp/fx_subfolder/zig1` returns rc=0 on the same inputs.
- ADJUDICATED NOT a regression: pre-fix `zig1_5` never reached lowering (always `error[2000]` at operator tokens). Crash site is outside the `5ec13efb` diff (switch case-collection only). Same deferred "self-emission fidelity gap" class as QUICK_REF.md:74.
- Root cause NOT yet traced. Suspected: a front_resolution / resolved_types self-emission defect producing stale node→type ids in the SELF-EMITTED compiler.

## Architecture

- **Phase A:** extend the label-resolution machinery so `break :label` on a labeled block resolves to the block's exit BB, and `continue :label` (invalid on a block) does not. Two candidate designs (see Plan Task A1).
- **Phase B:** reproduce the self-compiled crash with a minimal committed fixture, trace the emission defect by diffing the self-emitted `front_resolution`/`resolved_type_table`/`semantic_analyzer` C against the reference `/tmp/ref_zig1.c`, then fix the single locus.

## Components / Data Flow

- **A1a (support break-on-block):** extend `LoopInfo` with `is_loop: u8` (or a parallel block-label stack). `labeled_stmt` lowering, when its body is a block, creates an exit BB and pushes a breakable entry (`header_bb = exit_bb = block-exit BB`, `is_loop = 0`); `break` resolves against it (jump to block exit); `continue` skips non-loop entries (continue-on-block is invalid).
- **A1b (explicit reject):** in `break_stmt`/`continue_stmt`, when a label does not resolve to a loop entry, emit a diagnostic (e.g. `error[XXXX] break target must be a loop`) instead of silent `return`.
- **B:** R fixture → self-compiled build (`scripts/self_compile/build_zig1_5.sh`) → ASan repro → emission diff vs reference → single-locus fix.

## Error Handling / Testing

- Fixtures are runtime-correctness driven (print expected value; RED = wrong output). 4 MD5 gates, matrix 21/21, self-compile re-count, Z98 dialect, `timeout 120` on all compiler invocations.

## Out of Scope

- Other self-emission fidelity gaps revealed during Phase B beyond the first traced locus (STOP-present).
- `sf/src_sh/` self-containment implementation (deferred; own plan on disk).
- Tagged-union qualified-label+capture gap (Task-1 M1 hazard; documented).
