# Self-Compile C-Emission Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 5 C-emission defect classes so `zig1` produces a compilable `zig1_5` (self-compiled compiler): `build_zig1_5.sh` completes with 0 gcc errors, both binaries smoke on hello, and the 4 MD5 + corpus 287 + matrix 21/21 byte-identity gate holds.

**Architecture:** D → R → I → I-E → I-A → I-FA2 → F-A..F-E → GATE pipeline. D maps the 5 error classes to root causes (read-only); R builds one minimal RED fixture per independent root cause; I pins the upstream-correct fix per root cause (read-only, STOP on design forks); **I-E pins the E1 design + triages the class-1b residual (read-only, AMENDMENT 1)**; **I-A pins the upstream A fix — type-identity keying (read-only, AMENDMENT 3)**; **I-FA2 pins the import-expr field-access resolution fix that makes the type-storage discriminator fire at load/store sites (read-only, AMENDMENT 4)**; **F is split into F-A..F-E — one fix task per root cause (AMENDMENT 1)**; GATE reconciles docs.

> **OPERATOR RULING (2026-08-20, AMENDMENT 1):** (1) Lower.zig fixes are approved — "I don't have a concern if the files are different from the plan"; root causes C (C1) and E (E1) are fixed in `lower.zig` as their upstream-correct location. (2) An I-E follow-up task pins E1's which-variant-payload derivation (the I report left a `<variant payload type_id>` placeholder) and triages the 202 class-1b errors into shapes before any F-E code. (3) F is split into F-A, F-B, F-C, F-D, F-E — one per root cause, each independently gated + reviewed. (4) A1 (kind-G module-independent mangle key) accepted, with an F-A grep gate for same-named user globals. E2 (emitter `int zT_n` fallback) rejected as a patch. C2 (emitter name+type dedup) rejected in favor of C1.

> **OPERATOR RULING (2026-08-20, AMENDMENT 2):** I-E findings accepted (option a). F-E re-scoped to three parts: **E1** (bindOptionalCapture tagged-union branch — latent-correct, first-non-void-variant derivation), **E1c** (variant-payload field access `inst.<variant>.<field>` — the dominant class-1b producer, root `semantic_analyzer.zig:607` + `lower.zig:2450-2458`, ~115 errs), and **tag-test** (if (union.field) compares runtime tag vs variant index, `lower.zig:4225-4237` — required for the R fixture to print 7). F-E runs AFTER F-A and F-C (their ~68 class-1b errors collapse first); it re-measures the class-1b residual before the full self-compile gate.

> **OPERATOR RULING (2026-08-20, AMENDMENT 3):** F-A BLOCKED — A1 (drop `module_id` for kind G) MERGED json's `g_arena` (defined in both `file.zig` and `json.zig`) → json MD5 changed, NOT a re-baseline case. The root flaw is kind-G overloading (type-storage globals = shared, user globals = per-module). A new **I-A** follow-up task pins the upstream fix (type-identity keying) — answer two questions: (1) what identity key makes type-storage globals one name without merging user globals, (2) where the type-storage-vs-user discriminator is available at mangle time. F-A is re-scoped to implement the I-A result (revert the A1 working-tree edit first; json gate must stay byte-identical).

> **OPERATOR RULING (2026-08-20, AMENDMENT 4):** F-A was implemented per the I-A pinned design (commit `c98590b7`, `nameManglerMangleGlobal` + 4 kind-G sites) and passed all byte-identity gates (4 MD5s incl. json `9720478c…`, corpus/matrix zero regression), BUT the fixture `emission_mangler_collision_xmod` stayed RED (`gcc rc=1`): the type-storage discriminator `types_items[type_id].name_id == name_id` fires at the def/extern/store sites (tmod `_Color_2`) but NOT at the cmod1/cmod2 `load_global` sites, because the load result temp is typed builtin int (tid 18) rather than the Color type (tid 29). The operator asked whether any of the 3 F-A report options (a: resolve decl type from `emitter.global_decls`; b: `is_type_storage` flag; c: fix load-temp typing in lowering) was upstream, else find an alternative. **Investigation (read-only) found NONE of (a)/(b)/(c) is upstream, and confirmed option 1 — a `semantic_analyzer.zig` fix**: `semanticAnalyzerResolveFieldAccess` resolves an `ident_expr`-base `m.X` field access through the module symbol (module branch at `:372-389` → returns `fs.type_id` = Color 29), but has **no `import_expr`-base branch**, so `@import("m").X` falls through to `:431` → `semanticAnalyzerResolveExpr(import_expr)` = `TYPE_VOID` (`:1609`) → returns VOID. Consequently `s.type_id` stays 0 and `resolvedTypeTableGet(s.decl_node)` yields int for the import-based alias, so the already-committed I-A discriminator can never fire there. **This is the real upstream root cause: `const Color = @import("color.zig").Color` must resolve identically to `const Color = color.Color`.** A new **I-FA2** read-only task pins the exact `semanticAnalyzerResolveFieldAccess` `import_expr`-base change (operator-confirmed as option 1); F-A is then amended to implement it on top of the committed `c98590b7`.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), compiler under test `/tmp/fx_subfolder/zig1`, gcc -m32 -std=c89, `bash sf/scripts/build_release.sh`, 4 MD5 gates, corpus 287, matrix 21/21.

## Global Constraints

- **Emission-only.** Zero memory (AST-spill/16 MB) work; zero determinism/runtime/memory (correctness-plan T3-T6) work. Fix scope: `sf/src/c89_emit.zig` (A, B, D), `sf/src/lower.zig` (C1, E1) per AMENDMENT 1, and `sf/src/semantic_analyzer.zig` (I-FA2 import-expr field-access resolution) per AMENDMENT 4 — no other files.
- **Hard byte-identity gate:** 4 MD5s byte-identical — gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3` (repo-root CWD), json `9720478c937409a29fe23ae0199821cf`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. Corpus 287 `OK=276 FAIL=7 ICE=0 CRASH=0 GREEN=4`. Matrix 21/21.
- **Runtime-priority override:** if a fix changes an MD5 but the emitted C is still correct AND runtime-identical, STOP and report to operator + propose a re-baseline. If MD5 changes with any runtime/correctness doubt, STOP without proposing.
- **`sf/build/out_release/` is WEDGED — NEVER touch/list/build into it.** All compiler runs `timeout 120`.
- **Build:** `bash sf/scripts/build_release.sh` → gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`; then reinstall std: `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`.
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.7: re-read region before each edit, bottom-to-top; fastedit: re-read after every edit, never `end_line = start_line - 1`).
- **Z98 constraints** (AGENTS.md §1.3): no anytype/@Type; concrete maps; `@intCast` for i32↔usize; switch requires `else`.
- **The plan is the ONLY authority.** STOP on any issue/confusion. Do not fix anything outside the 5 classes.
- **Commit messages verbatim per task.**

---

### Task D: discovery — map 5 error classes to root causes

**Files:**
- Read: `sf/src/c89_emit.zig` (emitter), `sf/src/lir.zig`, `sf/src/lower.zig` (as needed to trace)
- Create: `.superpowers/sdd/task-D-emission-report.md` (report, read-only — no commit)

**Consumes:** the 5-class table in the spec. **Produces:** `class → root-cause → emitter-site` map + which classes share a root cause + which classes are self-compile-only vs latent-in-corpus.

- [ ] **Step 1: Regenerate the failed build, capture per-class error list**

Run: `bash scripts/self_compile/build_zig1_5.sh` — expected to FAIL at `gcc -c` (rc=1). Then run:

```bash
cd /tmp/zig1_5/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /workspace/znineeight/sf/src/include -c *.c 2> /tmp/emit_errs.txt; echo "rc=$?"
```

- [ ] **Step 2: Bucket every error into its class**

For each of the 5 classes, count errors and collect representative `file:line` examples + the exact emitted-C text + the mangled identifier involved. Verify the counts are stable vs the T2 baseline (1195 errors / 16 files; class 1 ~190, class 2 ~200, class 5 = 9).

- [ ] **Step 3: Trace each class to its emitter site**

For class 1 (`zG_` enum globals): identify where enum constants are referenced as globals (kind-1 mangling, `nameManglerMangle` `c89_emit.zig:400-475`) vs where their definition SHOULD be emitted but isn't. Grep `c89_emit.zig` for the enum-constant emission path and the `.enum_const => |ec|` arms (`:2672`, `:5058`). For classes 2-5, trace the corresponding temp-decl / anon-type / payload / void-as-value emission sites.

- [ ] **Step 4: Determine shared vs distinct root causes**

Write the report with a `class → root-cause → site(s)` table, marking which classes are distinct root causes and which are the same bug. This table drives the R-task fixture count (one fixture per *independent* root cause).

- [ ] **Step 5: Write report**

Report at `.superpowers/sdd/task-D-emission-report.md`. No commit (read-only).

---

### Task R: repro — one RED fixture per root cause

**Files:**
- Create: `repro/mi_matrix/<name>_xmod/{main.zig,NOTES.md}` (one dir per independent root cause, named per the D report)
- Report: `.superpowers/sdd/task-R-emission-report.md`

**Consumes:** D report (root-cause list). **Produces:** RED fixtures — each minimal input that reproduces its class's bad C emission under the current `/tmp/fx_subfolder/zig1`.

- [ ] **Step 1: For each root cause, write a minimal fixture**

Each fixture is the smallest Z98 program that triggers the class (e.g. for class 1: an enum with many variants, some referenced as compile-time globals; for class 2: a function with enough temps to collide; for class 3: a `switch` producing an anonymous type; for class 4: a tagged-union payload field access; for class 5: a void-fn call in value position). Mirror the existing `xmod` fixture style (see `repro/mi_matrix/widthbits_union_intconst_xmod/`).

- [ ] **Step 2: Verify RED on each fixture**

Run (from the fixture dir where the fixture imports `std`): `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rfx <fixture main.zig>` then `cd /tmp/rfx && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c`. Expected: the same gcc error class as the full self-compile. If a class cannot be reproduced minimally, record it in NOTES.md and report DONE_WITH_CONCERNS (do NOT fake a fixture).

- [ ] **Step 3: Write NOTES.md per fixture**

Each NOTES.md: fixture source, RED evidence (exact gcc error + rc), the root cause it pins, expected post-fix result.

- [ ] **Step 4: Commit**

Commit: `repro: self-compile emission defects (<class-name>_xmod fixtures)`

---

### Task I: investigate — pin the upstream-correct fix per root cause

**Files:**
- Read: `sf/src/c89_emit.zig` (targeted sites from D)
- Create: `.superpowers/sdd/task-I-emission-report.md` (report, read-only — no commit)

**Consumes:** D report + R fixtures. **Produces:** per-root-cause fix design (the correct emitter change, NOT a patch of emitted text), plus STOP if any design fork needs an operator ruling.

- [ ] **Step 1: For each root cause, identify the correct emitter fix**

Design the change in `c89_emit.zig` that makes the emitted C correct (e.g. for class 1: emit the `zG_` enum-constant definition when it is referenced — or stop referencing it as a global and use the existing `zT_` macro). For each, name the exact function/line to change and the shape of the change.

- [ ] **Step 2: Verify the fix would NOT change the 4 MD5s / corpus / matrix**

Reason about whether the fix path is also reachable from any of the 287 corpus dirs or 21 examples. If a fix WOULD change existing-correct output, flag it as a design fork.

- [ ] **Step 3: Flag design forks → STOP for operator ruling**

If any root cause has two valid fixes with different byte-identity risk, present them and STOP. Otherwise proceed.

- [ ] **Step 4: Write report**

Report at `.superpowers/sdd/task-I-emission-report.md`. No commit (read-only).

### Task I-E: pin E1 design + triage class-1b residual (read-only)

**Files:**
- Read: `sf/src/lower.zig:1283-1303` (`bindOptionalCapture`), `sf/src/type_registry.zig`, `sf/src/c89_emit.zig` (as needed)
- Create: `.superpowers/sdd/task-IE-emission-report.md` (report, read-only — no commit)

**Consumes:** I report (E fork). **Produces:** E1 design fully pinned — the which-variant-payload derivation replacing the `<variant payload type_id>` placeholder — plus a class-1b (202) shape triage.

- [ ] **Step 1: Pin the which-variant-payload derivation for E1**

The I report's E1 sketch leaves `<variant payload type_id>` unresolved. Determine, from the emitted C + `bindOptionalCapture` + the type registry, how an `if (union) |v|` capture must derive the payload type (which variant is the non-null/payload variant). Name the exact type-id derivation (type_registry fields, variant-index source). If `if`-capture on a tagged union cannot determine a unique payload variant, document the constraint (e.g. single-payload-variant unions only) and the resulting scope.

- [ ] **Step 2: Triage the 202 class-1b errors by shape**

From `/tmp/emit_errs.txt` (or regenerate via `cd /tmp/zig1_5/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /workspace/znineeight/sf/src/include -c *.c 2>/tmp/emit_errs.txt`), bucket the 202 `zT_<n> undeclared` errors: how many are the if-capture family (fixed by E1) vs a second shape (e.g. the int_cast chain `zT_1159 = (unsigned int)zT_1158;`). Report counts + representative sites + whether a second fix (E1b) is needed.

- [ ] **Step 3: Write report + STOP if a second shape needs design**

Report at `.superpowers/sdd/task-IE-emission-report.md`. If a second class-1b shape exists and needs its own design, present it (may extend F-E scope). No commit (read-only).

---

### Task I-A: pin the upstream A fix — type-identity keying (read-only)

> **AMENDMENT 3 (2026-08-20):** F-A was BLOCKED — A1 (drop `module_id` for all kind G) fixed the type-storage collision but MERGED user globals: json_parser defines `g_arena` in BOTH `file.zig` and `json.zig`, and A1 collapsed them into one C symbol → json MD5 changed (`fb846433…` vs `9720478c…`), so json is NOT a re-baseline case. A1's root flaw: **kind G (`kind == 1`) is overloaded** — it carries both type-storage globals (shared, one runtime descriptor per type) AND user module globals (per-module storage). The upstream fix must key type-storage globals by the **type they store** (not by `(name_id, module_id)`), while user globals keep per-module keying. This I-A task pins that fix precisely (read-only); F-A is then amended to implement it.

**Files:**
- Read: `sf/src/c89_emit.zig:400-479` (`nameManglerMangle`), `:2330-2348` (extern decls), `:2436-2452` (`emitGlobalDecls`), `:4387-4431` (`load_global`), `:4433-4449` (`store_global`); `sf/src/lir.zig:472-477` (`ModuleGlobalDecl`); `sf/src/main.zig:585-629` (global_decls registration); `sf/src/lower.zig:1317-1329` (`lowerGlobalRef`), `:900-915`, `:2325-2335`, `:5580-5595` (load/store_global emission)
- Create: `.superpowers/sdd/task-IA-emission-report.md` (report, read-only — no commit)

**Consumes:** F-A BLOCKED evidence (`task-FA-emission-report.md`). **Produces:** the exact upstream fix for root cause A + the answer to the two open questions, so F-A implements without re-reading.

**Mechanism already established (do NOT re-derive — verify only if a line contradicts):**
- `nameManglerMangle` (`c89_emit.zig:400-479`) cache key = `(module_id << 35) | (kind << 32) | name_id`; for kind G the base mangled name is `zG_<fnv1a(name)>_<name>` with `_N` suffix on collision. The collision maps (`collision_mod`/`collision_name`, `:472-473`) key only on the mangled STRING. The A1 edit (currently in the working tree, UNCOMMITTED) changed the key so kind-G drops `module_id`.
- Kind-G mangle call sites all pass the GLOBAL's `module_id`: extern decls `:2336`, defs `:2441`, `load_global` `:4388`, `store_global` `:4435`.
- `ModuleGlobalDecl` (`lir.zig:472-477`) = `{ name_id, module_id, type_id, has_runtime_init }`. **No per-type-storage flag exists.**
- Registration: `main.zig:585-629` appends a `ModuleGlobalDecl` for each storage `var_decl` (flag 0x04 gate at `:586`; `gv_is_storage` at `:591-599`; import_expr/field-access-of-import excluded at `:603-606`). `module_id = mods[mi].id` (the DECLARING module).
- `load_global`/`store_global` LIR carry the global's own `module_id` (from `s.module_id`/`gss.module_id` — the declaring module), so both the definition (`emitGlobalDecls`) and all references mangle with the SAME module_id → they AGREE. The collision in the A fixture arises because the SAME type name is declared as a storage global in MULTIPLE modules (tmod aliases `Color`, cmod1/cmod2 import it) → each gets its own `module_id` → 3 different `_N`-suffixed names for one logical type descriptor.
- `json_parser` `g_arena` in `file.zig` + `json.zig` is a genuine USER global (per-module storage) — it must stay per-module (this is why A1 fails).

**The two questions (answer them in the report):**
1. **What identity key should type-storage globals use so all modules agree on ONE name, without merging distinct user globals?** Candidate: key by the STORED TYPE's identity — i.e. use the type's `type_id` (or the type name's `name_id` with the type's OWNING module) instead of `(global name_id, global module_id)`. Since a type-storage global's `type_id` is the type it stores (and `ModuleGlobalDecl.type_id` is already populated at `main.zig:622`), derive the mangle identity from the TYPE, not the global. Verify: is `type_id` globally unique per type (so two modules that each define a DIFFERENT type named `Color` stay distinct)? Trace where `type_id` is assigned/registered in the type registry.
2. **Where is the type-storage vs user-global discriminator available at mangle time?** At `emitGlobalDecls`/`load_global`/`store_global`, the code has `g.type_id`/`lg.result`-typed temps but must know the global is a TYPE descriptor to apply type-identity keying. Determine: is the discriminator derivable from existing data (e.g. `g.type_id`'s type has `name_id == g.name_id` — the global is named after its own type), or does it need a new field on `ModuleGlobalDecl`/LIR `load_global`/`store_global` (main.zig + lower.zig registration)? Recommend the minimal correct option, respecting the "upstream, maintainable" bar (no patch, no A1/A2-style overload).

- [ ] **Step 1: Verify the A1 failure mechanism end-to-end** (the json `g_arena` merge) against the working-tree A1 edit — confirm the diagnosis, then note the A1 edit must be REVERTED or reworked.
- [ ] **Step 2: Answer question 1** — the exact type-identity keying (type_id vs type-owning-module), with the two-modules-same-type-name analysis.
- [ ] **Step 3: Answer question 2** — where the discriminator lives / whether a new field is needed, and the exact files/lines for the fix.
- [ ] **Step 4: Write the report** at `.superpowers/sdd/task-IA-emission-report.md` with the pinned fix design (function + lines + code shape). No commit (read-only). If the fix requires a `ModuleGlobalDecl`/LIR field, present the exact struct/registration change.

---
### Task I-FA2: pin the import-expr field-access resolution fix (read-only)

> **AMENDMENT 4 (2026-08-20):** F-A (commit `c98590b7`) applied the I-A pinned type-identity keying exactly, passed all 4 MD5s + corpus + matrix, but the fixture `emission_mangler_collision_xmod` stayed RED: the discriminator fires at def/extern/store (tmod `_Color_2`) but NOT at cmod1/cmod2 `load_global` (they reference `_Color`/`_Color_1`). Root (controller-verified, read-only): `semanticAnalyzerResolveFieldAccess` resolves ident-expr-base module access (`m.X`, `:331-389`) through the module symbol → returns the type's `type_id` (Color 29), but has NO `import_expr`-base branch, so `@import("m").X` falls through to `:431` → `semanticAnalyzerResolveExpr(import_expr)` = `TYPE_VOID` (`:1609`) → `s.type_id` stays 0 and the load temp is typed int. **The upstream fix (operator-confirmed option 1) is in `semantic_analyzer.zig` — make `@import("m").X` resolve through the module symbol exactly like `m.X`.** This task pins that change precisely (read-only); F-A is then amended to implement it on top of `c98590b7`.

**Files:**
- Read: `sf/src/semantic_analyzer.zig:323-429` (`semanticAnalyzerResolveFieldAccess`, incl. the ident_expr `type_alias` branch `:335-371` and module branch `:372-389`, the `import_expr` fallthrough at `:431-435`); `:1609-1610` (`import_expr` → `TYPE_VOID`); `sf/src/symbol_registrator.zig:224-308` (`registerDecl` — `field_access` init is NOT classified `type_alias`, unlike `ident_expr` at `:270-283`); `sf/src/lower.zig:2227-2266` (field_access lowering — ident_expr/type_alias base path); `sf/src/main.zig:603-606` (import_expr/field-access-of-import storage-global exclusion)
- Create: `.superpowers/sdd/task-IFA2-emission-report.md` (report, read-only — no commit)

**Consumes:** F-A RED evidence (`task-FA-emission-report.md` marker table). **Produces:** the exact `semantic_analyzer.zig` change (function + lines + code shape) so F-A implements without re-reading.

**Mechanism already established (do NOT re-derive — verify only if a line contradicts):**
- `s.type_id` is populated by `frontResolveModuleInits` (`front_resolution.zig:112-120`) from `semanticAnalyzerResolveModuleVarDecl`'s result. For ident-base `const Color = color.Color` → `semanticAnalyzerResolveFieldAccess` module branch returns `fs.type_id` = Color (tid 29) → `s.type_id = 29`. For import-base `const Color = @import("color.zig").Color` → no import_expr branch → falls through → `TYPE_VOID` → `s.type_id` stays 0, `resolvedTypeTableGet(s.decl_node)` = int → the I-A discriminator (`types_items[type_id].name_id == name_id`) fails at load sites.
- `registerDecl` (`symbol_registrator.zig:224-308`) classifies `ident_expr`-init aliases as `SymbolKind.type_alias` (`:270-283`), but `field_access` init (both `color.Color` and `@import("color.zig").Color`) is not in the switch → default `SymbolKind.global`, `sym_type_id = 0`.
- The module-field resolution that must be reused lives at `semantic_analyzer.zig:372-389`: `symbolRegistryQualifiedLookup(target_mod, field_name_id)` → if `fs` is a `type_alias` (or has a type_id) return `fs.type_id` and record it in the resolved table.

**The questions to answer (in the report):**
1. **Exact change shape**: add an `import_expr`-base case at the top of `semanticAnalyzerResolveFieldAccess` (`:323`) that resolves the import's target module id (via the same lookup the ident_expr/module branch uses — trace how `import_expr` gives a module symbol/module_id today), then performs the module-field lookup mirroring `:372-389`, setting `resolvedTypeTableSet(node_idx, type_id)` and returning the field symbol's `type_id`. Is the module_id obtained from `symbolRegistryQualifiedLookup` of the import path (same as `registerDecl`'s import_expr handling at `symbol_registrator.zig:238-252` — `path_to_id` + `typeRegistryGetOrCreateModule`), or directly from the import_expr symbol? Pin the exact source.
2. **Sema vs registrator**: is the cleanest single change the sema field-access fix (controller-recommended, mirrors the ident-expr module branch), or also needed in `registerDecl` (classify `field_access` init as `type_alias` when the resolved field is a type)? Determine whether the sema fix alone is sufficient for `s.type_id` + `resolvedTypeTableGet(decl_node)` to both become 29 for the import-base alias, or whether `registerDecl` must also change. If registerDecl must change, specify the exact guard (e.g. after `resolveTypeExprFull`, or matching the ident_expr nameCache pattern).
3. **Blast radius**: would the change alter any currently-correct resolution? Confirm the module-field branch already handles ident-base and the new import-base branch is a strict parallel (same `fs` kind/type_id outcomes), so no corpus/MD5 change. Note the existing `main.zig:603-606` exclusion (import_expr/field-access-of-import are NOT storage globals) — does the sema fix affect that? (It should not: storage classification is separate from type resolution.)
4. **Fixture expectation**: after the fix, `const Color = @import("color.zig").Color` in cmod1/cmod2 resolves to Color (tid 29) → `load_global` result temp typed Color → the committed `nameManglerMangleGlobal` discriminator fires → all modules emit `zG_E5B43CF8_Color` (one name) → fixture `gcc -c` rc=0. json `g_arena` (user global, type `*Arena` → name mismatch) stays per-module → json MD5 stays `9720478c937409a29fe23ae0199821cf`.

- [ ] **Step 1: Verify the fallthrough** — confirm `@import("m").X` reaches `:431` (base_type_id = `semanticAnalyzerResolveExpr(import_expr)` = TYPE_VOID → `:432-435` returns VOID), and that the ident-expr module branch `:372-389` is the behavior the import-expr base must mirror.
- [ ] **Step 2: Answer question 1** — pin the exact `import_expr`-base code shape (source of module_id, the field lookup, the resolved-table write, the return).
- [ ] **Step 3: Answer question 2** — sema-only vs sema+registerDecl, with evidence for whether `s.type_id`/`resolvedTypeTableGet` both reach 29.
- [ ] **Step 4: Answer questions 3-4** — blast radius + fixture expectation, and whether any corpus dir uses import-expr-base type-alias field access that would change.
- [ ] **Step 5: Write the report** at `.superpowers/sdd/task-IFA2-emission-report.md`. No commit (read-only).

---
### Task F-A: fix — mangler collision on type storage globals (root cause A)

**Files:**
- Modify: per the I-A report (c89_emit.zig + optionally lir.zig/main.zig/lower.zig for the discriminator field)
- Report: `.superpowers/sdd/task-FA-emission-report.md`

> **AMENDMENT 3 (2026-08-20):** A1 (drop `module_id` for kind G) was REJECTED — it merged json's `g_arena` (2 modules). F-A now implements the I-A-pinned **type-identity keying**: type-storage globals mangle by the STORED TYPE's identity (all modules agree on one name), user globals keep per-module keying. First REVERT the uncommitted A1 working-tree edit in `nameManglerMangle` before applying the I-A fix.

> **AMENDMENT 4 (2026-08-20):** F-A Step 1-2 DONE and committed (`c98590b7` — A1 reverted, `nameManglerMangleGlobal` + 4 kind-G sites; 4 MD5s byte-identical incl. json `9720478c…`, corpus/matrix zero regression). Step 3 fixture gate NOT met: `emission_mangler_collision_xmod` still `gcc rc=1` — the discriminator fires at def/extern/store (tmod `_Color_2`) but not at cmod1/cmod2 `load_global` (`_Color`/`_Color_1`), because import-base aliases type the load temp as int (sema `import_expr` fallthrough). **F-A is now BLOCKED pending I-FA2.** After I-FA2 pins the `semantic_analyzer.zig` fix, F-A is amended to implement it ON TOP of the committed `c98590b7` (no revert needed), re-run Step 3, and commit the follow-up as a second fix commit.

**Consumes:** I-A report (pinned fix, `task-IA-emission-report.md`). **Produces:** `emission_mangler_collision_xmod` GREEN + json gate intact.

- [ ] **Step 1: Revert the A1 working-tree edit + apply the I-A fix**

The A1 edit in `nameManglerMangle` (`c89_emit.zig:404-407`, the `if (kind != @intCast(u8, 1))` module_id drop) is UNCOMMITTED in the working tree — revert it. Then apply the I-A report's pinned type-identity keying exactly (function + lines + code shape from the report). Via `edit`/`fastedit` (re-read region, bottom-to-top).

- [ ] **Step 2: Rebuild + reinstall std**

```bash
bash sf/scripts/build_release.sh
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```

- [ ] **Step 3: Fixture GREEN + byte-identity gate**

Re-run `emission_mangler_collision_xmod`: dump + gcc -c → 0 errors. Then 4 MD5s byte-identical (gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3` repo-root CWD, json `9720478c937409a29fe23ae0199821cf`, mud `a1d0dd55aada9c3fd904ae33f54de32e`), corpus 287 unchanged, matrix 21/21. json MUST stay byte-identical (the g_arena merge gate). If an MD5 changed: check emitted C correct + runtime-identical → STOP + propose re-baseline; else STOP (defect).

- [ ] **Step 4: Commit**

Commit: `fix: mangle type-storage globals by stored type identity`

---


### Task F-B: fix — local dedup 128-slot cap (root cause B)

**Files:**
- Modify: `sf/src/c89_emit.zig:499` (field), `:531` (init), `:6061-6064` (grow)
- Report: `.superpowers/sdd/task-FB-emission-report.md`

**Consumes:** I report §B. **Produces:** `emission_local_dedup_cap_xmod` GREEN.

- [ ] **Step 1: Apply fix B**

Change `dedup_names: [128]u32` → `[*]u32` + add `dedup_cap: u32` (`:499`), init in `c89EmitterInit` (`:531`) with `sandAlloc` for 128 + `dedup_cap = 128`, and replace the cap guard at `:6061-6064` with grow-then-store (per I report §B shape). Via `edit`/`fastedit`.

- [ ] **Step 2: Rebuild + reinstall std** (same commands as F-A Step 3)

- [ ] **Step 3: Fixture GREEN + byte-identity gate**

Re-run `emission_local_dedup_cap_xmod`: dump + gcc -c → 0 errors. Then 4 MD5s byte-identical + corpus 287 unchanged + matrix 21/21. Runtime-priority override as in F-A.

- [ ] **Step 4: Commit**

Commit: `fix: grow local dedup table past 128 (duplicate redecls)`

---

### Task F-C: fix — sibling-variant payload conflation (root cause C, C1 lowering)

**Files:**
- Modify: `sf/src/lower.zig:308-314` (5 arrays), `:629` (64-cap → grow), `:656-677` (`maybeDisambiguateCapture` full scan)
- Report: `.superpowers/sdd/task-FC-emission-report.md`

**Consumes:** I report §C (C1, operator-approved lower.zig scope). **Produces:** `emission_sibling_payload_xmod` GREEN.

- [ ] **Step 1: Apply fix C1**

Grow the 5 `local_decl_*` arrays from `[64]` to growable (`sandAlloc`-backed, mirroring the memory-plan pattern; update init at `lower.zig:438-444`), remove the silent 64-cap `return` at `:629`, and ensure `maybeDisambiguateCapture` (`:656-677`) scans the full local list. Via `edit`/`fastedit`.

- [ ] **Step 2: Rebuild + reinstall std** (as F-A Step 3)

- [ ] **Step 3: Fixture GREEN + byte-identity gate**

Re-run `emission_sibling_payload_xmod`: dump + gcc -c → 0 errors, run → expected output. Then 4 MD5s byte-identical + corpus 287 unchanged + matrix 21/21. Runtime-priority override as in F-A.

- [ ] **Step 4: Commit**

Commit: `fix: grow local-decl arrays past 64 + full capture disambiguation (sibling payload)`

---

### Task F-D: fix — indirect .call void guard (root cause D)

**Files:**
- Modify: `sf/src/c89_emit.zig:5233-5258` (.call arm)
- Report: `.superpowers/sdd/task-FD-emission-report.md`

**Consumes:** I report §D. **Produces:** `emission_void_call_xmod` GREEN.

- [ ] **Step 1: Apply fix D**

In the `.call` arm, resolve the callee's fn type (per I report §D shape: hoisted_temps lookup, deref ptr, fn_items return_type) and suppress the `result = ` assignment when the return type is void. `call_direct` guard at `:5372` is the reference. Via `edit`/`fastedit`.

- [ ] **Step 2: Rebuild + reinstall std** (as F-A Step 3)

- [ ] **Step 3: Fixture GREEN + byte-identity gate**

Re-run `emission_void_call_xmod`: dump + gcc -c → 0 errors, run → expected output. Then 4 MD5s byte-identical + corpus 287 unchanged + matrix 21/21. Runtime-priority override as in F-A.

- [ ] **Step 4: Commit**

Commit: `fix: suppress void result assignment in indirect call (.call arm)`

---

### Task F-E: fix — void-temp class-1b (root cause E: E1 + E1c + tag-test)

> **AMENDMENT 2 (2026-08-20):** I-E investigation re-scoped F-E. E1 (if-capture) fixes ~0 of the 202 class-1b errors (corpus has no tagged-union if-captures); the dominant producer is **E1c** (variant-payload field access `inst.<variant>.<field>`, ~115 errs, root `semantic_analyzer.zig:607` override + `lower.zig:2450-2458`); ~68 of the 202 are actually A (~30 global/pal type loss) + C (~38 switch-arm conflation) and collapse when those land; and the R fixture won't print 7 until the **tag-test** bug is fixed (`lower.zig:4225-4237` tests the constant variant index, not `i`'s runtime tag). Runs AFTER F-A and F-C.

**Files:**
- Modify: `sf/src/lower.zig` (E1 `bindOptionalCapture` tagged-union branch; E1c variant-payload field access at `:2450-2458`; tag-test at `:4225-4237`), `sf/src/semantic_analyzer.zig:607` (drop the `result = base_type_id` override for tagged-union field access)
- Report: `.superpowers/sdd/task-FE-emission-report.md`

**Consumes:** I-E report (E1 pinned design + E1c analysis + tag-test), F-A + F-C results (reorder). **Produces:** class-1b residual re-measured (expect ~68 already gone from A/C), `emission_void_temp_xmod` GREEN printing 7, full self-compile build.

- [ ] **Step 1: Apply fix E1 (bindOptionalCapture tagged-union branch)**

In `bindOptionalCapture`, add the `tagged_union_type` branch per the I-E report's pinned first-non-void-variant derivation (`types_items[cond_ty].payload_idx` → `tu_items[...]` → `fe_items[fields_start+i].type_id`, first `!= TYPE_VOID`), emitting `load_field TU_FIELD_PAYLOAD` into a payload-typed temp — mirroring the switch-arm at `lower.zig:3790-3815`. Via `edit`/`fastedit`.

- [ ] **Step 2: Apply fix E1c (variant-payload field access — the dominant class-1b producer)**

Fix `inst.<variant>.<field>`: stop overriding the result to `base_type_id` for tagged-union field access at `semantic_analyzer.zig:607`, and emit a real payload load in `lower.zig:2450-2458` (payload struct member access `.payload.<variant>._0`, or `load_field TU_FIELD_PAYLOAD` + variant-tag check) so a follow-on `.field` (`inst.call_direct.result`, `inst.tail_call.is_extern`) resolves instead of producing a void temp. Via `edit`/`fastedit`.

- [ ] **Step 3: Apply tag-test fix (if (union.field) compares runtime tag)**

Fix `if (union.field)` so the condition compares `load_field TU_FIELD_TAG` on the *base* (`i`) against the nominated variant index, instead of testing the constant tag value of the nominated variant (`lower.zig:4225-4237` + `:2450-2458`). Required for the fixture to print 7. Via `edit`/`fastedit`.

- [ ] **Step 4: Rebuild + reinstall std** (as F-A Step 3)

- [ ] **Step 5: Fixture GREEN + byte-identity gate**

Re-run `emission_void_temp_xmod`: dump + gcc -c → 0 errors, run → prints 7. Then 4 MD5s byte-identical + corpus 287 unchanged + matrix 21/21. Runtime-priority override as in F-A.

- [ ] **Step 6: Re-measure class-1b residual**

Regenerate `/tmp/emit_errs.txt` and count remaining `zT_<n> undeclared`. Expected: the ~68 A/C errors are gone (landed in F-A/F-C), E1c removed its ~115, leaving a small residual to triage. If a substantial NEW shape appears, STOP and report.

- [ ] **Step 7: Full self-compile build + smoke (success gate)**

```bash
bash scripts/self_compile/build_zig1_5.sh
```
Expected: rc=0, `=== [zig1_5] Done: /tmp/zig1_5 ===`, both `zig1_5_asan` + `zig1_5_clean` produced. Smoke both on `examples/z98/hello/main.zig` (rc=0, `.c` emitted). If any gcc error remains, it is an incomplete fix (iterate) or a NEW class (STOP and report).

- [ ] **Step 8: Commit**

Commit: `fix: tagged-union payload access (E1 if-capture, E1c variant-payload field, tag-test)`

---


### Task GATE: reconcile docs + closeout

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Report: `.superpowers/sdd/task-GATE-emission-report.md`

**Consumes:** F result. **Produces:** reconciled tracking docs.

- [ ] **Step 1: Final gate sweep**

Re-verify 4 MD5s byte-identical, corpus 287 `OK=276 FAIL=7 ICE=0 CRASH=0 GREEN=4`, matrix 21/21, `test_analyzer_bin` "5 passed, 4 failed".

- [ ] **Step 2: Update EXPECTED_FAIL.md**

Version bump + a closeout section: the 5 emission classes fixed, the R fixtures (now GREEN), the self-compile-now-buildable milestone, and the next frontier (resume correctness plan T3-T6).

- [ ] **Step 3: Update QUICK_REF.md**

Add a post-emission-fix baseline paragraph; note that self-compile now produces a *buildable* `zig1_5` (gcc-compilable emitted C), correcting the prior "FULLY GREEN" wording that only checked rc + file count.

- [ ] **Step 4: Commit**

Commit: `docs: self-compile emission-fix GATE closeout + reconciliation`
