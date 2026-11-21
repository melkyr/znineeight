# F-CROSSMOD-STORE Implementation Plan — cross-module `pub var` scalar store (bug fix)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the zig1 ICE `error[3043] internal: unsupported field-store base` (rc=3, 0 `.c`) when an importing module assigns a scalar to a cross-module `pub var` member (e.g. `other.shared = 7;`), so the committed R5 RED fixture `repro/mi_matrix/crossmod_pubvar_xmod/main.zig` goes GREEN with byte-exact stdout `7 7`.

**Architecture:** single additive bug fix in `sf/src/lower.zig` only. `lowerAssignLValue` routes every `field_access` lvalue unconditionally to `lowerFieldStore` (lower.zig:1190-1191), which has NO module-base case — it lowers the module identifier as a runtime value (→ spurious `warning[3023]`) and then hits `iceFieldStoreUnsupported`. The LOAD path already has the module-base case (`lowerExpr` field_access, `SymbolKind.module` → target-module qualified lookup → member `SymbolKind.global` → `.load_global{name_id, module_id=target_mod}` at lower.zig:2577-2619). The fix mirrors that shape in `lowerFieldStore`: when `fa_node.child_0` is an `ident_expr` resolving to a `SymbolKind.module` symbol whose member is a `SymbolKind.global` (non-extern), emit `.store_global{name_id, module_id=target_mod, value}` and return. The extern+def C architecture is already proven by the working read path (owner `.c` holds the single definition; importing headers carry `extern int zG_…;`); the same symbol is referenced for reads and writes, so the write needs no new emitter/symbol work. Semantics: identical to the same-module ident store (`lowerAssignLValue` :1156-1162) and to the module runtime-init store (lower.zig:6141).

**Tech Stack:** Z98 dialect in `sf/src/*.zig` (self-hosted compiler source); verified against the rebuilt zig0-bootstrap reference; R5 fixture run-gate.

## Global Constraints

- This plan is **F-CROSSMOD-STORE** = item 4 of the operator-approved follow-on execution order (G1 rulings: defect CLEAR via I5, additive store-side routing only). ONLY this bug fix; **no other F work, no other compiler changes.**
- Z98 dialect discipline: `@intCast` on every narrowing/widening; no `anytype`/`@Type`; `switch` must have `else`; no method syntax; no pointer captures. Follow the surrounding file style exactly.
- Source edits via `fastedit` ONLY per `docs/sf/AGENTS.md` X.7 (re-read the region immediately before every edit; absolute line numbers; edit bottom-to-top; an INSERT = replace the anchor line keeping the original at the end of `new_code` since `end_line = start_line - 1` errors). No python/sed/bulk transforms. No `git checkout` to erase.
- **Files that MAY change: `sf/src/lower.zig` ONLY.** NO other `sf/src` file; never touch `sf/build/out_release/`. The R5 fixture is committed verbatim and is NOT amended.
- **Operator-authorized D1 dialect (carried from F-BITCAST AMENDMENT 1, applies to all subsequent fixes):** if an edit block's `var x: u32 = type_mod.TYPE_*;` cross-module comptime-const local-init decl is dropped by zig0 during self-compile (`'x' undeclared`), wrap the initializer as `@intCast(u32, type_mod.TYPE_*)` WITHOUT a fresh ruling. Any drop/undeclared situation NOT matching that exact class → STOP-present.
- Reference rebuild: `timeout 900 bash sf/scripts/build_release.sh` → output `/tmp/fx_subfolder/zig1`. **CRITICAL:** this rebuild wipes `/tmp/fx_subfolder/lib` — after any rebuild re-install the canonical std lib (cp `sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig}` into `/tmp/fx_subfolder/lib/`) or every std-importing program fails `error[3048]`.
- GREEN contract (byte-exact stdout, run-gate `RUNRC=0`): `crossmod_pubvar_xmod` → `7 7`.
- The 4-MD5 gate programs perform no cross-module scalar store ⇒ their dump md5 MUST stay byte-identical: gol `302df36b…`, lisp `3591bad9…`, json `76056b97…`, mud `53405b3b…`. Any move is a bug → STOP-present.
- **Battery/docs deferral (operator scheme, F-BITCAST AMENDMENT 2):** this plan contains ONLY the implementation task. The full battery (golden/matrix/corpus) + fixed-point re-baseline STOP-present + EXPECTED_FAIL/QUICK_REF docs GATE for items 3-6 run COMBINED once F-SWITCHRANGE (item 6) lands. Per-commit gates that STILL hold here: fixture RED→GREEN byte-exact, 4-MD5 byte-identical, self-compile fixed point closes (record new md5), exact commit scope.
- Authoritative per-fixture classifier = Step-4 recipe in `.superpowers/sdd/task-LANGWINS-report.md` (`fixture_run.sh` run-gate; fresh output dir `rm -rf`+`mkdir -p` REQUIRED, else dump ICEs rc=3 spill-open). Pre-existing dirty/untracked repo files are NEVER staged or committed.
- Commit messages follow repo style (lowercase `feat:`/`test:`/`fix:`/`docs:` prefix + concise body).
- Operator standing rules: only plan-authorized actions; STOP-and-present on any issue or any plan-vs-evidence divergence; store memories as we go (mnemoria agent `fcrossmodstore-session`); NO context compression during this build session.

---

## Background (verified anchors — read before editing; line numbers at HEAD `f1505f24`)

1. Store lvalue dispatch: `lowerAssignLValue` (lower.zig:1148-1199). `field_access` → `lowerFieldStore` unconditionally (:1190-1191). The `ident_expr` same-module global store precedent: `isStorageGlobal` + `symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, name_id)` → `.store_global{name_id, module_id=gss2.module_id, value}` (:1156-1162). `isStorageGlobal` (lower.zig:1624-1634) returns true for `SymbolKind.global` not flagged extern (`flags & 0x04 == 0`).
2. `lowerFieldStore` (lower.zig:1202-1297): reads `fa_node.child_0` into `child_0_node` (:1205); the module-ident base has NO matching branch → else at :1236-1238 `base_temp = lowerExpr(self, fa_node.child_0)` (fires `warning[3023]` module-as-value) → `resolved_base` null → `iceFieldStoreUnsupported` (:1294-1296, def :986, `error[3043]`). THE GAP.
3. The LOAD-side mirror (proof the extern architecture works): `lowerExpr` field_access module case (lower.zig:2577-2619): module symbol → `target_mod = s.module_id` → member `symbolRegistryQualifiedLookup(target_mod, field_name_id)` → `SymbolKind.global` → `gbl_tid` from `resolvedTypeTableGet(ts.decl_node)` → `.load_global{name_id=ts.name_id, module_id=target_mod, result}` (:2618). Emission side (c89_emit) already emits per-module storage-global extern headers (`extern int zG_…;`) + the single owner definition; reads and writes of the same symbol share it.
4. Symbol access: `Symbol{name_id,type_id,kind,flags:u16,decl_node,module_id}` (symbol_table.zig:4-10); `symbolRegistryQualifiedLookup(reg, mod_id, name_id)` (symbol_table.zig:141); `astStoreIdentifier(store, node_idx)` (ast.zig:620); extern flag = `0x04`; module symbol carries `.module_id` = the imported module's id; `sym_mod` is the module alias in scope in lower.zig.
5. R5 fixture: `repro/mi_matrix/crossmod_pubvar_xmod/` — `other.zig` declares `pub var shared: i32 = 0;` + `pub fn read() i32 { return shared; }`; `main.zig` (importer) does `other.shared = 7; printInt(other.shared); writeByte(' '); printInt(other.read());` — RED today = ICE `error[3043] internal: unsupported field-store base` rc=3 0 `.c` (read-only variant emits the extern header + owner def fine; zig0 oracle single-storage exit 7).
6. Scalar-only gap: cross-module ARRAY-ELEMENT stores already work (index_access base lowers through `lowerExpr` → load_global → the F-`assign_index` store-drop fix f014259b). This fix covers only the scalar `field_access` (module member) store.

---

### Task 1: Fix — module-base `store_global` routing in `lowerFieldStore`

**Files:**
- Modify: `sf/src/lower.zig` (insert at the head of `lowerFieldStore`, between `child_0_node` (:1205) and the `base_temp` decl (:1206))

**Interfaces:**
- Consumes: `lowerFieldStore` (existing signature `(self, fa_node_idx, value_temp, diag_node_idx)`), Symbol/SymbolKind (`sym_mod`), `astStoreIdentifier`, `.store_global` LirInst shape from the same-module precedent (:1159) and module-init (:6141).
- Produces: cross-module scalar `pub var` store lowered to `.store_global`; R5 fixture GREEN (`7 7`); 4-MD5 gates byte-identical; fixed-point closes on a NEW md5.

- [ ] **Step 1: Confirm the pre-edit RED + snapshot gates**

Against the current reference (repo-root CWD; `/tmp/fx_subfolder/zig1` md5 `0d97c207…`, std lib already installed):
```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/crossmod_pubvar_xmod/main.zig /tmp/fcms_red
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum; done
```
Expected: the fixture dump is ICE (rc=3, `error[3043]: internal: unsupported field-store base`, 0 `.c`) → RED confirmed; the four md5s equal gol `302df36b…`/lisp `3591bad9…`/json `76056b97…`/mud `53405b3b…`. If the fixture is already GREEN or any gate hash moved, STOP-present.

- [ ] **Step 2: Edit `sf/src/lower.zig`**

Insert a module-base intercept at the TOP of `lowerFieldStore`, immediately AFTER the existing line `var child_0_node = ast_mod.astStoreNodeAt(self.ctx.store, fa_node.child_0);` (:1205) and BEFORE the existing `var base_temp: u32 = undefined;` (:1206). INSERT = replace the anchor line `var base_temp: u32 = undefined;` keeping it at the END of `new_code` (X.7 INSERT form):
```zig
    if (child_0_node.kind == AstKind.ident_expr) {
        var cm_c0_name = ast_mod.astStoreIdentifier(self.ctx.store, fa_node.child_0);
        var cm_c0_sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, cm_c0_name);
        if (cm_c0_sym) |cmcs| {
            if (cmcs.kind == sym_mod.SymbolKind.module) {
                var cm_tgt_mod = cmcs.module_id;
                var cm_mem_sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, cm_tgt_mod, field_name_id);
                if (cm_mem_sym) |cmms| {
                    if (cmms.kind == sym_mod.SymbolKind.global) {
                        if ((@intCast(u16, cmms.flags) & @intCast(u16, 0x04)) == @intCast(u16, 0)) {
                            emitInst(self, LirInst{ .store_global = .{ .name_id = cmms.name_id, .module_id = cm_tgt_mod, .value = value_temp } });
                            return;
                        }
                    }
                }
            }
        }
    }
    var base_temp: u32 = undefined;
```
Notes: `fa_node`/`child_0_node`/`field_name_id`/`value_temp` are already computed above this point (:1203-1205). `AstKind`, `sym_mod`, `symbolRegistryQualifiedLookup`, `symbolRegistryGetTable` helpers, `emitInst`, `LirInst`, `store_global` are all in scope in lower.zig (see `isStorageGlobal` :1624 and `lowerAssignLValue` :1156-1162). The extern-flag skip (`0x04`) mirrors `isStorageGlobal` so extern storage is never routed through `store_global`; anything not a non-extern global member (type_alias/function/const slipped through sema) falls through to the EXISTING path (loud ICE — unchanged behavior, never silent). If `sym_mod` is not the correct alias name in this file, use the alias actually imported (check the import header block of lower.zig and match the names used at :1626).

- [ ] **Step 3: Rebuild the reference compiler**

```bash
timeout 900 bash sf/scripts/build_release.sh
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```
Expected: release-Done, NEW `/tmp/fx_subfolder/zig1` md5 (≠ `0d97c207…`), std lib re-installed. Record the md5.

- [ ] **Step 4: Verify the fixture flips RED→GREEN**

```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/crossmod_pubvar_xmod/main.zig /tmp/fcms_green
```
Expected: `RUNRC=0`; stdout byte-exact `7 7`; gcc clean. Confirm the emitted C shows the store as an assignment to the single shared symbol (main TU references the extern `zG_…_shared`; other TU holds its one definition) — and that the previous spurious `warning[3023]` + ICE are gone. If not GREEN with the exact contract, or the store does NOT reach the owner's storage (e.g. prints `7 0` or a link error), STOP-present.

- [ ] **Step 5: 4-MD5 gates byte-identical (repo-root CWD)**

```bash
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum; done
```
Expected: gol `302df36b…` / lisp `3591bad9…` / json `76056b97…` / mud `53405b3b…` — all four byte-identical. ANY move = a bug → STOP-present (do not re-baseline).

- [ ] **Step 6: Self-compile round-trip (fixed point check)**

```bash
bash scripts/self_compile/build_next_gen.sh /tmp/fx_subfolder/zig1 /tmp/fcms_self
```
Expected: dump rc=0, 42 `.c`, 0 `error[`, 0 PANIC, hop binaries md5-identical to each other AND to the new reference (fixed point closed). Record the NEW fixed-point md5. If the fixed point does NOT close, STOP-present. (The re-baseline of the fixed point is part of the COMBINED items-3-6 STOP-present after item 6 — not here.)

- [ ] **Step 7: Commit + report**

```bash
git add sf/src/lower.zig
git commit -m "fix: cross-module pub var scalar store — module-base store_global routing (F-CROSSMOD-STORE)"
```
Stage ONLY `sf/src/lower.zig`. Pre-existing dirty/untracked files stay unstaged. Append the full report to `.superpowers/sdd/task-F-CROSSMOD-STORE-report.md` (`## F-CROSSMOD-STORE-1`): RED proof, exact edit (hunk), fixture GREEN evidence (stdout bytes + emitted-C shape incl. the extern/single-def confirmation), 4-MD5 table, new reference md5, new fixed-point md5, commit sha, git-status-at-end. Ledger line in `.superpowers/sdd/progress.md`. Store a success memory via `mnemoria --path .opencode/memory add --agent fcrossmodstore-session ...`.

Report back: `DONE` + commit sha + one-line test summary + any concern.

---

## Plan Self-Review (performed at authoring time)

1. **Spec coverage:** G1 ruling (c) — cross-module pub-var ICE fixed as F-CROSSMOD-STORE with the I5 root-cause shape (module-base → `store_global` routing in `lowerFieldStore`, mirroring the proven load path :2577-2619 and the same-module ident-store precedent :1156-1162). Scalar-only, additive, no LIR/symbol/emitter change, fixture unchanged with GREEN contract `7 7`. R5 oracle exit-7 semantics preserved (single storage, importer write visible to owner read).
2. **Placeholder scan:** no TBD/TODO; the insertion block is complete code with the exact anchor; commands are exact.
3. **Type/name consistency:** identifiers (`cm_c0_name`/`cm_c0_sym`/`cmcs`/`cm_tgt_mod`/`cm_mem_sym`/`cmms`) follow the file's abbreviated local style and cannot collide with the surrounding `base_temp`/`resolved_base`; `store_global` field names match the LirInst shape used at :1159/:6141; extern flag constant `0x04` matches `isStorageGlobal` :1629.

## Execution Handoff

Plan complete. **Subagent-Driven (recommended per operator):** fresh implementer subagent per task + task reviewer (spec compliance + quality). No Task 2/Task 3 in this plan — battery + fixed-point re-baseline + docs GATE run COMBINED after F-SWITCHRANGE (item 6) per the operator deferral scheme (F-BITCAST AMENDMENT 2).
