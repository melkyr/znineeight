# Self-Compile Silent-Drop Repro & Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduce and isolate the "modules 1–4 silently dropped" bug (single root cause of 213 `error[3000] cannot declare variable of type void` during self-compile) down to a durable, minimal repro, and pin the mechanism (silent OOM / module-too-big / state-ast_root corruption) so a future fix plan can proceed with confidence.

**Architecture:** A six-rung repro ladder (simple → complex) isolating the trigger dimension, followed by one marker/fprintf-instrumented investigation task (on a /tmp copy, reverted after), then a consolidated STOP ruling and a GATE reconciliation. No `sf/src` changes land in the committed tree; no fix is implemented in this plan.

**Tech Stack:** Z98 dialect (no `anytype`/`@Type`), C89 emission, `--markers` + `markerWrite` + intrusive `fprintf` for instrumentation, `gcc -m32` corpus recipe.

## Global Constraints

- Compiler under test: the **existing** `/tmp/fx_subfolder/zig1` built from HEAD (do NOT rebuild during R tasks). Build recipe (only if ever needed): `bash sf/scripts/build_release.sh` gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`, then reinstall std: `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`.
- 4 MD5 gates (single-file `--dump-c89 | md5sum`, lisp from repo root): gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3`, mud `a1d0dd55aada9c3fd904ae33f54de32e`, json `fc357296537347a0ef58af49b5a40081`. This plan's tasks must NOT change gate/corpus emitted output (repros are new dirs only; I-DROP instrumentation is on a /tmp copy and fully reverted).
- Corpus: 269 dirs. Corpus recipe MUST be per-module (`--dump-c89 --output-dir DIR` then gcc each `.c`; stdout-concat falsely fails `fn_ptr_struct_field`).
- Fixture convention: bare `@import("std")` + `std.io.printInt`; documented `writeByte(' ')` separators where needed. RED = dump rc≠0 or `error[3000]` present; GREEN = dump/gcc/run rc=0 with expected output. Each fixture commits `main.zig` + `NOTES.md` only.
- All runs `timeout`-gated (e.g. `timeout 120 ...`). `sf/build/out_release/` is WEDGED — never touch/ls/build into it.
- edit/fastedit ONLY (no sed/python); source edits only via fastedit (re-read region before each edit; NEVER `end_line=start_line-1`; keep new_code a single contiguous block).
- Verification MUST scan the whole tree/closure for the defect class, never stop at the first error.
- Zig-spec/grammar claims MUST be verified against the online langref before acceptance.
- Z98 dialect: no `anytype`, no `@Type`.

---

### Task R1: sanity baseline — cross-module struct return at 2 modules

**Files:**
- Create: `repro/mi_matrix/voiddecl_struct_xmod_r1/main.zig`
- Create: `repro/mi_matrix/voiddecl_struct_xmod_r1/mod.zig`
- Create: `repro/mi_matrix/voiddecl_struct_xmod_r1/NOTES.md`

**Interfaces:**
- Consumes: nothing (self-contained fixture).
- Produces: the GREEN floor — proof that small-scale cross-module struct return does NOT trip the drop.

- [ ] **Step 1: Write the fixture**

`mod.zig`:

```zig
pub const Foo = struct {
    v: u32,
};

pub fn make() Foo {
    var f = Foo{ .v = 42 };
    return f;
}
```

`main.zig`:

```zig
const std = @import("std");
const mod = @import("mod.zig");
pub fn main() void {
    var x = mod.make();
    std.io.printInt(x.v);
}
```

- [ ] **Step 2: Run RED/GREEN check**

Run from the fixture dir:
```bash
cd repro/mi_matrix/voiddecl_struct_xmod_r1 && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/r1.c 2>/tmp/r1.err; echo "dump rc=$?"; ls -la /tmp/r1.c
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/r1.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/r1 2>/tmp/r1g.err; echo "gcc rc=$?"; timeout 30 /tmp/r1; echo "run rc=$?"
```
Expected: dump rc=0, gcc rc=0, run prints `42`, rc=0. **GREEN** (the floor — small scale does not trip).

- [ ] **Step 3: Write NOTES.md**

Record: purpose (sanity floor for the VOID-decl silent-drop ladder), fixture sources, GREEN result (dump/gcc/run rc, output `42`), and the baseline claim "cross-module struct return works at 2 modules".

- [ ] **Step 4: Commit**

```bash
git add repro/mi_matrix/voiddecl_struct_xmod_r1/
git commit -m "repro: cross-module struct return baseline (voiddecl_struct_xmod_r1)"
```
(If git commit SEGFAULTs, remove stale `.git/index.lock` and retry.)

---

### Task R2: import-chain depth

**Files:**
- Create: `repro/mi_matrix/voiddecl_chain_r2/{main.zig, a1.zig, a2.zig, ..., aN.zig, NOTES.md}`

**Interfaces:**
- Consumes: R1's GREEN floor (chain starts where R1 passes).
- Produces: whether linear import-chain depth trips the drop (N ∈ {5, 10, 20, 40}).

- [ ] **Step 1: Write the chain generator + fixtures**

Generate a linear chain `main → a1 → a2 → … → aN` where `aN` defines `pub const T = struct { v: u32 };` and `pub fn make() T`, and each `aK` (1 ≤ K < N) re-exports the next: `pub const a_next = @import("a{K+1}.zig");` (plus `pub fn make() T` forwarding if the dialect needs it — verify; the goal is `main` calls `a1.make()` and the terminal `T` struct return flows through). `main.zig`:

```zig
const std = @import("std");
const a1 = @import("a1.zig");
pub fn main() void {
    var x = a1.make();
    std.io.printInt(x.v);
}
```

Start with N=5. Run the RED/GREEN check per Step 2. Then escalate N ∈ {10, 20, 40} (regenerate the chain files). For each N record dump rc + presence of `error[3000]`.

- [ ] **Step 2: Run RED/GREEN check**

Same recipe as R1 Step 2 (from the fixture dir, output files `/tmp/r2*.c`). GREEN (all N): prints `42`. RED (any N): dump rc≠0 and/or `error[3000]`.

- [ ] **Step 3: Write NOTES.md**

Record each N's result in a table (N → rc → GREEN/RED → first error site if RED). Note the largest N that stays GREEN and whether any N trips the drop. If all N pass, state "chain depth alone does not trip; proceed to R3" (the ladder's discard-the-easy-resolution step).

- [ ] **Step 4: Commit**

```bash
git add repro/mi_matrix/voiddecl_chain_r2/
git commit -m "repro: import-chain depth probe (voiddecl_chain_r2)"
```

---

### Task R3: sibling module count + first-N drop

**Files:**
- Create: `repro/mi_matrix/voiddecl_count_r3/{main.zig, m1.zig, ..., mN.zig, NOTES.md}`

**Interfaces:**
- Consumes: R2 result.
- Produces: whether sibling module count drops the FIRST K modules (N ∈ {4, 8, 16, 32, 39}).

- [ ] **Step 1: Write the generator + fixtures**

N sibling modules `mK.zig`, each:

```zig
pub const S = struct { v: u32 };
pub fn make() S { var f = S{ .v = K }; return f; }
```

`main.zig` imports all N (`const m1 = @import("m1.zig");` … `const mN = @import("mN.zig");`) and calls every `mK.make()`, printing each `v` (with `writeByte(' ')` separators, then `printInt` for the sum). Start with N=4, then N ∈ {8, 16, 32, 39}.

- [ ] **Step 2: Run RED/GREEN check**

Per R1 recipe. Expected at small N: GREEN printing the K values. Key question: at which N (if any) does the FIRST imported module's call resolve to void (`error[3000]` at its `var`)? This isolates the "first-K dropped" pattern.

- [ ] **Step 3: Write NOTES.md**

Record the N → rc → GREEN/RED table; if RED, which module ids' calls error (first-K?).

- [ ] **Step 4: Commit**

```bash
git add repro/mi_matrix/voiddecl_count_r3/
git commit -m "repro: sibling module count probe (voiddecl_count_r3)"
```

---

### Task R4: interned identifier volume

**Files:**
- Create: `repro/mi_matrix/voiddecl_volume_r4/{main.zig, mod.zig, NOTES.md}`

**Interfaces:**
- Consumes: R3 result.
- Produces: whether interned identifier volume (1k/5k/10k) trips the drop (self-compile has 9,331).

- [ ] **Step 1: Write the generator + fixture**

`mod.zig`: thousands of `pub const vNNNN: u32 = NNNN;` (1k, then 5k, then 10k identifiers). `main.zig` references a representative subset (e.g. every 100th) and prints their sum, plus one struct-return call to a `pub fn make() Foo` in `mod.zig`:

```zig
const std = @import("std");
const mod = @import("mod.zig");
pub fn main() void {
    var s: u32 = 0;
    s += mod.v0000; s += mod.v0100; s += mod.v0200;
    std.io.printInt(s);
    var x = mod.make();
    std.io.printInt(x.v);
}
```

- [ ] **Step 2: Run RED/GREEN check**

Per R1 recipe at each volume (1k/5k/10k). Expected at 1k: GREEN. Key question: at which volume (if any) does the `mod.make()` struct return (or the identifier refs) start resolving to void?

- [ ] **Step 3: Write NOTES.md**

Record volume → rc → GREEN/RED table and the identifier-count threshold if tripped.

- [ ] **Step 4: Commit**

```bash
git add repro/mi_matrix/voiddecl_volume_r4/
git commit -m "repro: interned identifier volume probe (voiddecl_volume_r4)"
```

---

### Task R5: nested import tree

**Files:**
- Create: `repro/mi_matrix/voiddecl_nested_r5/{main.zig, root_a.zig, root_b.zig, ..., sub_*.zig, NOTES.md}`

**Interfaces:**
- Consumes: R4 result.
- Produces: whether a branching nested import tree trips the drop.

- [ ] **Step 1: Write the fixtures**

Root imports N children (`root_a`, `root_b`, …); each child imports M grandchildren; each grandchild defines a struct + `pub fn make()` returning it. `main` imports the roots and calls through to grandchild `make()`s. Shape mirrors a real module graph (e.g. N=6 children, each with M=4 grandchildren). Run the RED/GREEN check.

- [ ] **Step 2: Run RED/GREEN check**

Per R1 recipe. Record which depth/shape (if any) trips `error[3000]`.

- [ ] **Step 3: Write NOTES.md**

Record shape, rc, GREEN/RED, and which module positions error if RED.

- [ ] **Step 4: Commit**

```bash
git add repro/mi_matrix/voiddecl_nested_r5/
git commit -m "repro: nested import tree probe (voiddecl_nested_r5)"
```

---

### Task R6: self-hosting-shape mimic

**Files:**
- Create: `repro/mi_matrix/voiddecl_mimic_r6/{main.zig, m00.zig, ..., m38.zig, NOTES.md}`

**Interfaces:**
- Consumes: R1–R5 results.
- Produces: a reconstructed trigger (39 modules arranged like `sf/src` import order with representative identifier volume) OR a definitive negative (the drop cannot be reconstructed by shape/scale alone).

- [ ] **Step 1: Write the generator + fixtures**

Generate ~39 modules mirroring `sf/src`'s import order: module ids 1–4 correspond to allocator/string_interner/source_manager/diagnostics-like roles (each defining several structs + struct-returning fns that later modules and `main` call); the remaining modules each define a handful of structs/fns and import earlier modules in the same order. Include representative identifier volume (mix of the R4 pattern: each module carries a few hundred `pub const` identifiers). `main.zig` (module 0) calls struct-returning fns from the first-imported modules.

- [ ] **Step 2: Run RED/GREEN check**

Per R1 recipe. Key outcome: if RED, confirm it matches the self-compile signature (first modules' struct returns resolve to void); if GREEN, record that shape+scale alone does not reconstruct the drop and this is itself the isolation finding.

- [ ] **Step 3: Write NOTES.md**

Record the reconstructed layout, rc, GREEN/RED, and how closely it matches the real self-compile's marker signature.

- [ ] **Step 4: Commit**

```bash
git add repro/mi_matrix/voiddecl_mimic_r6/
git commit -m "repro: self-hosting-shape mimic (voiddecl_mimic_r6)"
```

---

### Task I-DROP: mechanism investigation (markers + intrusive fprintf)

**Files:**
- Modify (ONLY in a /tmp copy — never the committed tree): `sf/src/symbol_registrator.zig`, `sf/src/import_resolver.zig`, `sf/src/type_resolver.zig`
- Report: `.superpowers/sdd/task-I-DROP-report.md`

**Interfaces:**
- Consumes: R1–R6 ladder results (which rung trips).
- Produces: the exact dropped condition + corrupt value, and the mechanism verdict (silent OOM / module-too-big / state-ast_root corruption).

- [ ] **Step 1: Copy the tree to /tmp and instrument**

```bash
cp -r sf /tmp/idrop_src
```
In `/tmp/idrop_src/src/symbol_registrator.zig`, add `markerWrite`/fprintf logging at both `registerModuleSymbols` early-returns (`:422` and `:424`) printing `module_id`, `entry.state`, `entry.ast_root`, `root.kind`. In `/tmp/idrop_src/src/import_resolver.zig`, add silent-alloc-failure and parser-truncation probes in the parse/import path (log any `catch`ed failure that would previously be swallowed). In `/tmp/idrop_src/src/type_resolver.zig`, log `resolveFnSignatures` per-module entry and its `rt_box[0]` default.

- [ ] **Step 2: Build the instrumented compiler from the /tmp copy**

```bash
cd /tmp/idrop_src && bash sf/scripts/build_release.sh
```
(Gate: `=== [release] Done: /tmp/fx_subfolder/zig1 ===`.) Confirm the produced binary is the /tmp-instrumented one. Reinstall std into `/tmp/fx_subfolder/lib/` if the build wiped it.

- [ ] **Step 3: Run self-compile with markers and capture the trace**

```bash
timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig 2>/tmp/sc.err
grep -a "error[" /tmp/sc.err | grep -av "error[9999]" | head -20
grep -a "RSPL\|RS:\|FIX1\|RN:" /tmp/sc.err | head -80
```
Find the instrumentation output for modules 1–4 at symbol-registration time. Identify which early-return fires and the logged `state`/`ast_root`/`root.kind` values.

- [ ] **Step 4: Determine the mechanism**

Correlate the logged values against the three suspected mechanisms:
- Silent OOM → parse/import probes log a swallowed alloc failure for modules 1–4.
- Module-too-big → parser/registry buffer truncation visible in the probes.
- State/ast_root corruption → `state` or `ast_root` logged with a wrong (non-parsed / 0 / non-module_root) value at registration.
Also cross-check the R-ladder: which rung's dimension matches.

- [ ] **Step 5: Write the report**

Write `.superpowers/sdd/task-I-DROP-report.md` with: the exact early-return + logged values for modules 1–4; the mechanism verdict; the matching ladder rung; and a recommended F-plan entry point (instrumentation location, fix hypothesis). The /tmp copy and instrumentation are NOT committed.

- [ ] **Step 6: Revert + confirm clean tree**

```bash
cd /workspace/znineeight && git status --porcelain
```
Confirm zero source changes in the repo (all instrumentation stayed in /tmp). Working tree must be clean.

---

### Task STOP: consolidated ruling

**Files:**
- Modify: `docs/superpowers/plans/2026-08-18-self-compile-silent-drop-plan.md` (AMENDMENT section)

- [ ] **Step 1: Present findings**

Summarize the R-ladder (which rung tripped, which dimensions discarded) + the I-DROP report (mechanism verdict, corrupt value, fix entry point).

- [ ] **Step 2: Operator ruling**

Record the operator's ruling: whether the trigger is isolated, and whether an F-fix plan follows now or later. Amend the plan file with the ruling (plan-text AMENDMENT, following the established pattern).

---

### Task GATE: corpus + docs reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`

- [ ] **Step 1: Reconcile docs**

Bump `EXPECTED_FAIL.md` version; add a closeout record: the R-ladder fixtures (count, GREEN/RED per rung), the I-DROP mechanism finding, and the recorded next blocker (the VOID-decl family, with the isolated mechanism). Update `QUICK_REF.md` baseline line with the new corpus count. Record the trigger isolation — do NOT fix anything.

- [ ] **Step 2: Verify gates unaffected**

4 MD5 gates byte-identical; corpus count = prior + new fixture dirs; matrix unchanged. (No emitted-output change is possible — repro dirs only.)

- [ ] **Step 3: Commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs: silent-drop repro ladder GATE + reconciliation"
```

---

### Task M-FINAL: final whole-branch review

**Files:**
- None (review only).

- [ ] **Step 1: Generate the review package**

Run the superpowers skill's `scripts/review-package BASE HEAD` where BASE = the commit this plan started from (before the first R task). Pass the printed `.diff` path to a code-reviewer subagent (requesting-code-review template).

- [ ] **Step 2: Review**

Reviewer verifies: all ladder fixtures committed with valid NOTES.md; I-DROP report complete and instrumentation fully reverted (clean tree); docs reconciled truthfully; no `sf/src` changes landed; no gate impact.

- [ ] **Step 3: Fix wave if needed**

Address any Critical/Important findings (one fix subagent for all findings), then re-review. Record Minor findings in the ledger.

---

## AMENDMENT (2026-08-18) — u16 array-index overflow fix (whole-class sweep)

**Context.** I-DROP isolated the mechanism: modules 1-4 are silently dropped because `astStoreAddExtraChildren` (ast.zig:424) packs `(start << 16) | count` into the u32 `AstNode.payload`; when `store.extra_children.len >= 65536` during self-compile, `start << 16` wraps, module_root payloads decode to wrong regions, registration runs on garbage (0 named types), and cross-module struct refs fall to TYPE_VOID → 213x error[3000]. The R-ladder (R1-R6) all stayed below the boundary, so nothing tripped.

**Operator rulings (2026-08-18, question tool):**
1. Fix scope = the WHOLE class (not just extra_children): widen every `*_start: u16` index into the two unbounded arrays (`ast.extra_children`, `type_registry.xt_items`/`xn_items`) to u32. Repack sites `<< 16` → `<< 32`.
2. `AstNode.payload` u32 → u64, encoding `(start << 32) | count`, decode `>> 32` / `& 0xFFFFFFFF`. Accept AstNode growth 28 → 32 bytes. `*_count` fields stay u16.
3. Success gate: self-compile ADVANCES past the 213x error[3000] (modules 1-4 register cleanly).

**Task R1: scale repro crossing the boundary (voiddecl_boundary_xmod)**
- Create `repro/mi_matrix/voiddecl_boundary_xmod/`: N sibling modules, each carrying ~10k `pub const vNNNN: u32 = NNNN;` + one `pub const S = struct { v: u32 };` + `pub fn make() S`; `main.zig` imports all N, calls `m1.make()` (early) + `mLast.make()`, prints `.v`.
- Tune N so `ast.extra_children.len` crosses 65,536 (R4 showed ~10k extra_children per 10k-const module; N=7 → ~70k).
- RED: `error[3000]` on struct-return calls for modules parsed after the boundary. GREEN control: small N below boundary prints correctly. NOTES.md documents N, boundary crossing, RED/GREEN.
- Commit message: `repro: extra_children 65536 boundary probe (voiddecl_boundary_xmod)`.

**Task F1: the sweep (one implementer, two staged commits)**
- Commit 1 (extra_children path): ast.zig:126 `payload: u32`→u64; :128 `zzz_astnode_sz` → 32-byte layout; :424 encode `(start<<32)|count`; :428 decode `>>32`/`&0xFFFFFFFF`; :132 `FnProto.params_start: u16`→u32 (params_count stays u16); parser.zig:1444/1448 `param_start`→u32 (drop `@intCast(u16,…)`); repack sites `<<16`→`<<32` u64 result at analyzer.zig:407,784, lower.zig:5472, semantic_analyzer.zig:1653, type_resolver.zig:1228; audit every `AstNode.payload`/`astStoreGetExtraChildren` consumer for the u64 change.
- Commit 2 (type_registry path): type_registry.zig:79 `FnPayload.params_start`→u32; :80-84 `fields_start`/`members_start`/`elems_start`/`tags_start`→u32; :512/:523/:550 `GetOrCreateTuple/Fn/ErrorSet` `*_start: u16`→u32; truncation casts → u32 at symbol_registrator.zig:207, semantic_analyzer.zig:2090, type_resolver.zig:391,1226; update `GetOrCreate*` callers.
- Gates per commit: 4 MD5s byte-identical (gol 9cf758d9…, lisp 88dcb7f9…, mud a1d0dd55…, json fc357296…); corpus 269 unchanged; matrix 21/21; test_analyzer 5/4; R1 RED→GREEN; self-compile marker scan: RN: markers present for modules 1-4 and the 213x error[3000] resolved (or frontier advances to the next genuine blocker, recorded not fixed).

**Task GATE (amended):** after the existing GATE content, additionally record in the closeout: the u16-index-overflow mechanism, the whole-class sweep (payload u64 + all *_start u32), R1 fixture (boundary repro), and the new self-compile status. Corpus = 269 + R1 dir. 4 MD5s byte-identical. Version bump.

**Task M-FINAL (unchanged):** whole-branch review, BASE = `a441da3e`.
