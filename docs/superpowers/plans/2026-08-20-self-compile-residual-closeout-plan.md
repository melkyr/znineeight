# Self-Compile Residual Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining 425 self-compile C-emission errors (residual classes A₂, C₂, E₂) so `build_zig1_5.sh` reaches rc=0 and both binaries smoke on hello, with the 4 MD5 + corpus 287 + matrix 21/21 byte-identity gate holding.

**Architecture:** R → I → F → GATE. R builds one full-graph fixture per residual (A₂, C₂, E₂); I pins each upstream fix (read-only, STOP on forks); F applies each fix with a self-compile re-count == 0 gate; GATE reconciles docs. Full-graph fixtures (3+ module import chains reproducing the exact self-compile error text) are the binding correction over the prior plan.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), compiler under test `/tmp/fx_subfolder/zig1`, gcc -m32 -std=c89, `bash sf/scripts/build_release.sh`, 4 MD5 gates, corpus 287, matrix 21/21.

## Global Constraints

- **Emission-only.** Zero memory/determinism/runtime work. Fix scope: `sf/src/c89_emit.zig`, `sf/src/lower.zig`, `sf/src/semantic_analyzer.zig` only — no other files without an operator ruling.
- **Hard byte-identity gate:** 4 MD5s byte-identical — gol `9cf758d96f25d41980379564a5501bc8`, lisp `851c9ed307bc8dc9ac5920a323d371e1` (repo-root CWD, re-baselined AMENDMENT 5), json `9720478c937409a29fe23ae0199821cf`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. Corpus 287 `OK=276 FAIL=7 ICE=0 CRASH=0 GREEN=4` (+5 `emission_*_xmod` fixtures = 292 dirs). Matrix 21/21.
- **Runtime-priority override:** MD5 changes but emitted C still correct AND runtime-identical → STOP + propose re-baseline. MD5 changes with runtime/correctness doubt → STOP without proposing.
- **Fixture fidelity rule (binding):** each fixture is a 3+ module import chain; its gcc error text matches the self-compile error; an F-task gate is the **self-compile re-count of its class == 0**, not just fixture GREEN.
- **`sf/build/out_release/` WEDGED — never touch.** All runs `timeout 120`. `--output-dir` must pre-exist.
- **Build:** `bash sf/scripts/build_release.sh` → `=== [release] Done: /tmp/fx_subfolder/zig1 ===`; reinstall std (`cp sf/src/std.zig std_io.zig std_arena.zig std_net.zig /tmp/fx_subfolder/lib/`).
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.7: re-read region before each edit, bottom-to-top; fastedit: re-read after every edit, never `end_line = start_line - 1`).
- **Z98 constraints** (AGENTS.md §1.3): no anytype/@Type; concrete maps; `@intCast` i32↔usize; switch requires `else`.
- **The plan is the ONLY authority.** STOP on any issue/confusion. Root causes B and D are at 0 — do NOT touch their code.
- **Commit messages verbatim per task.**

---

### Task R: repro — full-graph fixtures for A₂, C₂, E₂

**Files:**
- Create: `repro/mi_matrix/emission_type_storage_extern_xmod/{main.zig, mod_a.zig, mod_b.zig, mod_c.zig, NOTES.md}` (A₂)
- Create: `repro/mi_matrix/emission_sibling_payload_scale_xmod/{main.zig, ... , NOTES.md}` (C₂)
- Create: `repro/mi_matrix/emission_void_temp_scale_xmod/{main.zig, ... , NOTES.md}` (E₂)
- Report: `.superpowers/sdd/task-R-residual-report.md`

**Consumes:** the 3 residual mechanisms in the spec. **Produces:** 3 RED full-graph fixtures.

- [ ] **Step 1: Fixture A₂ — type-storage global, multi-module definition + missing extern**

Mirror the self-compile `AstKind` shape exactly: a type owned by module `mod_a` (e.g. `pub const Color = enum { Red, Green, Blue };`), aliased via `const Color = @import("mod_a.zig").Color` in `mod_b` and `mod_c`, where `mod_c` does NOT include `mod_a`'s header in its emitted include chain but DOES reference the storage global `zG_<hash>_Color`. Run: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rA main.zig` then `cd /tmp/rA && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c`. Expected RED: `'zG_<hash>_Color' undeclared` in `mod_c` — the exact self-compile error shape. Record in NOTES.md.

- [ ] **Step 2: Fixture C₂ — sibling-payload conflation at scale**

A tagged union with ≥2 non-void variants, exercised through a multi-module chain (a module defines the union + a fn returning it; another module does a `switch`/field access on a variant). Expected RED: `incompatible types when assigning` (anon struct A vs anon struct B). Record in NOTES.md.

- [ ] **Step 3: Fixture E₂ — void-temp producer (lexer call-arg shape)**

A minimal program reproducing the lexer's call-argument void temp (`zT_<n> undeclared` where the arg temp's type stays void). Expected RED: `'zT_<n>' undeclared`. Record in NOTES.md.

- [ ] **Step 4: Verify all 3 RED with exact error text**

Re-run each; confirm the gcc error matches the self-compile residual text (not a different class).

- [ ] **Step 5: Commit**

Commit: `repro: self-compile residual fixtures (type-storage extern, sibling payload scale, void temp)`

---

### Task I: investigate — pin upstream fix per residual (read-only)

**Files:**
- Read: `sf/src/c89_emit.zig` (global def/extern emission — `:2336` extern, `:2441` def), `sf/src/lower.zig` (sibling payload, void-temp sites), `sf/src/semantic_analyzer.zig`
- Create: `.superpowers/sdd/task-I-residual-report.md` (no commit)

**Consumes:** R fixtures + spec residual table. **Produces:** per-residual fix design + STOP on forks.

- [ ] **Step 1: A₂ design — single-owner definition + extern propagation**

Determine where the type-storage global definition is emitted (which module, why multiple) and how to emit exactly ONE definition (the type's owner module) + an `extern` in every referencing module's header chain. Name the exact emitter functions/lines.

- [ ] **Step 2: C₂ design — sibling-payload at scale**

Pin why the payload-type conflation persists after F-C; name the exact site(s) to fix.

- [ ] **Step 3: E₂ design — void-temp producers**

Pin the lexer call-arg void-temp site + confirm the 38 switch-arm / 30 pal producers are covered by C₂/A₂ respectively (so E₂'s own fix is the lexer site only, if that's where it lands).

- [ ] **Step 4: Verify each fix would NOT change the 4 MD5s / corpus / matrix**

Reason about byte-identity per fix. Flag any design fork → STOP for operator ruling.

- [ ] **Step 5: Write report**

Report at `.superpowers/sdd/task-I-residual-report.md`. No commit (read-only).

---

### Task F: fix — apply the residual fixes (A₂, C₂, E₂)

**Files:**
- Modify: `sf/src/c89_emit.zig`, `sf/src/lower.zig`, `sf/src/semantic_analyzer.zig` (per I report)
- Report: `.superpowers/sdd/task-F-residual-report.md`

**Consumes:** I report. **Produces:** self-compile re-counts A₂==0, C₂==0, E₂==0.

- [ ] **Step 1: Apply each fix** (via `edit`/`fastedit`)

- [ ] **Step 2: Rebuild + reinstall std**

```bash
bash sf/scripts/build_release.sh
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```

- [ ] **Step 3: R fixtures GREEN**

Re-run each fixture: dump + gcc -c → 0 errors.

- [ ] **Step 4: Class re-count == 0 (the real gate)**

Regenerate the full self-compile error log and count each class:
```bash
bash scripts/self_compile/build_zig1_5.sh   # dumps 40 .c to /tmp/zig1_5/gen (may still fail gcc)
cd /tmp/zig1_5/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /workspace/znineeight/sf/src/include -c *.c 2>/tmp/emit_errs_res.txt
grep -c "zG_.*undeclared" /tmp/emit_errs_res.txt        # A₂ target 0
grep -c "zT_[0-9]*.*undeclared" /tmp/emit_errs_res.txt  # E₂ target 0
grep -c "incompatible types when assigning\|has no member" /tmp/emit_errs_res.txt  # C₂ target 0
```
Expected: A₂ == 0, E₂ == 0, C₂ == 0. Any nonzero → incomplete fix (iterate) or NEW shape (STOP and report).

- [ ] **Step 5: Full self-compile build + smoke (success gate)**

```bash
bash scripts/self_compile/build_zig1_5.sh
```
Expected: rc=0, `=== [zig1_5] Done: /tmp/zig1_5 ===`, both binaries produced. Smoke both on `examples/z98/hello/main.zig` (rc=0, `.c` emitted). If any gcc error remains → STOP.

- [ ] **Step 6: Byte-identity gate**

4 MD5s byte-identical + corpus 287 unchanged + matrix 21/21. MD5 change → runtime-priority override (STOP + propose re-baseline if correct, else STOP).

- [ ] **Step 7: Commit**

Commit: `fix: self-compile residual emission defects (type-storage extern, sibling payload, void temp)`

---

### Task GATE: reconcile docs + closeout

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Report: `.superpowers/sdd/task-GATE-residual-report.md`

**Consumes:** F result. **Produces:** reconciled tracking docs.

- [ ] **Step 1: Final gate sweep**

Re-verify 4 MD5s byte-identical, corpus 287 `OK=276 FAIL=7 ICE=0 CRASH=0 GREEN=4` (+5 fixtures = 292), matrix 21/21, `test_analyzer_bin` "5 passed, 4 failed".

- [ ] **Step 2: Update EXPECTED_FAIL.md**

Version bump + closeout section: the 3 residual classes fixed, the R fixtures (now GREEN), and the self-compile-now-buildable milestone.

- [ ] **Step 3: Update QUICK_REF.md**

Post-residual-closeout baseline paragraph: self-compile now produces a *buildable* `zig1_5` (gcc-compilable emitted C at full 40-module scale).

- [ ] **Step 4: Commit**

Commit: `docs: self-compile residual closeout GATE + reconciliation`
