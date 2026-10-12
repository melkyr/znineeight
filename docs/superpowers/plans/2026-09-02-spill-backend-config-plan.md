# zig1 Spill Backend Configurability + Additional Spill Gains + RSS Budget — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the user control over the memory/I-O tradeoff: disk-back the AST side tables for more gains, introduce a Disk/Ram spill backend selected by an immutable flag array, add `-mm<N>` (hard RSS budget, default 64 MB) and `-s<N>` (decremental spill levels, documented in `--help` + README), and unify the spill temp formats.

**Architecture:** Five phases: (1) I-SIDE/F-SIDE spill the remaining AST side tables; (2) I-FMT/F-FMT unify the spill temp formats (incl. `resolved_types` 10→5 B/node); (3) I-SBackend/F-SBackend introduce the `SpillStore` Disk/Ram abstraction and route all spills through it; (4) I-MM/F-MM + F-S add the config (hard budget + decremental levels via an immutable flag mask); (5) GATE sweeps all modes. Deactivation order = addition order (oldest spills first). Byte-identity holds in both Disk and Ram modes (same data, different location) — no dual codegen.

**Tech Stack:** Zig (sf/src), C89 (emitted C), pal.stream* (spill I/O), gcc -m32.

## Global Constraints

- **Deactivation order (addition order, operator-approved):** S-AST(nodes) → S-LIR → S-HASH → S-RES → S-SIDE(new). `-s0` = all on disk; increasing N deactivates from the head (→ Ram).
- **Spill-level mechanism:** an immutable (`const`) array of per-spill flags; `-s<N>` computes a mask that directly selects each spill's `SpillStore` backend.
- **`-mm<N>`:** hard RSS budget, **default 64 MB**, friendly `-mm64` syntax (MB), enforced via `checkCombinedPeak` (the M0 tripwire). Must not break the current `--max-mem` plumbing.
- **`-s<N>` + `-mm<N>` documented in `--help` output and the README.**
- **Byte-identity gates (authoritative):** gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `4591fef0` — keep byte-identical OR re-baseline with golden 9/9 runtime evidence (runtime is the bar).
- **Golden 9/9** fixtures; **self-compile** 41 `.c` / 0 err / 0 PANIC; **ref 0-warning** (`-O3 -Wall -Wextra -fsyntax-only`).
- **Spill I/O via `pal.stream*` only** (AMENDMENT 12: no self-declared externs); S-FIX-1 ICE discipline on short write/read/seek.
- Z98 dialect; `edit`/`fastedit` only; never touch `sf/build/out_release/`.
- Ledger `.superpowers/sdd/progress.md` (append per task); mnemoria `mnemoria --path .opencode/memory add --agent spillconfig-session --type <discovery|decision|pattern|problem>`.
- Report `.superpowers/sdd/task-SPILLCONFIG-report.md` (gitignored; WARNING `task-1-report.md` TRACKED never reuse; `task-brief` matches numeric "Task N" only — prefer self-contained dispatches).
- Pre-existing dirty files never staged: `docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `mnemoria/*`, untracked `build/`.
- Design doc: `docs/superpowers/specs/2026-09-02-spill-backend-config-design.md`.
- Compile recipe: `timeout 120 C --dump-c89 --output-dir DIR <entry>`; gcc `-m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c *.c`; link `zig_runtime.c` + `zig_pal.c`. Rebuild ref `timeout 900 bash sf/scripts/build_release.sh` + reinstall std lib. Self-compile `timeout 900 bash scripts/self_compile/build_zig1_5.sh`.

---

### Task I-SIDE: AST side-table census + read order (read-only)

**Files:**
- (Read) `sf/src/ast.zig` (side-table arrays + append/get), `sf/src/lower.zig`, `sf/src/semantic_analyzer.zig` (side-table readers)
- Report: append `## I-SIDE` to `.superpowers/sdd/task-SPILLCONFIG-report.md`

**Interfaces:**
- Consumes: design doc — side tables `extra_children`+`extra_ranges` ~1.4 MB + `identifiers`/int/float/string/`fn_protos` ~0.6–1.0 MB; I-TABLE precedent (read-order verdict decides disk-back viability).
- Produces: sizes + read-order verdict + disk-back viability for each side table → feeds F-SIDE.

- [ ] **Step 1: Measure each side table's live size at self-compile**

Using `--markers` (existing `measureMarkerWrite` instrumentation is off — use the I-4B /tmp instrumented-build pattern if needed) or by reading the emitted C sizes, record each side-table array's final length × element size at self-compile: `extra_children` (u32), `extra_ranges` (u64), `identifiers` (u32), `int_values` (u64), `float_values` (f64), `string_values` (u32), `fn_protos` (16 B). Rank by bytes.

- [ ] **Step 2: Enumerate readers + access order**

Grep the `astStoreGetExtraChildren` / side-table getters across lowering + semantic. Determine the access pattern (sequential-by-range-index vs random) during lowering — the I-TABLE read-order check. Note which tables are read only before lowering (freed by F-FREE anyway).

- [ ] **Step 3: Disk-back viability verdict + report**

For each table: is it big enough to matter, read sequentially (direct-offset block fault-in viable), and dead after lowering? STOP-present if a big table is catastrophically random-access. Append `## I-SIDE` to the report. NO `sf/src` edits, NO commit, NO ledger/mnemoria.

### Task F-SIDE: Disk-back the value pools `identifiers` + `int_values` (F)

**Files:**
- Modify: `sf/src/ast.zig` (getter + block spill for the value pools), the ~66 inline pool-read sites across `sf/src/{lower,analyzer,type_resolver,semantic_analyzer,symbol_registrator,comptime_eval,const_alias_prepass}.zig`
- Commit: `perf: disk-back AST value pools (identifiers/int_values fault-in)`

**Interfaces:**
- Consumes: I-SIDE verdict + the AMENDMENT-1 reframe (see below). The value pools (`identifiers`, `int_values`) are read as **u32/u64 values** via `astStoreNodePayload(node)` → pool-index → `pool.items[idx]` — VALUE semantics, no slice.
- Produces: `pool=` drop toward ~1.3 MB (identifiers 1.05 MB + int_values 0.26 MB cumulative).

**AMENDMENT 1 (operator-ruled 2026-09-02):** scope F-SIDE to **`identifiers` + `int_values` only** — whatever it yields. **Defer `extra_children` + `extra_ranges`** (the ast.c-contained pair I-SIDE ranked "cleanest") because they return **`[]const u32` SLICES** into the resident array (`astStoreNodeExtraChildren` ast.zig:661, `astStoreGetExtraChildren` ast.zig:635) — the S-INTERNER "retained slices" deal-breaker: a caller holding the slice across a later fault-in evicts the block → dangling pointer. Disk-backing them needs a copy-out API change (break the `[]const u32` return + all ~66 sites) or an index-based accessor (rewrite the iteration pattern) — a separate decision, not part of this task.

- [ ] **Step 1: Golden baseline capture**

`/tmp/golden_FSIDE/` (4 MD5 gate emissions + 9 fixtures + `--track-memory` baseline `pool=15324K`).

- [ ] **Step 2: Route the value-pool reads through getters**

Add value getters (e.g. `astStoreIdentifier(store, node)` / `astStoreIntValue(store, node)`) that resolve the payload → pool index → fault in the value's block → return the u32/u64 value. Replace the ~66 inline reads `store.<pool>.items[astStoreNodePayload(store, node)]` with the getter calls across the 7 reader files. This is mechanical (value semantics) — no slice, no retention hazard, byte-identity-safe (same value returned).

- [ ] **Step 3: Disk-back the two value pools**

Write `identifiers` + `int_values` through to disk during parse (append order = read order), replace the resident array with a direct-offset block fault-in + resident window (the F-TABLE pattern). Keep `string_values`/`fn_protos`/`float_values` resident (too small).

- [ ] **Step 4: Verify + measure + commit**

Gates: 4 MD5 byte-identical, golden 9/9, self-compile 41 `.c`/0 err/0 PANIC, ref 0-warning, `pool=` before/after. Commit verbatim message above.

### Task I-FMT: Spill-format unification evaluation (read-only)

**Files:**
- (Read) `sf/src/ast.zig`, `sf/src/lir_stream.zig`, `sf/src/resolved_type_table.zig`, `sf/src/module_registry.zig` (spill serialization)
- Report: append `## I-FMT` to `.superpowers/sdd/task-SPILLCONFIG-report.md`

**Interfaces:**
- Consumes: the four spill formats (AST 114,688 B blocks; LIR byte stream; RES 4090 B blocks / 10 B/node; HASH raw arrays) + F-SIDE's new format.
- Produces: a proposed **unified block/record format** (common header/shape + validation) covering all spills, incl. the `resolved_types` 10→5 B/node drop (dead source half).

- [ ] **Step 1: Document each spill's on-disk format**

For each spill: file layout, block/record size, offset math, header fields, validation present (S-FIX-1/3/5/7 guards), and any encoding waste (e.g. RES's dead source 5 B/node; AST record padding).

- [ ] **Step 2: Design the unified format**

Propose a common convention: consistent block sizing, a shared block header (magic/version/block-id/len) if any, offset math (byte offsets vs counts), and consistent validation. Include the `resolved_types` 10→5 B/node change (drop `source_items`/`source_flags` — provably dead at self-compile — or move them to a separate sparse file only when needed).

- [ ] **Step 3: Cost/benefit + report**

For each proposed change: byte-identity risk, pool effect, I/O effect, effort. STOP-present anything that would re-baseline gates without runtime equivalence. Append `## I-FMT` to the report. NO `sf/src` edits, NO commit.

### Task F-FMT: Apply the unified spill format (F)

**Files:**
- Modify: per I-FMT's approved scope (e.g. `sf/src/resolved_type_table.zig` for the 5 B/node change; `sf/src/ast.zig` if block-size convention changes)
- Commit: `refactor: unify spill temp format (per I-FMT)` (adjust if the applied scope differs — record in report)

**Interfaces:**
- Consumes: I-FMT's unified-format decision.
- Produces: byte-identical-or-re-baselined spills with the unified shape + the 5 B/node encoding.

- [ ] **Step 1: Golden baseline capture** (`/tmp/golden_FFMT/`).
- [ ] **Step 2: Apply the format changes** per I-FMT (write + read symmetric; keep offsets/validation consistent).
- [ ] **Step 3: Verify + measure + commit** (4 MD5 keep-or-re-baseline + golden 9/9; self-compile; ref 0-warning; `pool=` before/after). Commit verbatim message above.

### Task I-SBackend: SpillStore abstraction design (read-only)

**Files:**
- (Read) `sf/src/pal.zig` (stream*), `sf/src/ast.zig`, `sf/src/lir_stream.zig`, `sf/src/resolved_type_table.zig`, `sf/src/module_registry.zig` (all `streamOpen/Write/Read/Seek` call sites)
- Report: append `## I-SBackend` to `.superpowers/sdd/task-SPILLCONFIG-report.md`

**Interfaces:**
- Consumes: design doc's `SpillStore` abstraction (Disk = pal.stream*; Ram = growable sand buffer, offset-addressed).
- Produces: the exact `SpillStore` interface + the per-spill I/O-site census (every `pal.stream*` call to route) + the immutable flag-array design.

- [ ] **Step 1: Census every spill I/O site**

Grep each spill file for `streamOpen/streamWrite/streamRead/streamSeek/streamClose`. List every call site with its offset math + read/write direction.

- [ ] **Step 2: Design the `SpillStore` interface + backends**

Define `SpillStore` (write(off, bytes) / read(off, bytes) / open/close / seek semantics) with Disk (pal.stream*) and Ram (growable sand buffer, offset-addressed — reads/writes are buffer indexing) implementations. Design the Ram backend's buffer allocation (which arena; how it grows; whether it counts toward `pool.peak` — it must, since Ram mode keeps the data in the pool).

- [ ] **Step 3: Design the immutable flag array + mask**

Define the ordered spill registry (S-AST → S-LIR → S-HASH → S-RES → S-SIDE) and the immutable per-spill flag array; how `-s<N>` produces the mask (deactivate the first N → Ram) and how each spill consults its flag to pick Disk vs Ram at init/open time. Byte-identity argument: data identical, location differs.

- [ ] **Step 4: Report** — append `## I-SBackend` (interface + census + flag design). NO `sf/src` edits, NO commit.

### Task F-SBackend: Implement the SpillStore abstraction (F)

**Files:**
- Modify: `sf/src/pal.zig` (if Ram needs new primitives), the four+ spill files (route through `SpillStore`), `sf/src/allocator.zig` (Ram backend buffer, if arena-backed), `sf/src/main.zig` (flag plumbing)
- Commit: `refactor: route spills through SpillStore (Disk/Ram backend)`

**Interfaces:**
- Consumes: I-SBackend interface + census + flag design.
- Produces: all spills work in both Disk and Ram modes, selected by the flag array; byte-identical both modes.

- [ ] **Step 1: Golden baseline capture** (`/tmp/golden_FSBACKEND/`).
- [ ] **Step 2: Implement `SpillStore` + Disk/Ram backends** per I-SBackend.
- [ ] **Step 3: Route each spill through `SpillStore`** per the I-SBackend census (S-AST, S-LIR, S-HASH, S-RES, S-SIDE). Each spill picks its backend from the flag array.
- [ ] **Step 4: Verify + measure + commit** — 4 MD5 byte-identical in BOTH Disk and Ram modes; golden 9/9; self-compile; ref 0-warning; `pool=` Ram mode HIGHER (resident) than Disk mode by design. Commit verbatim message above.

### Task I-MM: `-mm<N>` semantics + current plumbing (read-only)

**Files:**
- (Read) `sf/src/main.zig` (`--max-mem`/`-m` plumbing), `sf/src/allocator.zig` (`checkCombinedPeak`, max_mem)
- Report: append `## I-MM` to `.superpowers/sdd/task-SPILLCONFIG-report.md`

**Interfaces:**
- Consumes: M0's `--max-mem` (space-syntax KB, default ≈ 16 GiB KB-semantics inactive).
- Produces: the `-mm<N>` spec (MB units, `-mm64` = 64 MB, default 64 MB when unset) + enforcement-point design.

- [ ] **Step 1: Document the current `--max-mem` plumbing**

`--max-mem`/`-m` parse (`main.zig`), `cli.max_mem` → `compiler_alloc.max_mem` → `checkCombinedPeak` gate (allocator.zig:219-228). Note the KB semantics + the 16 GiB default.
- [ ] **Step 2: Design `-mm<N>`**

`-mm<N>` = N MB hard pool ceiling; no `-mm` → default 64 MB (active); document how it interacts with (or supersedes) `--max-mem` (keep `--max-mem` as the legacy KB form, or fold — recommend in report). Enforced at `checkCombinedPeak` (ICE `memory limit exceeded`).
- [ ] **Step 3: Report** — append `## I-MM`. NO `sf/src` edits, NO commit.

### Task F-MM: Implement `-mm<N>` hard RSS budget (F)

**Files:**
- Modify: `sf/src/main.zig` (`-mm<N>` parse, MB units, default 64 MB), `sf/src/allocator.zig` (`checkCombinedPeak` / max_mem wiring)
- Commit: `feat: -mm<N> hard RSS budget (default 64MB)`

**Interfaces:**
- Consumes: I-MM spec.
- Produces: `-mm64` enforces a 64 MB ceiling (ICE on exceed); no `-mm` defaults to 64 MB active; small programs pass, huge inputs ICE with a clear message.

- [ ] **Step 1: Golden baseline capture** (`/tmp/golden_FMM/`).
- [ ] **Step 2: Implement `-mm<N>`** per I-MM (friendly switch, MB units, default 64 MB). Preserve `--max-mem` if I-MM recommends keeping it.
- [ ] **Step 3: Verify + measure + commit** — 4 MD5 byte-identical; golden 9/9; self-compile (64 MB ceiling must NOT trip self-compile at pool=15,324K); a canary `-mm1` must ICE; ref 0-warning. Commit verbatim message above.

### Task F-S: `-s<N>` decremental spill levels + docs (F)

**Files:**
- Modify: `sf/src/main.zig` (`-s<N>` parse → mask), the spill files (consult the flag array), `--help` text, README (docs section)
- Commit: `feat: -s<N> decremental spill levels (flag-mask) + help/README`

**Interfaces:**
- Consumes: I-SBackend flag-array design + F-SBackend implementation.
- Produces: `-s0` = all on disk (current), `-s1..-sN` deactivate from the head (S-AST first), documented in `--help` + README.

- [ ] **Step 1: Golden baseline capture** (`/tmp/golden_FS/`).
- [ ] **Step 2: Implement `-s<N>`** — parse, compute the mask from the immutable flag array (deactivate the first N), each spill picks its backend. `-s0` (default) = current behavior.
- [ ] **Step 3: Document** in `--help` + README: the meaning of each level, the deactivation order, and the memory/I-O tradeoff (higher `-s` = more RAM, less I/O; `pool=` rises accordingly).
- [ ] **Step 4: Verify + measure + commit** — 4 MD5 byte-identical at `-s0`; golden 9/9 across `-s0`, `-s1`, and the max level; self-compile clean at `-s0` (and each level that keeps enough spilled to fit); ref 0-warning; `pool=` per level recorded. Commit verbatim message above.

---

### Task GATE: Full sweep + reconciliation

**Files:**
- (Docs) `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Commit: `docs: spill backend config plan GATE + reconciliation`

- [ ] **Step 1: Full sweep across all modes**

4 MD5 byte-identical at `-s0` (all disk) and at each higher `-s` level that stays within the `-mm` budget; golden 9/9; matrix; corpus; self-compile 41 `.c`/0 err/0 PANIC; ref 0-warning.
- [ ] **Step 2: `pool=` per level + `-mm` enforcement**

Record `pool=` for `-s0..-sN`; confirm `-mm64` default holds self-compile (15,324 K < 64 MB) and `-mm1` ICEs; record the Ram-mode (resident) `pool=` for the max level.
- [ ] **Step 3: Reconciliation + commit**

Document the final `pool=` trajectory, the mode matrix, any re-baselines (with golden runtime evidence), and the README/help state. Commit the two docs with the verbatim message above.
