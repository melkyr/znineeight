# zig1 Memory Refactoring — Investigation + Roadmap — Design

**Date:** 2026-08-26
**Status:** DRAFT (awaiting operator approval)
**Branch:** zig1_start

## Goal

Produce a **conclusion / roadmap** for the future refactoring of zig1 to fit self-compilation in a **≤ 16 MiB pool** while never making the host OS (32 MB physical, P3/P4, Windows 98) report "out of memory". The plan **investigates** (reads zig1 code, evaluates what structures/encodings are available) and **proposes** (a prioritized roadmap) — it does NOT perform the refactoring.

## Scope Decisions (operator-ruled 2026-08-26)

- **No single big I task.** Investigation is split into **5 read-only I tasks**, each independently reviewable, followed by **1 P (proposal) task** that goes over the findings and decides.
- **Read-only for I tasks** — no `sf/src` changes. The only committed artifact is the P-1 roadmap document.
- **I/O tricks allowed**: page-file / partial AST-LIR disk dump is in scope to evaluate. The hard constraint: compilation must NOT make Windows go "out of memory".
- **zig0 dialect is the binding constraint** (migration to a richer dialect is a future objective, out of scope): the roadmap must only rely on constructs zig0 actually compiles — plain structs, unions, `u32`/`u64` fields with shift/mask helpers, arrays, out-of-line value tables. Confirmed NOT available: packed structs, bitfields, `anytype`, `@Type`.
- **Custom binary encoding is allowed** (u32/u64 + shifts), implementable in zig0, reusing existing codebase patterns.
- **Hard target:** zig1 self-compiles under a 16 MiB pool (32 MB physical P3/P4 Win98; cannot allocate more than physically available). Marker-volume reduction is in scope as an I task.
- **Byte-identity:** re-baselining the 4 MD5 gates is allowed if a future execution changes emission.

## Background — measured facts (2026-08-26, memory-comparison plan `2ce7c4ed`)

- **pool.peak = 83,210 KB** at self-compile (`track-memory: perm=1977K mod=16383K scr=2012K pool=83210K type_db=245K total=20372K`) — but this is the CUMULATIVE bump high-water: the pool (`allocator.zig:186`) is monotonic, NEVER reset. **Live in-use = 20,372 KB** (`total` = perm+mod+scr exactly). Both > 16 MiB.
- **Module arena dominates live:** 16,383 KB (the 16 MiB module segment high-water). AST + LIR together ≈ 11 MB of it.
- **AstNode = 32 B** (ast.zig:116-128, marker `ZZZ_ASTNODE_32B` :128): `kind u8, flags u8, pad2, span_len u32, span_start u32, child_0/1/2 u32, payload u64`. **180,020 nodes at self-compile** (marker `IRN:n180020`, import_resolver.zig:227) = 5.5 MB. Waste: payload u64 mostly holds a u32; child_2 used by ~10/111 kinds; 2 B padding.
- **LirInst = union(enum) ≈ 32 B** (lir.zig:22-102); largest variant `tail_call` = 28 B payload + 4 B tag; most insts are 1-4 u32.
- **Token = 24 B** (token.zig:115-123); a packed 16 B layout exists as a `FIXME` REJECTED by zig0.
- **Arena architecture** (allocator.zig): `memory_pool_buf[268435456 = 256 MiB]` (:184); perm/mod/scratch are GrowableSand segment arenas BACKED BY the pool, 4 KB→8→16→… doubling (:108-130), `sandReset` keeps peak + "post-reset reuse" (:78-87), `sandTryReallocInPlace` tail-guard (:158-171). **BUG: `checkCombinedPeak` (:216-228) gates pool.peak against POOL_SIZE (256 MiB), NOT `max_mem` (16 MiB) — the 16 MB budget is UNENFORCED.** type_db = separate 128 KB stack arena (main.zig:155-157).
- **Markers:** 2,932 `[]const u8 = "…"` sites (rodata bloat) + `--markers` emits an 82 MB / ~7.4M-line stderr ≈ 27 s wall (pal.zig:130-134 markerWrite). Not arena memory, but wall + rodata.
- **Prior memory-optimization plan DONE** (c2605866+): allocation-STRATEGY levers executed (exact-size two-pass token array, `sandTryReallocInPlace` 28 paths, per-scope `sandReset`, interner/hash pre-size, `lirFunctionRelocateToModule`). Remaining gap = the **constant factor: the 32-byte structs themselves** (representation compaction) + the geometric segment doubling + cumulative pool.

## Architecture — 5 I tasks + 1 P task

1. **I-1 Hot-structure census:** every struct/union allocated at scale (AstNode, LirInst, Token, OpInfo, CallInfo, type-registry/symbol-table/interner/hash-map entries, error-set entries) — exact sizeof (zig0 C layout), per-field usage, count at self-compile scale → waste map.
2. **I-2 Arena/pool behavior:** map the 83 MB cumulative vs 20 MB live gap; which collection/arena drives it; segment-doubling overhead; reset/reclaim points; where return-to-pool or spill is structurally possible.
3. **I-3 zig0 dialect design-space:** catalog what zig0 compiles (plain structs, unions, shift/mask helpers, out-of-line value tables — AstStore int/float pool pattern) vs confirmed-unavailable (packed, bitfields) → the legal representation toolkit + existing patterns to reuse.
4. **I-4 I/O spill feasibility:** parse→resolve→lower→c89_emit pipeline — where AST/LIR can be partially spilled to disk/page file (module boundaries, single-vs-multi-pass, re-load points) and how pool exhaustion manifests on Win98 → spill points + feasibility + risk.
5. **I-5 Marker-volume census:** 2,932 marker sites — rodata bytes, per-site volume, which are redundant/compressed, stderr I/O cost → reduction options.
6. **P-1 Roadmap conclusion:** consolidate I-1..I-5 into a committed roadmap doc — prioritized refactoring options (representation compaction, arena reclaim, disk spill, marker reduction) with per-item pool-reduction estimate, zig0-compat, risk, and a recommended order, framed against the ≤16 MiB self-compile target + never-OOM-Windows constraint.

## Components / Data Flow

- I tasks read `sf/src/*.zig` (ast.zig, lir.zig, token.zig, allocator.zig, parser.zig, lower.zig, c89_emit.zig, type_registry.zig, import_resolver.zig, pal.zig, main.zig, …) + measure with `--markers`, `size`, `grep -c` counts. All findings → one shared report `.superpowers/sdd/task-ROADMAP-report.md` (gitignored).
- P-1 writes + commits `docs/superpowers/specs/2026-08-26-zig1-memory-refactor-roadmap.md`.

## Error Handling / Testing

- Read-only acceptance: no `sf/src` edits; `git status` clean apart from pre-existing uncommitted files.
- Evidence rule: every roadmap claim must trace to a read (file:line) or a measurement (count, byte size, RSS/pool number) recorded in the report — no invented figures.
- `timeout 120` on every compiler/binary invocation; `--output-dir` must pre-exist; `--markers` stderr redirect to file + grep.
- 4 MD5 gates untouched (no source changes); noted as re-baselinable for future execution.
- Each I task delivers file:line-grounded findings + a one-paragraph "what this means for ≤16 MB" synthesis.

## Out of Scope

- Performing the refactoring / compaction / spill itself (future execution plan, fed by P-1's roadmap).
- Migration to a richer dialect (future objective).
- Any `sf/src` source change; any byte-identity re-baseline execution.
- Self-compile correctness/determinism work (established elsewhere).
