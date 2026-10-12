# Std-Lib Closeout Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out the 8 actionable std-lib final-review items (D2 compiler bug, printInt INT_MIN, host_is_windows config const, 2 spec-catalog doc fixes, emitSocketSelect #ifdef) + commit the /tmp build-script redirects. Track the 2 Win latents. D1 (search path) is a separate plan.

**Architecture:** T0 (commit redirects) → R1 (D2 repro) → I1 (D2 site + config-const point, batched) → combined STOP → F1 (D2) → F2 (config const) → F3 (misc batch) → F4 (gate sweep + tracking refresh).

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), zig1 (`/tmp/fx_subfolder/zig1`), gcc -m32 C89, std-lib modules (`sf/src/std*.zig`), tech docs (`sf/docs/tech_docs/*.md`).

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-60) is MANDATORY before any build/compile/run. Copy the exact commands; do not improvise flags.
- **Compiler under test:** `/tmp/fx_subfolder/zig1`. **`sf/build/out_release/` is WEDGED — any command touching it HANGS; use explicit timeouts on ALL such commands. Never touch out_release.** Rebuild: `bash sf/scripts/build_release.sh`, gate on `=== [release] Done: /tmp/fx_subfolder/zig1 ===`.
- **4 MD5 gates byte-identical** UNLESS operator-approved re-baseline with runtime proof (AMENDMENT B): gol `ff47d18dc8ef00e9b8f92f5e0a14c34a`, lisp `c1cb748b423eef191b9c9ce7023ae2a0`, json `376fd6812ef751913bdad00de676ceb6`, mud `fd0fdaa42a419b0e72cfdb3226a54c4a` (mud NOT a gate).
- **Corpus:** 246 dirs, OK=239/FAIL=3/GG=4. FAIL must not increase. FAIL=3 = field_store_drop, test_stub_0, self_embed_optional_cycle.
- **RUNTIME gate mandatory** (AGENTS §2.5.3): every fixed repro must run rc=0 AND print expected output. Compile-only gates FORBIDDEN.
- **Tech-doc maintenance (AGENTS §1.1.1):** every I-task and source-changing F-task updates the covering tech doc — `[updated: 2026-08-14]`.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; bottom-to-top). NO sed/python/bulk transforms. NO scope creep.
- **The plan is the ONLY authority.** Plan says A → do A. If you believe X/Y is better, STOP and present.
- **I-tasks report then STOP for combined operator ruling.** F-tasks do NOT start until the ruling.
- **D1 (`@import("std")` search path) is OUT OF SCOPE** — separate plan. Do NOT migrate std copies or touch the resolver.

---

### Task T0: Commit the /tmp redirects + F4 report edit

**Files:**
- Commit: `sf/scripts/build_release.sh`, `sf/scripts/differential_test.sh`, `.superpowers/sdd/task-F4-stdlib-report.md`

**Context:** These three files are operator-authorized uncommitted workarounds: build_release.sh OUT_DIR → /tmp/fx_subfolder, differential_test.sh ZIG1 → /tmp/fx_subfolder/zig1 (the wedged-out_release workaround, m0713), and the F4-report 48→47 correction. T0 formalizes them.

- [ ] **Step 1: Inspect the diff**
`git diff sf/scripts/build_release.sh sf/scripts/differential_test.sh .superpowers/sdd/task-F4-stdlib-report.md` — confirm only the authorized /tmp redirects + report edit are present, nothing else.
- [ ] **Step 2: Commit**
```bash
git add sf/scripts/build_release.sh sf/scripts/differential_test.sh .superpowers/sdd/task-F4-stdlib-report.md
git commit -m "build: point build/differential scripts at /tmp/fx_subfolder (out_release wedge workaround)"
```
- [ ] **Step 3: Verify no other uncommitted tracked files remain**
`git status` — working tree clean (untracked repro dirs from prior plans are fine).

**Gate:** commit scoped to exactly the 3 files; working tree clean of other tracked modifications.

---

### Task R1: D2 repro (std_arena module-instance ≥1 incomplete type)

**Files:**
- Create: `repro/mi_matrix/arena_multi_inst_xmod/{mod_a.zig,mod_b.zig,std_arena.zig,main.zig,std.zig,std_io.zig,NOTES.md}`
- Report: `.superpowers/sdd/task-R1-closeout-report.md`

**Interfaces:**
- Consumes: D2 defect (std-lib final review Imp-2): `_N` module-instance suffix on the std_arena struct typedef but NOT on fn-signature type refs → instance-≥1 consumer emits `return type is an incomplete type`.
- Produces: a reproducible gcc-FAIL gate for I1/F1.

**Context:** The std_arena module is imported at module-instance 0 (by mod_a) and module-instance 1 (by mod_b). The instance-1 emission hits the incomplete-type bug.

- [ ] **Step 1: Write the repro sources**

`repro/mi_matrix/arena_multi_inst_xmod/std_arena.zig`:
```zig
pub const Arena = struct {
    data: [*]u8,
    capacity: u32,
    used: u32,
};

pub fn create() Arena {
    return Arena{ .data = undefined, .capacity = @intCast(u32, 0), .used = @intCast(u32, 0) };
}
```

`repro/mi_matrix/arena_multi_inst_xmod/mod_a.zig`:
```zig
const arena_mod = @import("std_arena.zig");

pub fn makeA() arena_mod.Arena {
    return arena_mod.create();
}
```

`repro/mi_matrix/arena_multi_inst_xmod/mod_b.zig`:
```zig
const arena_mod = @import("std_arena.zig");

pub fn makeB() arena_mod.Arena {
    return arena_mod.create();
}
```

`repro/mi_matrix/arena_multi_inst_xmod/main.zig`:
```zig
const std = @import("std.zig");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var a = mod_a.makeA();
    var b = mod_b.makeB();
    std.io.printInt(@intCast(i32, a.used + b.used));
}
```

`std.zig` = io-only (`pub const io = @import("std_io.zig");`), `std_io.zig` byte-identical to `repro/mi_matrix/union_literal_nested_xmod/std_io.zig` (post-F4 convention).

- [ ] **Step 2: Verify the RED state**

Multi-module dump (`mkdir -p /tmp/r1 && /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r1 repro/mi_matrix/arena_multi_inst_xmod/main.zig 2>/tmp/r1/err`), then gcc compile inside /tmp/r1. Expected: rc≠0 with `return type is an incomplete type` (or the observed D2 error class) in mod_b's emitted C. Record the exact error + which module/line.

- [ ] **Step 3: zig0 oracle on a /tmp copy**

zig0 writes beside the source — copy to /tmp, run. Expected: compiles clean (rc=0). This is the post-fix reference.

- [ ] **Step 4: Write NOTES.md + report**

NOTES.md mirrors `union_literal_nested_xmod/NOTES.md` (What it tests / compiler gap with file:line / measured result / oracle / expected classification). Report: `.superpowers/sdd/task-R1-closeout-report.md`.

- [ ] **Step 5: Commit**
```bash
git add repro/mi_matrix/arena_multi_inst_xmod/
git commit -m "repro: std_arena module-instance>=1 incomplete type (arena_multi_inst_xmod)"
```

**Gate:** RED reproduced with evidence (exact gcc error); zig0 oracle clean; NOTES.md + report written; committed.

---

### Task I1: D2 emitter site + host_is_windows config point (batched)

**Files:**
- Investigate: `sf/src/c89_emit.zig` (module-instance `_N` suffixing), `sf/src/comptime_eval.zig` (`host_is_windows`)
- Modify (docs): covering tech doc (check `sf/docs/tech_docs/INDEX.md` Table A — likely `08_c89_emission.md` for D2, `05_semantic_analysis.md` or `00_shared_infra.md` for the config point)
- Report: `.superpowers/sdd/I1-closeout-report.md`

**Interfaces:**
- Consumes: R1 repro `arena_multi_inst_xmod/`, D2 context (instance `_N` suffix), `host_is_windows` const at `comptime_eval.zig:19`.
- Produces: exact D2 emitter locus + fix recommendation; config-const placement; tech-doc updates; blast radius.

**Context:** D2: the emitted struct typedef carries a `_N` module-instance suffix but the fn-signature type references (e.g. `pub fn makeB() arena_mod.Arena`) don't — so instance-≥1 consumers reference an incomplete type. `host_is_windows` is a hardcoded `= false` const at `comptime_eval.zig:19`.

- [ ] **Step 1: Confirm the D2 emitter mechanism**

Read `sf/src/c89_emit.zig` for module-instance suffixing (search "instance", "_", the emitted `zT_..._N` naming). Find: (a) where struct typedef names get the instance suffix; (b) where fn-signature / return-type references are rendered; (c) why they disagree at instance ≥1. Confirm the R1 error maps to this. Report exact file:line.

- [ ] **Step 2: Assess D2 blast radius**

Which emitted constructs hit the instance-≥1 path? Only multi-module programs where a module's `pub fn` returns/params reference a type defined in a module compiled at a different instance count. Grep examples/repros for `std_arena` multi-import (only arena_multi_inst_xmod — verify). Which MD5 gates would change with a fix (mud_server/rogue_mud omit arena — verify 0 gate impact)?

- [ ] **Step 3: Confirm the host_is_windows config point**

Read `comptime_eval.zig:19` + the `@isWindows` fold path. Confirm the minimal config-const placement (a `pub const` in a small config module OR keeping it in comptime_eval but clearly named/documented as the single flip point). Recommend which, matching operator m0983 (config const, no CLI).

- [ ] **Step 4: Update the covering tech doc(s)**

Document current D2 behavior + gap, corrected refs, `[updated: 2026-08-14]`. No compiler code changes.

- [ ] **Step 5: Write the I-report**

`/workspace/znineeight/.superpowers/sdd/I1-closeout-report.md`: D2 locus (file:line), fix options (recommend the operator-ruled one at the STOP), config-const placement, blast radius, concerns.

**Gate:** D2 locus confirmed with file:line; config-const point identified; tech doc updated; blast radius assessed. No compiler code changes.

**Report back — combined STOP for operator ruling on F1 (D2) + F2 (config const).**

---

### Task F1: Fix D2 (module-instance ≥1 arena incomplete type)

**Files:**
- Modify: `sf/src/c89_emit.zig` (per I1 ruling)
- Modify (docs): `08_c89_emission.md`
- Test: `repro/mi_matrix/arena_multi_inst_xmod/`

**Interfaces:**
- Consumes: I1 ruling, R1 repro.
- Produces: fn-signature type refs carry the same instance suffix as the typedef (or equivalent per ruling) — instance-≥1 consumers emit complete types.

- [ ] **Step 1: Implement per I1 ruling**
- [ ] **Step 2: Build + verify repro green:** dump rc=0, gcc compile rc=0, link rc=0, run rc=0 printing `0` (a.used + b.used = 0)
- [ ] **Step 3: Verify no regression:** F1-F6 lisp repros still green; 4 MD5 gates byte-identical (verify arena-suffix change doesn't touch gate emitted-C)
- [ ] **Step 4: Update tech doc `08_c89_emission.md` to FIXED**
- [ ] **Step 5: Commit**
```bash
git add sf/src/c89_emit.zig sf/docs/tech_docs/08_c89_emission.md
git commit -m "fix: module-instance type refs carry instance suffix (arena_multi_inst_xmod)"
```

**Gate:** repro green (dump/gcc/link/run rc=0, prints `0`); 4 MD5s byte-identical; tech doc updated.

---

### Task F2: `host_is_windows` config-module const

**Files:**
- Modify: config const location (per I1 ruling — e.g. `sf/src/comptime_eval.zig` or a new `sf/src/target.zig`) + its importers
- Modify (docs): covering tech doc
- Test: `@isWindows()` fold still 0; console builtin test still green

**Interfaces:**
- Consumes: I1 ruling.
- Produces: a single documented const that a Windows build flips; no CLI flag.

- [ ] **Step 1: Implement per I1 ruling** (config const, `= false`, imported by the `@isWindows` fold path)
- [ ] **Step 2: Build + verify:** `console_builtin_test` still folds `@isWindows()` → 0; emitted C unchanged
- [ ] **Step 3: Verify 4 MD5 gates byte-identical**
- [ ] **Step 4: Update tech doc**
- [ ] **Step 5: Commit**
```bash
git add sf/src/... sf/docs/tech_docs/...
git commit -m "refactor: host_is_windows as single config const for Windows builds"
```

**Gate:** `@isWindows()` folds 0; 4 MD5s byte-identical; tech doc updated.

---

### Task F3: printInt INT_MIN + spec-catalog doc fixes + emitSocketSelect #ifdef

**Files:**
- Modify: `sf/src/std_io.zig` (printInt), `docs/superpowers/specs/2026-08-08-multimodule-emission-defects-design.md` or the std-lib spec (catalog sigs — use the doc that carries the wrong rows), `sf/src/c89_emit.zig` (emitSocketSelect #ifdef)
- Modify (docs): covering tech doc
- Test: throwaway /tmp `printInt(-5)` + `printInt(-2147483648)`; net_builtin_test

**Interfaces:**
- Consumes: std-lib final-review Min-1/2/3/6.
- Produces: printInt correct for INT_MIN and -5; spec catalog rows match implementation; emitSocketSelect #ifdef-guarded.

- [ ] **Step 1: Fix `std_io.printInt`**

In `sf/src/std_io.zig` printInt (the `v = @intCast(u32, 0 - n)` site, ~line 26), replace with the i64-widened negation:
```zig
var v: u32 = @intCast(u32, 0 - @intCast(i64, n));
```
Verify this compiles under zig1 (the F4-reviewer verified it works for both `-5` → magnitude 5 and INT_MIN → 2147483648; the earlier `@intCast(u32, n)` alternative breaks `-5`).

- [ ] **Step 2: Verify printInt via /tmp throwaway**

Build a /tmp test calling `std.io.printInt(@intCast(i32, -5))` and `std.io.printInt(std.math.minInt(i32))` (or `@intCast(i32, -2147483648)`). Expected: `-5` prints and INT_MIN prints without panic. Confirm INT_MIN output `-2147483648` (or the magnitude, per the sign-handling the fix produces — verify actual output).

- [ ] **Step 3: Fix the spec catalog rows**

In the std-lib spec (`docs/superpowers/specs/2026-08-08-...-design.md` or wherever the wrong `@socketCreate() i32` / `@socketSelect` rows live): correct to `@socketCreate(port: u16) i32` and the 5-arg `@socketSelect`. Add the `@sleepMs` OpenWatcom-arm disposition note (2-way `_WIN32/#else` per zig0 source).

- [ ] **Step 4: Add the #ifdef guard to `emitSocketSelect`**

Mirror net_runtime.c's guard (identical arms) around the emitted select body in `sf/src/c89_emit.zig`.

- [ ] **Step 5: Verify gates**

4 MD5s byte-identical (printInt change only affects examples that print — verify which; net_builtin_test still rc=0; net_builtin_test emitted C `#ifdef` present).

- [ ] **Step 6: Update tech doc**
- [ ] **Step 7: Commit**
```bash
git add sf/src/std_io.zig sf/src/c89_emit.zig <spec-doc> sf/docs/tech_docs/...
git commit -m "fix: printInt INT_MIN + spec catalog sigs + socketSelect ifdef guard"
```

**Gate:** printInt `-5` + INT_MIN correct (no panic); spec rows match impl; emitSocketSelect #ifdef present; 4 MD5s byte-identical; tech doc updated.

---

### Task F4: Gate sweep + tracking-entry refresh

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, covering tech docs
- Report: `.superpowers/sdd/task-F4-closeout-report.md`

**Interfaces:**
- Consumes: F1-F3 fixes.
- Produces: final manifest reflecting post-closeout state; tracking entries for Win latents refreshed.

- [ ] **Step 1: Full 21-example matrix (MEM4 recipe)**
- [ ] **Step 2: Verify 4 MD5 gates**
- [ ] **Step 3: Corpus sweep (246 dirs) + test_analyzer_bin PASS**
- [ ] **Step 4: EXPECTED_FAIL.md version bump + tracking entries** — Win32 WSAStartup + Win-arm-untested stay latent (documented); D2 + printInt + config-const fix records
- [ ] **Step 5: QUICK_REF.md baseline**
- [ ] **Step 6: Commit**
```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md <tech docs>
git commit -m "docs: std-lib closeout gate sweep + tracking entries"
```

**Gate:** 21/21 matrix; 4 MD5s byte-identical; corpus no new FAIL; EXPECTED_FAIL + QUICK_REF + tech docs consistent.
