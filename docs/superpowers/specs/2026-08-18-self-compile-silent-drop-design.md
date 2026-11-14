# Self-Compile Silent-Drop Repro & Isolation — Design

## Problem

Self-compiling `sf/src/main.zig` with the current `zig1` now reaches the semantic-analysis phase but emits **213× `error[3000]: cannot declare variable of type void`** across 12 files (c89_emit 68, lexer 40, analyzer 29, module_registry 18, parser 17, ast 13, main 10, import_resolver 9, symbol_table 4, type_registry 3, token 1, pal 1).

All 213 errors share **one root cause**: the first four modules imported by `main.zig` — **allocator (module id 1), string_interner (2), source_manager (3), diagnostics (4)** — parse successfully (`IRP` markers present) but are **silently skipped** by symbol registration and type resolution:

- `registerModuleSymbols` (`sf/src/symbol_registrator.zig:420-455`) never registers their decls. Its two early-return guards: `:422` `(state != parsed/resolved or ast_root == 0)` and `:424` `root.kind != module_root`.
- `resolveFnSignatures` (`sf/src/type_resolver.zig:1195-1261`) never creates their fn types (`rt_box[0] = TYPE_VOID` default at `:1214`).
- Consequence: every `var x = alloc_mod.initCompilerAlloc();` / `stringInternerInit(...)` / `sourceManagerInit(...)` / `diagnosticCollectorInit(...)` resolves the callee's struct return type to `TYPE_VOID` via the `Q1VF` fallback (`sf/src/semantic_analyzer.zig:424-426`), then the var-decl check at `semantic_analyzer.zig:1915-1922` emits `error[3000]`.

### Why a silent drop is severe

A silently dropped module produces a cascade of wrong diagnostics far from the true site, and the corruption is **invisible** — no OOM message, no ICE, no parse failure. The failure mode is worse than a diagnostic because it masks the real defect and can persist across many builds.

## Root-Cause Status (unproven link)

Verified facts:

- Modules 1–4 parse (all 39 modules emit `IRP` markers); module 5 (name_mangler) IS registered (`RN:m5n38` present) while modules 1–4 show `RN:m1..m4` = 0.
- At the end of import resolution the entries appear valid (`state = parsed`, valid `module_root` AST), so the flip happens between import resolution and symbol registration.
- Small repros do **not** reproduce: same-module struct return, cross-module struct return, field-access imports, double-import, 11-module interdependent graphs, 40-module graphs — all pass with zero `error[3000]`.
- The real self-compile has **39 modules and 9,331 unique interned identifiers** (324,576 `INT:dup` hits). The existing corpus (`r_fallback_fnret`, `r_fallback_constalias`, etc.) is 2–4 modules with tiny identifier sets.

Suspected mechanisms (not yet discriminated):

1. **Silent OOM** — an allocation fails and is swallowed during parse/registration of modules 1–4, leaving them without a valid AST or state.
2. **Module-too-big truncation** — modules 1–4 exceed some parser/registry buffer and are silently truncated.
3. **State / ast_root corruption at scale** — a growth/realloc bug (F-SWEEP class) flips `entry.state` or `entry.ast_root` for the first modules when interner/hash-map growth occurs at high identifier volume.

The single missing link: which early-return condition fires for modules 1–4, and what the corrupt value is (`state` / `ast_root == 0` / `root.kind`).

## Design

A **repro ladder** of six durable fixtures (simple → complex) that isolate the trigger dimension, plus one **investigation task** that pins the mechanism using **markers + intrusive fprintf** (operator-chosen helper). Fix tasks are deliberately out of scope here — this plan reproduces and isolates.

### Part A — Repro ladder (R1–R6)

Each rung is a committed `repro/mi_matrix/<name>/` fixture (`main.zig` + `NOTES.md`) run against the **existing** `/tmp/fx_subfolder/zig1` (HEAD binary, no rebuild). RED = dump rc≠0 or `error[3000]` present; GREEN = dump/gcc/run rc=0 with expected output. Each rung isolates one dimension:

| Rung | Fixture | Dimension isolated |
|---|---|---|
| R1 | `voiddecl_struct_xmod_r1` | Cross-module struct return at 2 modules (GREEN floor) |
| R2 | `voiddecl_chain_r2` | Linear import-chain depth (N ∈ 5/10/20/40) |
| R3 | `voiddecl_count_r3` | Sibling module count + first-N drop (N ∈ 4/8/16/32/39) |
| R4 | `voiddecl_volume_r4` | Interned identifier volume (1k/5k/10k) |
| R5 | `voiddecl_nested_r5` | Branching nested import tree |
| R6 | `voiddecl_mimic_r6` | Self-hosting-shape mimic (~39 modules, sf/src-like import order) |

### Part B — I-DROP investigation

On a **/tmp copy** of the tree (never the committed workspace): add `markerWrite` / intrusive `fprintf` at `registerModuleSymbols` early-returns (`symbol_registrator.zig:422`, `:424`) logging `module_id`, `entry.state`, `entry.ast_root`, `root.kind`; add silent-alloc-failure and parser-truncation probes in the parse/import path. Build, run self-compile with `--markers`, parse the trace, and report:

1. Which early-return condition drops modules 1–4.
2. The exact corrupt value (state / ast_root==0 / root.kind).
3. Whether the mechanism is silent OOM, module-too-big truncation, or state/ast_root corruption.

All instrumentation is **reverted** before commit (working tree stays clean).

### Part C — Cadence

R1→R6 ladder → I-DROP → **STOP** (consolidated ruling) → **GATE** (corpus + docs reconciliation). An F-fix plan is a future plan, ruled on at STOP.

## Constraints

- No `sf/src` changes in the committed tree (I-DROP instruments only a /tmp copy; all reverted).
- Repro tasks do NOT rebuild `/tmp/fx_subfolder/zig1` (use the committed HEAD binary).
- Fixtures use the bare `@import("std")` + `std.io.printInt` convention (with documented `writeByte(' ')` separators where needed).
- All runs `timeout`-gated; `sf/build/out_release/` never touched.
- 4 MD5 gate values and corpus counts are unaffected (new dirs only, no emitted-output change).
- Zig-spec/grammar claims must be verified before accepted (operator standing requirement).

## Success Criteria

1. At least one R-rung turns RED, proving the drop is reproduced on a controlled fixture (not the full compiler).
2. I-DROP names the exact dropped condition + corrupt value and the trigger dimension.
3. The self-hosting mystery is reduced to an isolable, instrumented repro that a future F-plan can fix with confidence.
