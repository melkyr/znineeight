# zig1 Live-Set Reduction via Allocation Savings + Workaround Elimination — Design

> Status: draft (2026-10-06). Measurement spike; no compiler fixes are committed by the paired plan.

## Problem

Real-hardware **RSS** is the binding budget (operator ruling, 2026-10-06). After the L3 fix
(per-module `diag_read` reset, commit `2d713a9a`) the `-s0` self-compile is **pool 14924K /
RSS ≈ 17580K** — down from pool 19274K / RSS 20216K, and now under the `-mm16` host gate.

The L6 investigation (Task 3b, `1a91d363`) proved that bounding the remaining `diag_read`
segment tail is **pool-only**: the tail is carved-but-never-touched, so it cannot lower RSS, and
every global growth rule that shrinks `pool` either fragments `type_db` or destroys L3's
`source` free-list reuse and *raises* RSS. Tail-bounding is therefore exhausted as an RSS lever.

What remains is the **live working set**. The `-s0` pool is dominated by the carve of a few live
arenas (post-L3):

| Arena | carve | note |
|---|---:|---|
| `module` | ~5256K | AST + lowered module state |
| `diag_read` | ~4545K | faulted source text + per-line `u32` index (reset per module by L3) |
| `perm` | ~2497K | permanent maps, interner, symbols |
| `import_scratch` | ~1353K | transient per-`@import` file text |
| `type_db` | ~1008K | type registry |
| `scratch` | ~218K | was 4570K pre-L3 (reuse win) |
| `source` | 0 | reused from `seg_free_head` |

RSS tracks the *touched* portion of these carves. The only route to lower RSS is therefore to
**stop allocating / shrink live allocations** and to **remove scaffolding that no longer earns
its bytes**.

This spike finds that waste and ranks it. It does **not** fix anything (SPIKE TERMINAL).

## Metric

- **Binding metric:** peak RSS of the self-compile run (`/usr/bin/time -v` Maximum resident set
  size), median of ≥3 interleaved samples. `pool`, `total` (live perm+mod+scratch), and the
  per-arena carve are reported for context only.
- **Baseline to freeze:** the current HEAD self-compile `-s0` RSS (expect ≈17.5–17.6 MB) plus the
  per-arena carve table and the 8/8 dump-MD5 pins.
- **Headroom (context):** a vanilla Windows 98 boot has a documented floor (min 16 MB;
  ~12–18 MB clean-boot range depending on drivers). On a **32 MB** machine that leaves roughly
  14–20 MB. The exact OS floor is a **deferred** measurement (out of scope here).
- **No target is fixed by this plan.** The ranked savings table (Task 3) is the operator's
  decision input; the concrete target is ruled *after* it.
- **Rejected as targets:** `pool` (host gate `-mm16`, already met) and `total` (≈3 MB) — context,
  not success.

## Scope

**In:**

- **Workstream 1 — Allocation-savings census.** Enumerate every allocation and classify where
  bytes are wasted (alloc+copy redundancy, over-sizing, per-object overhead, retained-after-last-read).
- **Workstream 2 — zig0-era workaround / boxing re-evaluation.** Code was shaped by **zig0**
  constraints that no longer apply: the seed model compiles `sf/src` with the current `zig1`
  (Z98), and the language has since gained features (PACK-CORE + PACK-AGG landed: packed union,
  nested packed fields, `enum(uN)`, `[N]Packed`, by-value/global/cross-module — commits
  `94734372…04ab6cf6`). Find workarounds and boxings that are now removable or simplifiable.

**Out (deferred):** a general boxing + array-vs-scalar *layout* sweep, and an 86Box/PCem Win98
idle measurement. They may be picked up after the census shows what is left.

## Workstream 1 — Allocation-savings census

Enumerate every allocation entry point and classify it.

- **Inventory:** `sandAlloc`, `u32ArrayListEnsureCapacity` / `...Append`, `growableSandInit`,
  `*ArrayList` boxes, `SpillStore` opens, and the inline `[N]` buffer fields (e.g. the four
  singletons with `spill_path: [512]u8`). Roughly 249 `sandAlloc`/ArrayList sites at `sf/src`.
- **Per-site columns:** file:line; owning arena/lifetime (`perm`/`module`/`scratch`/`diag_read`/
  `import_scratch`/`source`/`emission`/`lir_read`/`type_db`); object and count at self-compile;
  **per-object overhead** (arena alignment pad + any header); **alloc+copy redundancy**
  (allocate-then-copy-from-temp / double write / rebuild); **over-sizing** (capacity ≫ high-water,
  exact-fit-that-forces-a-tail, geometric over-carry); **live-vs-dead** (retained after last read —
  the `diag_read` tail class).
- **Ranking proxy:** expected **RSS** drop = bytes the peak actually *touches* that could be
  avoided, using the per-arena `arena <name>: grew` trace and the L3 lesson (only touched pages
  raise RSS).
- **Outputs:** a census table (all sites) + a shortlist of save-allocation candidates with byte
  estimates and risk.

## Workstream 2 — zig0-era workaround / boxing re-evaluation

- **Enumerate workarounds:** the Z98-limitation workarounds in `docs/sf/AGENTS.md` §1.3 (manual
  concrete hash maps for missing generics; global aggregate constants via `pub var` + `init()`;
  no `@cInclude` in zig0 mode; "no comptime beyond basic folding"; no pointer captures;
  `continue`-in-`while` rewrite; string-literal → `[]const u8` workaround; slice-bounds precompute;
  `switch` requires `else`) **plus** any code comment naming zig0/bootstrap and any structure whose
  shape encodes such a limitation.
- **Primary lead:** `sf/src/token.zig:131` — `Token` is 24 B with the comment *"Desired packed
  layout (16 bytes) rejected by zig0 for structs with union fields. Restore packed struct once
  zig1 can self-host."* PACK-AGG parked the "tagged-union-in-packed" FIXME as a **future
  follow-on**; with PACK-AGG now landed this is the flagship re-evaluation probe.
- **Method (per workaround):** write a **tiny seed probe** and compile it with the current seed to
  test whether the direct construct is now accepted; for boxing, check whether an inline `T` field
  can replace a `*T` and what the arena header/pad actually costs. Record: still-blocked /
  now-removable / removable-with-caveat.
- **Outputs:** a workaround/boxing table with per-item verdict + byte-delta estimate + risk
  (emitted-text / markers observable?).

## Evidence & gates (binding)

- Seed rebuilt per model: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>`;
  two-hop closure `hop1 == hop2`; no `FIXED_POINT_MD5` pin for a refactor candidate.
- Runtime equivalence oracle for any *fix*: corpus classify diff-empty
  (923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH) + runtime goldens gol/lisp/json/mud +
  `verify_stdlib` 266/0 + examples 24/24 + dump-MD5 8/8 (stdout-stream) + semantic markers
  byte-identical IN-SESSION.
- Memory: `-s0 --markers --track-memory` + `/usr/bin/time -v` RSS (median ≥3); per-arena carve =
  Σ `arena <name>: grew` `new`.
- Every claim evidenced (file:line, command output); the read-only spike writes only its reports.

## Risks / constraints

Seed model (code that changes must use constructs the current seed understands); `edit`/`fastedit`
only when fixing; runtime equivalence is the oracle; emitted C may change and dump-MD5 is recorded
per increment; compression forbidden during build sessions; no push; `timeout 120` per step
(aggregates 600); pre-create the `-o` output dir; free-function call form (no method syntax).

## Non-goals

- Re-litigating the exhausted allocator/AST/LIR/spill levers (F-1/I-F1, M5, I-COMPACT,
  S-INTERNER) and the L6 tail (proven pool-only).
- A struct-layout / packing sweep — already done ("the right way"); this spike targets
  *allocations and removable scaffolding*, not field packing.
- Changing the C89 back-end toolchain (explicitly deprioritized).
- Any fix that cannot be proven runtime-equivalent on the `repro/mi_matrix` + goldens battery.
