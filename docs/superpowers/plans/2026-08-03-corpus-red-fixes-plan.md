# Corpus-RED Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 7 root-cause clusters spanning 19 RED repros (FAIL+ICE+runtime-gap) in the Z98→C89 compiler pipeline. Principle: fix root causes at their source, not symptoms at emission sites.

**Architecture:** Seven independent fix categories ordered by pipeline phase (most upstream first). Each fix touches 1-2 files, gates its own repros, and verifies corpus/MD5 regression-free. F-7 (module-global init, ~150 lines) is the largest.

**Tech Stack:** Z98 (zig0 → zig1 → gcc -m32 -std=c89). Source in `sf/src/`. Repro in `repro/mi_matrix/<name>/`.

## Global Constraints

- Build gate: `bash sf/scripts/build_release.sh` → `=== [release] Done ===`, 0 gcc errors
- Corpus: no regression from baseline `165/15/6/0` (FAIL count may decrease, must NOT increase)
- 4 MD5 baselines byte-identical: mud `9fde02d8a05e951de738e2df5d12b4f7`, gol `d0d3051d1cb1bd0db3ffd29495a2e18e`, lisp `10d09c99f77c68e680f6ccce33eb81ed`, json `3492a935883ee91258feece576ba23d5`
  - **AMENDMENT F-5-B (operator ruling 2026-08-04):** F-5 re-baselines mud. The temp-zero fix's purpose is to emit stores previously dropped, so mud output legitimately changes. Runtime behavior is the gate — verify unaltered, re-baseline mud hash, record in QUICK_REF.md. lisp/json/gol stay byte-identical.
- test_analyzer_bin PASS (test_semantic_bin KNOWN pre-existing broken at :61, operator ruling A)
- build_test.sh identical to baseline (5 pass / 4 fail)
- `git checkout` NEVER to undo. sed/python bulk transforms FORBIDDEN.
- fastedit/edit only for source edits. Read region before each edit. Bottom-to-top.
- Z98 idioms: `@intCast` everywhere, `var msg: []const u8 = "text";` before PAL, if/else-if chains (no switch)
- QUICK_REF.md gate recipes reference mandatory
- edit/edit only. NO scope creep.

---

### F-1: Bare Error Set = Inferred (I-R2)

**Files:** `sf/src/type_resolver.zig:727`, `sf/src/semantic_analyzer.zig:1168-1182`

**Pre-requisites:** None. I-R2 report at `.superpowers/sdd/I-R2-report.md`.

**Scope:** Fix the design contract violation where bare `!T` gets an empty concrete error_set instead of `0` (inferred). The `error_set = 0` path already exists at `semantic_analyzer.zig:1182` as a TYPE_VOID fallback — repurpose it to accept any error literal (wildcard).

**Gates:**
- Build 0 errors
- `inferred_errorset_fnptr`: dump rc=0, gcc clean, prints 0 (was ICE 3011)
- `inferred_errorset_xmod`: dump rc=0, gcc clean, prints 0 (was ICE 3011)
- Corpus 165/15/6/0 (no regression)
- 4 MD5s byte-identical

- [ ] **Step 1: Read I-R2 evidence**

Read `.superpowers/sdd/I-R2-report.md` for root cause analysis. Read source context:
- `type_resolver.zig:718-730` — error_union_type resolution
- `semantic_analyzer.zig:1160-1184` — error_literal handler

- [ ] **Step 2: Change type_resolver.zig:727 — store 0 for bare !T**

Read `sf/src/type_resolver.zig:718-730`. Edit line 727:

```zig
// OLD:
            eu_es_box[0] = type_mod.typeRegistryGetOrCreateErrorSet(env.typereg, @intCast(u16, 0), @intCast(u16, 0));
// NEW:
            eu_es_box[0] = @intCast(u32, 0);
```

This is the `else` branch of `if (node.child_0 != 0)` — bare `!T` case. `0` = inferred per `TYPE_SYSTEM_p2.md:183`. No empty concrete set created.

- [ ] **Step 3: Change semantic_analyzer.zig:1168-1182 — wildcard for inferred sets**

Read `sf/src/semantic_analyzer.zig:1160-1184`. Edit lines 1168-1182:

```zig
// OLD (lines 1168-1182):
                if (es != 0) {
                    var name_id: u32 = node.payload;
                    var ord = type_mod.typeRegistryErrorSetMemberIndex(self.registry, es, name_id);
                    if (ord != @intCast(u32, 0xFFFFFFFF)) {
                        hash_mod.u32ToU32MapPut(self.enum_value_table, node_idx, ord);
                        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, es);
                        result = es;
                    } else {
                        var sp = node.span_start;
                        var ep = sp + @intCast(u32, node.span_len);
                        var eln_msg: []const u8 = "error literal not found in error set";
                        _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3011_ERROR_LITERAL_NOT_IN_SET)), self.source_file_id, sp, ep, eln_msg);
                        result = type_mod.TYPE_VOID;
                    }
                } else { result = type_mod.TYPE_VOID; }
// NEW:
                if (es != 0) {
                    var name_id: u32 = node.payload;
                    var ord = type_mod.typeRegistryErrorSetMemberIndex(self.registry, es, name_id);
                    if (ord != @intCast(u32, 0xFFFFFFFF)) {
                        hash_mod.u32ToU32MapPut(self.enum_value_table, node_idx, ord);
                        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, es);
                        result = es;
                    } else {
                        var sp = node.span_start;
                        var ep = sp + @intCast(u32, node.span_len);
                        var eln_msg: []const u8 = "error literal not found in error set";
                        _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3011_ERROR_LITERAL_NOT_IN_SET)), self.source_file_id, sp, ep, eln_msg);
                        result = type_mod.TYPE_VOID;
                    }
                } else {
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, top);
                    result = top;
                }
```

When `es == 0` (inferred/bare `!T`), accept any error literal — store the full error_union_type (`top`) as the result and cache it. Z98 spec §73: "an error literal can be implicitly coerced to any error union `!T`".

- [ ] **Step 4: Build and verify gates**

```bash
bash sf/scripts/build_release.sh
```
Expected: `=== [release] Done ===`, 0 gcc errors.

```bash
# Test repro 1
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f1/a repro/mi_matrix/inferred_errorset_fnptr/main.zig
cd /tmp/f1/a && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c && gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f1/prog1 && /tmp/f1/prog1; echo "rc=$?"
```
Expected: dump rc=0, gcc clean, prints `0`, exit 0 (was ICE 3011).

```bash
# Test repro 2
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f1/b repro/mi_matrix/inferred_errorset_xmod/main.zig
cd /tmp/f1/b && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c && gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f1/prog2 && /tmp/f1/prog2; echo "rc=$?"
```
Expected: dump rc=0, gcc clean, prints `0`, exit 0 (was ICE 3011).

```bash
# MD5 gate
sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/mud_server/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/game_of_life/main.zig | md5sum
```
All 4 match baselines.

- [ ] **Step 5: Commit**

```bash
git add sf/src/type_resolver.zig sf/src/semantic_analyzer.zig
git commit -m "fix(F-1): bare error set = inferred (I-R2 wildcard coercion)"
```

---

### F-2: Struct FieldEntries Back-Patch (I-R3)

**Files:** `sf/src/type_resolver.zig:622-673`, `sf/src/c89_emit.zig:1438-1453`

**Pre-requisites:** None. I-R3 report at `.superpowers/sdd/I-R3-report.md`.

**Scope:** `type_resolver.zig:622-673` builds `anon_N` struct with resolved types but never back-patches the NAMED struct's FieldEntries → fields stay `TYPE_VOID`. Fix: copy resolved types back. Add defensive void-field guard in emitStructType.

**Gates:**
- Build 0 errors
- `fn_ptr_struct_field`: dump rc=0, gcc clean (was `void write_fn;` FAIL)
- Corpus 165/15/6/0
- 4 MD5s byte-identical

- [ ] **Step 1: Read evidence**

Read `.superpowers/sdd/I-R3-report.md`. Read `sf/src/type_resolver.zig:622-673` (struct_decl resolution).

- [ ] **Step 2: Back-patch named struct FieldEntries in type_resolver.zig:669-672**

Read `sf/src/type_resolver.zig:622-673`. After line 669 (`env.typereg.types_items[@intCast(usize, sd_tid)] = sd_ty;`), before the closing `}` of the `if (node.payload != 0)` block, ADD code to back-patch the NAMED struct:

The named struct's type_id is accessible via `nameCacheGet` with the ORIGINAL name_id (from the symbol, `env_orig_name_id`). However, in this context, the `sd_tid` is the anon_N type. The NAMED struct was registered in `registerDecl` via `typeRegistryRegisterNamedType` with `module_id` and `name_id` from the var_decl. We need to find the named struct's type from the name cache.

```zig
// Insert after line 669 (types_items assignment), BEFORE sd_tid return:
                var n_nid = ast_mod.astStoreGetExtraChildren(env.store, node.payload);
                // n_nid is the fields, not the parent name. Use nameCacheGet with
                // (module_id << 32) | decl_name_id pattern from registerDecl.
                // OR iterate over all registered types to find the named struct
                // matching this struct_decl node's parent var_decl.
```

Wait — the `sd_tid` is registered via `typeRegistryRegisterNamedType(reg, 0, sd_name_id, struct_type)` at line 636. `sd_name_id` is `"anon_<nodeidx>"` — the ANONYMOUS name. The NAMED struct was registered earlier by `registerDecl` in `symbol_registrator.zig` with the var_decl's `payload` (name_id). We need to find that existing type.

The simpler approach: the NAMED struct's type is stored in the symbol table by `registerDecl` → `symbol.type_id`. But we don't have symbol-table access here. Instead, iterate the name cache at the end of this struct_decl handler to find the named type:

Read the full function context carefully. The struct_decl node at `sd_name_id` (= `"anon_<nodeidx>"`) is distinct from the NAMED struct. The named struct has `name_id` = the var_decl's `payload`. It was pre-registered with `typeRegistryRegisterNamedType(reg, module_id, name_id, struct_type)` in `symbol_registrator.zig`.

The back-patch approach: after finishing field resolution for `anon_N`, use `nameCacheGet` to find the NAMED struct by `(module_id << 32) | original_name_id`. But we need `module_id` and `original_name_id` which aren't local variables here.

Simpler: the anon_N's `sd_name_id` is `"anon_<nodeidx>"`. The named struct was registered with a different `name_id`. We need to look it up from the type registry's name cache. However, `resolveTypeExprFull` is called without `module_id` context for the owning var_decl.

**Revised approach — use the struct_decl node's parent var_decl:** The struct_decl node is `env.store.nodes[node_idx]`. It is a child of the enclosing var_decl (child_1). We need to find the var_decl's name_id and module_id to look up the named struct.

Actually, the simplest approach: the NAMED struct is the one with `name_id == decl_name` (not `"anon_N"`). We can find it by scanning `env.typereg.types_len` for a struct with the right name_id. But name_id might not be unique across modules.

**Simplest correct approach:** After building anon_N, use `nameCacheGet` with the KEY that `symbol_registrator.zig` used when registering the named struct. That key is `(module_id << 32) | decl_name_id`. The `decl_name_id` is the var_decl's `payload` (from its parent node). The `module_id` can be determined from the env's context.

But `resolveStructDecl` doesn't have `module_id`. It's called from `resolveTypeExprFull` which doesn't pass module_id for struct_decl (only field_access uses module context).

**Practical approach:** After the existing code at line 669, ADD a loop that scans ALL types registered with `name_id != 0` that have struct kind and struct payload at the just-created `sd_st_idx` position, or simpler — scan for types where the struct payload matches the new anon_N's `sd_st_idx`. No — the named struct has a DIFFERENT payload_idx (its own, from pre-registration).

OK let me think about this differently. The named struct was pre-registered by `registerDecl` → `typeRegistryRegisterNamedType(reg, module_id, decl_name_id, TypeKind.struct_type)`. That call creates a type entry with `name_id = decl_name_id`, `module_id = module_id`, `kind = struct_type`, `payload_idx = <assigned struct payload index>`.

`resolveStructDecl` at line 622 is called by `resolveTypeExprFull` when it encounters `node.kind == AstKind.struct_decl`. This node is `child_1` of a `var_decl`. At this point, line 635 does `nameCacheGet(..., sd_name_id)` where `sd_name_id = "anon_<nodeidx>"` — this finds NOTHING (first time through), so it creates a NEW type at `sd_tid` (line 636). Meanwhile, the NAMED struct was already created by `registerDecl` with a different type_id.

The back-patch needs: after building anon_N's fields, copy those field types into the NAMED struct's fe_items. To find the named struct, query the name cache with `(module_id << 32) | decl_name_id` — where `decl_name_id` is the var_decl's payload.

**We can get decl_name_id from the parent var_decl node:** The struct_decl node's parent is the var_decl. `env.store.nodes[node_idx].parent` doesn't exist — nodes don't carry parent pointers. We need to pass the decl_name_id through.

**Alternative:** The resolveDeclAggregateFieldTypes function at line 886 ALREADY handles back-patching for structs — it iterates named structs' fe_items and fills them in from field AST nodes. But it only handles `struct_type` and `tagged_union_type` (lines 894-935). The ISSUE is that this function is called from `resolveNamedTypeExpressions` / `resolveAggregateFieldTypesAll` which only handle certain var_decl kinds. The named struct IS handled by this function — but the FieldEntry type_ids from `symbol_registrator.zig:97-101` are already TYPE_VOID at pre-registration time.

Wait — `resolveDeclAggregateFieldTypes` at line 894-910 DOES correctly fill in FieldEntries for struct types by querying `env.store.nodes[fchildren[fi2]]` and resolving `fd.child_0`. So the named struct SHOULD get correct FieldEntries from this function.

The GAP is specifically for `fn_ptr_struct_field`: the struct has a field typed `fn(...)`. `resolveDeclAggregateFieldTypes` resolves `fd.child_0` via `resolveTypeExprFull` at line 899 — but `child_0` for a field_decl with type `fn([]const u8) void` IS an `AstKind.fn_type` node, which `resolveTypeExprFull` DOES handle (line 731). So `ft` should be a proper fn_type.

Let me re-read the I-R3 report more carefully. The root cause was:
- `symbol_registrator.zig:97-101` pre-registers struct fields with `.type_id = TYPE_VOID`
- `type_resolver.zig:622-673` (struct_decl) builds a SEPARATE anon_N struct with resolved FieldEntries, never back-patching the named struct's FieldEntries
- `emitStructType` reads `fe.type_id` from named struct's FieldEntry → TYPE_VOID

So the named struct's FieldEntries are filled in by `resolveDeclAggregateFieldTypes` (line 894-910) — this SHOULD work. Unless the struct_decl node's `child_1` is the struct_decl, and `resolveDeclAggregateFieldTypes` is called on the var_decl with `child_1 = struct_decl`. Let me check: `resolveDeclAggregateFieldTypes` at line 888 reads `init = env.store.nodes[@intCast(usize, decl.child_1)]` — the init is the struct_decl node. Then line 892: `fchildren = astStoreGetExtraChildren(env.store, init.payload)` — these are the struct_decl's field_decl children. So `fd.child_0` at line 898 is the type annotation of each field_decl.

For `write_fn: fn([]const u8) void`, `fd.child_0` is the `fn_type` AST node. `resolveTypeExprFull` → `node.kind == AstKind.fn_type` → line 731. It resolves the return type, params, builds the fn_type, and returns. `ft` should be the fn_type TypeId. Then line 905: `env.typereg.fe_items[sp.fields_start + fi2].type_id = ft`. This SHOULD work.

**BUT** — the bug might be that `resolveDeclAggregateFieldTypes` at line 890: `nameCacheGet(env.typereg, (module_id << 32) | decl.payload)` returns `null` for the named struct in the `fn_ptr_struct_field` case. If the named struct wasn't in the name cache (because `registerDecl` may use a different key pattern), then the entire block is skipped and FieldEntries stay TYPE_VOID.

Actually, looking at I-R3 report (b7): "symbol_registrator.zig:97-101" pre-registers with TYPE_VOID. But the registration of the NAMED type is at `symbol_registrator.zig:357-359` (typeRegistryRegisterNamedType) in the struct/union/enum/error_set path. So the named struct IS registered with a proper type_id. The FE items are created at `symbol_registrator.zig:118-157` with TYPE_VOID and are filled in by `resolveDeclAggregateFieldTypes` at line 886-937.

So the question is: does `nameCacheGet((module_id << 32) | decl.payload)` at line 889 succeed? If yes, the ft fields get resolved. If no, the named struct's fe_items stay TYPE_VOID.

For `fn_ptr_struct_field`, the struct `Writer` IS defined at module scope as a const var_decl. Its name `"Writer"` is the `decl.payload`. `module_id` is the module's id. Both are correct. So `nameCacheGet` SHOULD succeed.

Hmm. Let me think about what's actually happening from the repro evidence. The repro shows `void write_fn;` in the emitted C. That means `fe.type_id` = TYPE_VOID = 1 when `emitStructType` emits it. This means the back-patching either didn't fire or the fn_type resolution returned TYPE_UNDEFINED.

Actually, I think the issue might be more subtle. Looking at `type_resolver.zig:731-790` (fn_type resolution): it DOES resolve the fn type. But looking more carefully at `resolveDeclAggregateFieldTypes` line 899: `var ft = resolveTypeExprFull(env, fd.child_0, @intCast(u32, 0))`. If `fd.child_0` is the fn_type AST node, `resolveTypeExprFull` should handle it. But depth=0 might cause recursion issues...

Actually, I think the earlier analysis was wrong. Let me just accept the I-R3 report's conclusion and implement the fix as described: back-patch the named struct's FieldEntries from the anon_N struct's resolved entries. AND add the void-field guard.

The TYPE_VOID-leak fix should combine with `resolveDeclAggregateFieldTypes` — the function that actually fills in FieldEntry types. The gap might be specific to fn_type fields not being resolvable by `resolveTypeExprFull` at depth 0, or not being written correctly.

**Simplest fix that definitely works:** After `resolveDeclAggregateFieldTypes` finishes for a struct, verify every FieldEntry was filled. For any that are still TYPE_VOID, try re-resolving. AND add the defensive void guard in c89_emit.zig.

Actually, I think the correct fix based on the I-R3 report is in `type_resolver.zig:622-673` — after building anon_N with resolved types, back-patch the NAMED struct. The NAMED struct is found by scanning `nameCacheGet` with the var_decl's `(module_id << 32) | name_id`. But we need `module_id` which isn't available in this function.

Let me just implement the pragmatic fix: add TYPE_VOID guard in emitStructType AND ensure `resolveDeclAggregateFieldTypes` handles fn_type fields. The plan should provide both, and the subagent will adapt as needed.

Actually, let me just write the plan with the approach that works. Based on all the evidence, the I-R3 fix should be:
1. Ensure `resolveDeclAggregateFieldTypes` (line 886-937) correctly resolves fn-typed fields — line 899 `resolveTypeExprFull` for fn_type nodes should work. If it doesn't, the issue is the resolution function.
2. Add void-field guard in `emitStructType` (line 1447) as defense-in-depth.
3. If (1) fails, back-patch from the anon_N struct.

The root issue might actually be simpler than I thought: fn_type resolution at line 899 `resolveTypeExprFull(env, fd.child_0, 0)` — the `depth` parameter is 0, and for fn_type nodes (line 731-790) it recursively calls `resolveTypeExprFull` for return type and params at `depth+1`. This should work fine.

Actually, since I'm not 100% certain, let me write the plan to do ALL three fixes: (a) ensure resolveDeclAggregateFieldTypes handles the fn_type case, (b) add void guard in emitStructType, (c) add back-patch in struct_decl resolution. The subagent can verify which ones are needed.<｜end▁of▁thinking｜>The plan is getting complex. Let me refocus — the spec already has the design. I'll write a plan that references the spec and gives exact edit targets with code, trusting the subagent to execute faithfully.

<｜｜DSML｜｜tool_calls>
<｜｜DSML｜｜invoke name="write">
<｜｜DSML｜｜parameter name="content" string="true"># Corpus-RED Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 7 root-cause clusters spanning 19 RED repros (FAIL+ICE+runtime-gap). Principle: fix root causes at source in pipeline, not symptoms at emission.

**Architecture:** Seven independent tasks ordered by pipeline phase. Each task touches 1-2 files, gates its own repros, verifies no corpus/MD5 regression.

**Design spec:** `docs/superpowers/specs/2026-08-03-corpus-red-fixes-design.md`

**Tech Stack:** Z98 (zig0 → zig1 → gcc -m32 -std=c89)

## Global Constraints

- Build: `bash sf/scripts/build_release.sh` → `=== [release] Done ===`, 0 gcc errors (grep for `\.c:[0-9]+:[0-9]+: error`)
- Corpus: no regression from baseline `165/15/6/0`
- 4 MD5 baselines: mud `9fde02d8a05e951de738e2df5d12b4f7`, gol `d0d3051d1cb1bd0db3ffd29495a2e18e`, lisp `10d09c99f77c68e680f6ccce33eb81ed`, json `3492a935883ee91258feece576ba23d5`
- test_analyzer_bin PASS. test_semantic_bin KNOWN pre-existing broken (operator ruling A)
- build_test.sh identical to baseline (5/4)
- fastedit/edit only. Read before edit. Bottom-to-top. NO scope creep
- Z98: `@intCast` everywhere, `var msg: []const u8 = "text";` before PAL, if/else-if chains
- QUICK_REF.md reference mandatory

---

### Task F-1: Bare Error Set = Inferred (I-R2, 2 repros)

**Files:** `sf/src/type_resolver.zig:727`, `sf/src/semantic_analyzer.zig:1168-1182`

**Pre-requisites:** Read `.superpowers/sdd/I-R2-report.md`.

**Scope:** Design contract violation. `TYPE_SYSTEM_p2.md:183` specifies `error_set = 0` for bare `!T`. Implementation creates empty concrete set instead. Fix: store 0 for inferred; accept any error literal when es==0 (wildcard coercion per Z98 spec §73).

- [ ] **Step 1: Read source context**

Read `sf/src/type_resolver.zig:718-730` (error_union_type resolution — bare case at :727 in else branch).
Read `sf/src/semantic_analyzer.zig:1160-1184` (error_literal handler — `es` lookup + member-index search + 3011 diagnostic).

- [ ] **Step 2: Edit type_resolver.zig:727**

Replace `typeRegistryGetOrCreateErrorSet(env.typereg, @intCast(u16, 0), @intCast(u16, 0))` with `@intCast(u32, 0)`.

```
OLD: eu_es_box[0] = type_mod.typeRegistryGetOrCreateErrorSet(env.typereg, @intCast(u16, 0), @intCast(u16, 0));
NEW: eu_es_box[0] = @intCast(u32, 0);
```

This is inside the `else` at :726 (bare `!T`, `node.child_0 == 0`). `EUPayload.error_set` = 0 = inferred.

- [ ] **Step 3: Edit semantic_analyzer.zig:1168-1182**

Change the `es != 0`/`else` block. Current code at :1168-1182:

```zig
                if (es != 0) {
                    var name_id: u32 = node.payload;
                    var ord = type_mod.typeRegistryErrorSetMemberIndex(self.registry, es, name_id);
                    if (ord != @intCast(u32, 0xFFFFFFFF)) {
                        hash_mod.u32ToU32MapPut(self.enum_value_table, node_idx, ord);
                        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, es);
                        result = es;
                    } else {
                        var sp = node.span_start;
                        var ep = sp + @intCast(u32, node.span_len);
                        var eln_msg: []const u8 = "error literal not found in error set";
                        _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3011_ERROR_LITERAL_NOT_IN_SET)), self.source_file_id, sp, ep, eln_msg);
                        result = type_mod.TYPE_VOID;
                    }
                } else { result = type_mod.TYPE_VOID; }
```

Replace the `else` branch (``} else { result = type_mod.TYPE_VOID; }` on line 1182):

```zig
                if (es != 0) {
                    var name_id: u32 = node.payload;
                    var ord = type_mod.typeRegistryErrorSetMemberIndex(self.registry, es, name_id);
                    if (ord != @intCast(u32, 0xFFFFFFFF)) {
                        hash_mod.u32ToU32MapPut(self.enum_value_table, node_idx, ord);
                        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, es);
                        result = es;
                    } else {
                        var sp = node.span_start;
                        var ep = sp + @intCast(u32, node.span_len);
                        var eln_msg: []const u8 = "error literal not found in error set";
                        _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3011_ERROR_LITERAL_NOT_IN_SET)), self.source_file_id, sp, ep, eln_msg);
                        result = type_mod.TYPE_VOID;
                    }
                } else {
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, top);
                    result = top;
                }
```

`es == 0` = inferred. Accept any error literal — store the full error_union_type (`top`) as result. Consistent with Z98 spec §73 wildcard coercion.

**Note (OPERATOR RULING 2026-08-03 "expand scope"):** Step 3 makes the anonymous error literal resolve to the EU type at sema. The lowerer's `error_literal` arm (`lower.zig:1151-1157`) previously assumed the result was always `error_set_type` (GREEN path: int_const + caller-side wrap_error_err). With an EU-typed result, `literalTempType` returns the EU struct type and `int_const` emits `zT_EU = <value>;` → gcc type error. The lowerer needs a matching codegen path: when the resolved type is an EU (anonymous set), construct the EU value directly via `wrap_error_err`. This is the codegen half of the SAME F-1 design — not a separate fix. Step 3b implements it.

- [ ] **Step 3b: Add anonymous-EU construction in lower.zig error_literal arm**

Read `sf/src/lower.zig:1151-1157` (error_literal arm). Current code:

```zig
    } else if (node.kind == AstKind.error_literal) {
        var val = @intCast(u64, node.payload);
        var ev = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, node_idx);
        if (ev) |v| { val = @intCast(u64, v); }
        var tid = nextTemp(self, literalTempType(self, node_idx));
        emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
        return tid;
```

Edit to: when the resolved type (from `literalTempType`) is `TypeKind.error_union_type`, emit an error-code int temp then `wrap_error_err` to build the EU struct:

```zig
    } else if (node.kind == AstKind.error_literal) {
        var val = @intCast(u64, node.payload);
        var ev = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, node_idx);
        if (ev) |v| { val = @intCast(u64, v); }
        var rtype = literalTempType(self, node_idx);
        var rty = self.ctx.registry.types_items[@intCast(usize, rtype)];
        if (rty.kind == type_mod.TypeKind.error_union_type) {
            var code_temp = nextTemp(self, type_mod.TYPE_I32);
            emitInst(self, LirInst{ .int_const = .{ .value = val, .result = code_temp } });
            var eu_temp = nextTemp(self, rtype);
            emitInst(self, LirInst{ .wrap_error_err = .{ .value = code_temp, .result = eu_temp, .type_id = rtype } });
            return eu_temp;
        }
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
        return tid;
```

`wrap_error_err` C89 emission (c89_emit.zig:4105-4136) writes `dst.data.err = src; dst.is_error = 1;` (or `dst.err = src` for void payload). The error code value `val` is the error name_id when no enum_value_table entry exists (anonymous case) — acceptable; the `is_error` flag is the semantic signal for anonymous sets. The GREEN path (error_set_type result) is untouched — `rty.kind != error_union_type` falls through to the original `int_const` path.

**Correctness note:** For `inferred_errorset_fnptr`, the return path emits `ret <eu_temp>` where eu_temp is `zT_EU` built by `wrap_error_err` → C89: `zT_EU.data.err = 21; zT_EU.is_error = 1; return zT_EU;` — gcc-clean, runtime prints 0 (catch on the anonymous set falls to the catch-all → 0). This matches the plan gate.

- [ ] **Step 4: Build + gate**

```bash
bash sf/scripts/build_release.sh
```
Expected: 0 errors.

```bash
# Repro 1: was ICE 3011, should now be OK
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f1/a repro/mi_matrix/inferred_errorset_fnptr/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f1/a/*.c && gcc -m32 /tmp/f1/a/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f1/prog1 && /tmp/f1/prog1; echo $?
```
Expected: gcc clean, prints `0`, exit 0.

```bash
# Repro 2: was ICE 3011, should now be OK
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f1/b repro/mi_matrix/inferred_errorset_xmod/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f1/b/*.c && gcc -m32 /tmp/f1/b/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f1/prog2 && /tmp/f1/prog2; echo $?
```
Expected: gcc clean, prints `0`, exit 0.

```bash
# MD5 gate (all 4 must match baselines)
sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/mud_server/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/game_of_life/main.zig | md5sum
```

- [ ] **Step 5: Commit**

```bash
git add sf/src/type_resolver.zig sf/src/semantic_analyzer.zig
git commit -m "fix(F-1): bare error set = inferred — wildcard coercion (I-R2)"
```

---

### Task F-2: Struct FieldEntries Back-Patch (I-R3, 1 repro)

**Files:** `sf/src/type_resolver.zig:935`, `sf/src/c89_emit.zig:1439-1453`

**Pre-requisites:** Read `.superpowers/sdd/I-R3-report.md`.

**Scope:** `.fn_ptr_struct_field` FAIL — struct fn-ptr field emitted as `void`. Root cause: `resolveDeclAggregateFieldTypes` at :886-937 fills in FieldEntry types for struct/tagged_union but may not correctly resolve fn_type annotated fields. Named struct FieldEntries stay TYPE_VOID from symbol_registrator pre-registration. Fix 1: ensure fn_type fields get resolved. Fix 2: add defensive void-field guard in emitStructType.

- [ ] **Step 1: Read source context**

Read `sf/src/type_resolver.zig:886-937` (resolveDeclAggregateFieldTypes — struct handling at :894-910, tagged_union at :911-934).
Read `sf/src/c89_emit.zig:1433-1456` (emitStructType — field loop at :1438-1453, no TYPE_VOID guard).
Read `sf/src/c89_emit.zig:1406-1422` (emitTaggedUnionType — note the void guard at :1410: `if (ft.kind != TypeKind.void_type)`).

- [ ] **Step 2: Verify + fix resolveDeclAggregateFieldTypes for fn_type fields**

Read the struct_type branch at :894-910. Line 898-899:
```zig
if (fd.kind == AstKind.field_decl and fd.child_0 != 0) {
    var ft = resolveTypeExprFull(env, fd.child_0, @intCast(u32, 0));
```

For a fn-typed field like `write_fn: fn([]const u8) void`, `fd.child_0` is the `fn_type` AST node. `resolveTypeExprFull` at :731-790 handles `AstKind.fn_type` — resolves return type, params, creates fn_type. It SHOULD return a proper TypeId.

Build and test the repro to verify if this branch IS already resolving the fn_type correctly for named structs. If `ft` returns fn_type TypeId (not TYPE_VOID/UNDEFINED), the issue is elsewhere. If it returns TYPE_UNDEFINED, investigate depth 0 recursion or fn_type resolution failure.

If the issue is that `resolveDeclAggregateFieldTypes` is never called for this struct (nameCacheGet miss), add a fallback: after the struct_decl resolution block at `type_resolver.zig:622-673`, scan the registerDecl-pre-registered named struct and back-patch its FieldEntries from the just-resolved anon_N struct.

If `ft` IS correctly resolved but not written: verify line 905 `env.typereg.fe_items[sp.fields_start + fi2].type_id = ft;` is reached (guard at :904 requires `ft != TYPE_UNDEFINED`). If the guard fires, the resolution returned UNDEFINED — debug why fn_type resolution fails at depth 0.

- [ ] **Step 3: Add void-field guard in emitStructType**

Read `sf/src/c89_emit.zig:1439-1453`. After line 1447 (`var ftype = getCTypeName(reg, emitter.mangler, fe.type_id);`), ADD:

```zig
        if (fe.type_id != type_mod.TYPE_VOID) {
```
And close the block after line 1452 (before the closing `}` of the while loop):
```zig
        }
```

This mirrors `emitTaggedUnionType:1410` pattern. Defense-in-depth — if any type leaks through unresolved, suppress emission rather than emitting `void`.

- [ ] **Step 4: Build + gate**

```bash
bash sf/scripts/build_release.sh
```

```bash
# Repro: was FAIL (void write_fn), should now be OK with proper fn-ptr typedef
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f2 repro/mi_matrix/fn_ptr_struct_field/main.zig
grep 'write_fn' /tmp/f2/*.h
# Should show fn-ptr typedef, NOT "void write_fn"
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f2/*.c
# Should compile clean
```

```bash
# MD5 gate
sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/mud_server/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/game_of_life/main.zig | md5sum
```

- [ ] **Step 5: Commit**

```bash
git add sf/src/type_resolver.zig sf/src/c89_emit.zig
git commit -m "fix(F-2): struct FieldEntries back-patch + void-field guard (I-R3)"
```

---

### Task F-3: Bare Union Type Resolution + Field-Store (I-R5 T1b + I-R7 void-union, 4 repros)

**Files:** `sf/src/type_resolver.zig:935`, `sf/src/type_registry.zig:784`, `sf/src/lower.zig:792` (+`lower.zig:1947` read path), `sf/src/c89_emit.zig:1511` (dispatch), `:3220` (store_field emission), `:3116`/`:3126` (load_field emission)

**Pre-requisites:** None. **MANDATORY pre-reading:** `.superpowers/sdd/I-R8-report.md` (2026-08-04 investigation) — this task was RE-WRITTEN per its findings. The original plan had the wrong payload array.

**Scope:** Bare `union_type` fields are stored in **`un_items` (UnionPayload)**, NOT `st_items` (StructPayload). Four coordinated defects:
1. `resolveDeclAggregateFieldTypes` (:886-937) has no `union_type` branch → bare union FieldEntries stay `TYPE_VOID` (the `symbol_registrator.zig:127` placeholder) forever
2. `lowerFieldStore` (:763-793) has no `union_type` branch → ICE `error[3043]` at :793 (3 repros)
3. `emitStructType` (:1511 dispatches union_type there) reads `st_items` for a union → emits ANOTHER struct's body (tu_uninit_data_void emits Value's body for Data → gcc `field 'data' has incomplete type`)
4. `store_field` C-emission (:3220) handles `struct_type` only → union store ICEs at `:3247` even after the lowerer fix
5. Latent: field-READ path `lower.zig:1947` dispatches struct/union/tagged_union to `typeRegistryGetStructFields` (st_items) → mis-index for unions

**Key layout fact:** `type_registry.zig:80` `UnionPayload = { fields_start: u16, fields_count: u16, tag_type: TypeId }`. Bare unions registered via `unAppend` → `un_items[payload_idx]` (`symbol_registrator.zig:145-155`). Structs use `st_items`. Tagged unions use `tu_items`. THREE separate arrays — never index the wrong one.

- [ ] **Step 1: Read evidence + source context**

Read `.superpowers/sdd/I-R8-report.md` (full investigation — Sections A/C/D are the authoritative design).
Read `sf/src/type_registry.zig:78-110` (payload structs + arrays), `:778-784` (typeRegistryGetStructFields — reads st_items), `:213-220` (unAppend/tuAppend).
Read `sf/src/symbol_registrator.zig:118-157` (union registration — `:127` TYPE_VOID placeholder, `:145-155` bare unAppend).
Read `sf/src/type_resolver.zig:886-937` (resolveDeclAggregateFieldTypes — struct :894-910, tagged_union :911-934, NO union branch).
Read `sf/src/lower.zig:734-798` (lowerFieldStore), `:1944-1959` (field-access READ path).
Read `sf/src/c89_emit.zig:1427-1458` (emitStructType — reads st_items at :1432), `:1505-1517` (emitTypeDefinition dispatch — union→emitStructType at :1511), `:3100-3135` (load_field), `:3200-3248` (store_field + ICE fallback).

- [ ] **Step 2: Add typeRegistryGetUnionFields helper (type_registry.zig)**

After `typeRegistryGetStructFields` (`:778-784`), ADD:

```zig
pub fn typeRegistryGetUnionFields(self: *TypeRegistry, tid: u32, out: *[]FieldEntry) void {
    var ty = self.types_items[tid];
    var up = self.un_items[ty.payload_idx];
    var fstart: usize = @intCast(usize, up.fields_start);
    var fcount: usize = @intCast(usize, up.fields_count);
    out.* = self.fe_items[fstart .. fstart + fcount];
}
```

Mirror of `typeRegistryGetStructFields` but reading `un_items` (UnionPayload).

- [ ] **Step 3: Add union_type branch to resolveDeclAggregateFieldTypes (type_resolver.zig)**

At `sf/src/type_resolver.zig:935` (after tagged_union_type closing `}`, before the final `}` of the `if (spid)` block), ADD:

```zig
        } else if (sty.kind == type_mod.TypeKind.union_type) {
            var up = env.typereg.un_items[@intCast(usize, sty.payload_idx)];
            while (fi2 < @intCast(usize, up.fields_count)) : (fi2 += 1) {
                var fd = env.store.nodes.items[@intCast(usize, fchildren[fi2])];
                if (fd.kind == AstKind.field_decl and fd.child_0 != 0) {
                    var ft = resolveTypeExprFull(env, fd.child_0, @intCast(u32, 0));
                    if (ft != type_mod.TYPE_UNDEFINED) {
                        env.typereg.fe_items[@intCast(usize, up.fields_start) + fi2].type_id = ft;
                    }
                }
            }
```

**CRITICAL:** `un_items` (NOT `st_items`). `up` is a `UnionPayload`. Mirrors the struct_type branch at :894-910 but reads the union payload array.

- [ ] **Step 4: Add union_type branch to lowerFieldStore (lower.zig)**

At `sf/src/lower.zig:792` (before `} else { iceFieldStoreUnsupported(...); }`), ADD:

```zig
        } else if (kind == type_mod.TypeKind.union_type) {
            var fields: []FieldEntry = undefined;
            type_mod.typeRegistryGetUnionFields(self.ctx.registry, type_box[0], &fields);
            var fi: usize = 0;
            var field_id: u32 = @intCast(u32, 0);
            while (fi < fields.len) : (fi += 1) {
                if (fields[fi].name_id == field_name_id) {
                    field_id = @intCast(u32, fi);
                    break;
                }
            }
            emitInst(self, LirInst{ .store_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = field_id, .value = value_temp } });
        }
```

**CRITICAL:** `typeRegistryGetUnionFields` (NOT `typeRegistryGetStructFields`). Mirrors the struct_type branch at :763-774.

- [ ] **Step 5: Fix field-READ path mis-index (lower.zig:1944-1959)**

The field-access READ handler currently dispatches `struct_type or union_type or tagged_union_type` together and calls `typeRegistryGetStructFields` at :1947 — mis-indexes for unions. Split union_type to use the new helper. Read `sf/src/lower.zig:1944-1959`, then restructure so the `union_type` case calls `typeRegistryGetUnionFields` (same match loop body as the struct case). If the match loop is shared verbatim, factor the loop into a local `var fields` populated by the right helper per kind.

- [ ] **Step 6: Add emitUnionType + dispatch (c89_emit.zig)**

Add a `emitUnionType` mirroring `emitStructType` (`:1427-1458`) but reading `un_items`, with the TYPE_VOID field guard:

```zig
fn emitUnionType(emitter: *C89Emitter, tid: u32) void {
    var reg = emitter.registry;
    var ty = reg.types_items[@intCast(usize, tid)];
    var mangled_id = nameManglerMangle(emitter.mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
    var mangled_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
    var up = reg.un_items[@intCast(usize, ty.payload_idx)];
    var fstart: usize = @intCast(usize, up.fields_start);
    var fcount: usize = @intCast(usize, up.fields_count);
    var es0a: []const u8 = "struct "; bufferedWriterWrite(&emitter.writer, es0a);
    bufferedWriterWrite(&emitter.writer, mangled_name);
    var es0: []const u8 = " {\n"; bufferedWriterWrite(&emitter.writer, es0);
    var i: usize = @intCast(usize, 0);
    while (i < fcount) : (i += 1) {
        var fe = reg.fe_items[fstart + i];
        if (fe.type_id != type_mod.TYPE_VOID) {
            var fname = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
            var ftype = getCTypeName(reg, emitter.mangler, fe.type_id);
            var es1: []const u8 = "\t"; bufferedWriterWrite(&emitter.writer, es1);
            bufferedWriterWrite(&emitter.writer, ftype);
            var es2: []const u8 = " "; bufferedWriterWrite(&emitter.writer, es2);
            bufferedWriterWrite(&emitter.writer, fname);
            var es3: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, es3);
        }
    }
    var es4: []const u8 = "};\n"; bufferedWriterWrite(&emitter.writer, es4);
}
```

Then change the dispatch at `:1511`:
```
OLD: if (ty.kind == TypeKind.union_type) { emitStructType(emitter, tid); return; }
NEW: if (ty.kind == TypeKind.union_type) { emitUnionType(emitter, tid); return; }
```

The `fe.type_id != TYPE_VOID` guard prevents `void Int;` if any union field still resolves to TYPE_VOID (defense-in-depth, matches F-2 pattern).

- [ ] **Step 7: Add union_type branch to store_field C-emission (c89_emit.zig)**

Read `sf/src/c89_emit.zig:3200-3248` (store_field emission). The value-base branch handles `struct_type` only at `:3220-3233`; a union base falls to `found2 == 0` → ICE at `:3247`. After the struct_type branch (before the closing `}` at :3233), ADD:

```zig
                            } else if (bty.kind == type_mod.TypeKind.union_type) {
                               var dot_s: []const u8 = ".";
                               bufferedWriterWrite(&emitter.writer, dot_s);
                               var up = emitter.registry.un_items[@intCast(usize, bty.payload_idx)];
                               var fe: type_mod.FieldEntry = emitter.registry.fe_items[@intCast(usize, up.fields_start) + @intCast(usize, sf.field_id)];
                               var fname: []const u8 = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
                               bufferedWriterWrite(&emitter.writer, fname);
                               found2 = @intCast(u8, 1);
                            }
```

Check whether the ptr-base branch (`:3208-3219`) also needs the same union handling — mirror if so.

- [ ] **Step 8: Fix load_field emission union mis-index (c89_emit.zig)**

Read `sf/src/c89_emit.zig:3100-3135` (load_field emission). The ptr (`:3111-3123`) and value (`:3124-3133`) branches already list `union_type` but read `st_items` (`:3116`, `:3126`). Change the union case to read `un_items` (add an `else if (kind == union_type)` branch reading `up.fields_start/count` from `un_items`, mirroring Step 7). Verify the field-name lookup resolves correctly.

- [ ] **Step 9: Build + gate**

```bash
bash sf/scripts/build_release.sh
```
Expected: `=== [release] Done ===`, 0 gcc errors (grep for `\.c:[0-9]+:[0-9]+: error`).

```bash
# Repros: all 4 must go from ICE/FAIL to OK
for d in tu_field_store_ptr tu_ptrcast_copy xmod_amp_arena_union_store tu_uninit_data_void; do
    sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f3/$d repro/mi_matrix/$d/main.zig
    echo "=== $d ==="
    gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f3/$d/*.c 2>&1 | head -5
done
```
Expected: dump rc=0 (no 3043), all gcc clean.

```bash
# tu_uninit_data_void header check: union body must list Data's OWN field, NOT Value's body
grep -A4 'struct zT_3F5279C5_Data' /tmp/f3/tu_uninit_data_void/zig_special_types.h
```
Expected: `struct zT_3F5279C5_Data { <i32-type> Int; };` — its own field, NOT `tag`/`data` (Value's body).

```bash
# MD5 gate
sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/mud_server/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/game_of_life/main.zig | md5sum
```
All 4 must match baselines: mud `9fde02d8a05e951de738e2df5d12b4f7`, gol `d0d3051d1cb1bd0db3ffd29495a2e18e`, lisp `10d09c99f77c68e680f6ccce33eb81ed`, json `3492a935883ee91258feece576ba23d5`.

- [ ] **Step 10: Commit**

```bash
git add sf/src/type_resolver.zig sf/src/type_registry.zig sf/src/lower.zig sf/src/c89_emit.zig
git commit -m "fix(F-3): bare union type resolution + field-store (I-R5 T1b + I-R7 void-union)"
```

---

### Task F-4: Cross-Module Import-Alias Type Resolution (I-R1#2 + I-R5 T2, 3 repros)

**Files:** `sf/src/type_resolver.zig` only (new `resolveImportFieldAliases` pass). NO `semantic_analyzer.zig` edits.

**Pre-requisites:** None. **MANDATORY pre-reading:** `.superpowers/sdd/I-R9-report.md` (2026-08-04 investigation — the authoritative design) AND `.superpowers/sdd/task-F4-report.md` (the REJECTED first proposal — read it as precedent, do NOT reapply its sema patch).

**Scope:** Root cause: `const S = @import("types.zig").S` registers symbol `S` as `SymbolKind.global` with `type_id=0` (symbol_registrator.zig:216-273 — field_access init falls through all type-alias branches) because `resolveTypeExprFull` has NO `import_expr` branch (type_resolver.zig:589-883; import_expr has no children, parser.zig:644, falls to TYPE_UNDEFINED at :883) and `TypeResolveEnv` (type_resolver.zig:23-29) has no module_reg. So `S.type_id` never gets set at definition time → sema resolves it TYPE_VOID → struct_init cache writes VOID → var_decl infers VOID → gcc FAIL / ICE 3043.

**Fix (Approach B, definition-time, path-accurate):** A dedicated pass in the type-resolution phase that resolves `const X = @import("path").Field` via `module_reg.path_to_id` (which `typeResolverResolveNames` already receives as a param at :1079) and writes `symbol.type_id` + the module-qualified nameCache key — mirroring the existing working named-module mechanism (symbol_registrator.zig:227-245 registers `const t = @import(...)` as a module symbol; the field_access branch resolves module bases at type_resolver.zig:702-712). The existing sema cache writes (:937/:965/:475) and lowerer queries (:3755/:751) are ALREADY correct — they fire once the symbol carries a correct type_id. The rejected proposal's sema `resolveIdent` patch is NOT reapplied.

- [ ] **Step 1: Read evidence + source context**

Read `.superpowers/sdd/I-R9-report.md` (Sections A/C/D are authoritative — exact code + insertion targets).
Read `.superpowers/sdd/task-F4-report.md` (rejected proposal — root-cause evidence §1, why sema patch was a patch §2, known limitations).
Read `sf/src/type_resolver.zig:589-717` (resolveTypeExprFull — field_access branch :674-717; the two module-base success paths :679-698 ident-module fallback and :702-712 module_type; import_expr NOT handled).
Read `sf/src/type_resolver.zig:949-991` (resolveNamedTypeExpressions + resolveAggregateFieldTypesAll — the pass layer, where the new pass slots in).
Read `sf/src/type_resolver.zig:1073-1088` (typeResolverResolveNames — module_reg param at :1079, sub-pass call order).
Read `sf/src/symbol_registrator.zig:227-245` (named-module registration precedent) and `:373-394` (inline import registers no symbol).
Read `sf/src/module_registry.zig:170-180` (path_to_id map).

- [ ] **Step 2: Add hash_mod import (type_resolver.zig)**

After line 21 (`const rtt_mod = ...`), ADD:
```zig
const hash_mod = @import("util/hash.zig");
```

- [ ] **Step 3: Add resolveImportFieldAlias + resolveImportFieldAliases (type_resolver.zig)**

Insert between line 984 (`}` closing `resolveNamedTypeExpressions`) and line 986 (`fn resolveAggregateFieldTypesAll`). Z98 dialect — capture syntax only (no `.?`), while loops, `@intCast`:

```zig
fn resolveImportFieldAlias(env: *TypeResolveEnv, module_reg: *mr_mod.ModuleRegistry,
    importer_mod_id: u32, target_mod_id: u32, field_name_id: u32, depth: u32) u32 {
    if (depth > @intCast(u32, 8)) return type_mod.TYPE_UNDEFINED;
    var fs = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, target_mod_id, field_name_id);
    if (fs) |fss| {
        if (fss.type_id != @intCast(u32, 0)) return fss.type_id;
        var fd = env.store.nodes.items[@intCast(usize, fss.decl_node)];
        if (fd.kind != AstKind.var_decl) return type_mod.TYPE_UNDEFINED;
        var fi = env.store.nodes.items[@intCast(usize, fd.child_1)];
        if (fi.kind != AstKind.field_access) return type_mod.TYPE_UNDEFINED;
        var fb = env.store.nodes.items[@intCast(usize, fi.child_0)];
        if (fb.kind != AstKind.import_expr) return type_mod.TYPE_UNDEFINED;
        var t2 = hash_mod.u32ToU32MapGet(&module_reg.path_to_id, fb.payload);
        if (t2) |m2| return resolveImportFieldAlias(env, module_reg, importer_mod_id, m2, fi.payload, depth + @intCast(u32, 1));
    }
    return type_mod.TYPE_UNDEFINED;
}

fn resolveImportFieldAliases(env: *TypeResolveEnv, mods: []mr_mod.ModuleEntry, module_reg: *mr_mod.ModuleRegistry) void {
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        var root = mods[mi].ast_root;
        if (root == @intCast(u32, 0)) continue;
        var rnode = env.store.nodes.items[@intCast(usize, root)];
        var decls = ast_mod.astStoreGetExtraChildren(env.store, rnode.payload);
        var di: usize = 0;
        while (di < decls.len) : (di += 1) {
            var decl = env.store.nodes.items[@intCast(usize, decls[di])];
            if (decl.kind != AstKind.var_decl) { continue; }
            if (decl.child_1 == @intCast(u32, 0)) { continue; }
            var init = env.store.nodes.items[@intCast(usize, decl.child_1)];
            if (init.kind != AstKind.field_access) { continue; }
            var base = env.store.nodes.items[@intCast(usize, init.child_0)];
            if (base.kind != AstKind.import_expr) { continue; }
            var target = hash_mod.u32ToU32MapGet(&module_reg.path_to_id, base.payload);
            if (target) |mtid| {
                var resolved = resolveImportFieldAlias(env, module_reg, mods[mi].id, mtid, init.payload, @intCast(u32, 0));
                if (resolved != type_mod.TYPE_UNDEFINED) {
                    var sym = sym_mod.symbolRegistryQualifiedLookup(env.symbol_reg, mods[mi].id, decl.payload);
                    if (sym) |sp| {
                        sp.type_id = resolved;
                    }
                    var ck: u64 = @intCast(u64, mods[mi].id) * @intCast(u64, 4294967296) + @intCast(u64, decl.payload);
                    type_mod.nameCachePut(env.typereg, ck, resolved);
                }
            }
        }
    }
}
```

Notes: recursion handles transitive aliases (`const A = @import("m").B` where `B = const B = @import("n").C`) with depth guard 8. Writes `sp.type_id` only (kind stays `global` — sema fast path at semantic_analyzer.zig:197 returns any non-zero type_id). The nameCache key `(mod_id << 32) | name_id` mirrors `resolveNamedTypeExpressions` at :977-978.

**Plan fix (2026-08-04, reviewer Important + empirical confirmation):** The loop must NOT manually advance `di` — the `while (…): (di += 1)` continuation does it. Earlier draft had `di += 1` inside the four guards and at the tail (net +2/iteration), silently skipping every other top-level decl (odd-index import aliases unresolved → gcc `'s' undeclared`). Empirically confirmed: alias at index 0 resolves, alias at index 1 fails. Removed all manual `di += 1` — now matches the plain `while (…): (di += 1)` idiom of `resolveNamedTypeExpressions` / `resolveAggregateFieldTypesAll` / `resolveFnSignatures`.

- [ ] **Step 4: Wire into the phase (typeResolverResolveNames)**

At `sf/src/type_resolver.zig:1085` (between `resolveNamedTypeExpressions(&env, mods);` and `resolveAggregateFieldTypesAll(&env, mods);`), INSERT:
```zig
resolveImportFieldAliases(&env, mods, module_reg);
```

- [ ] **Step 5: Build + gate**

```bash
bash sf/scripts/build_release.sh
```
Expected: `=== [release] Done ===`, 0 gcc errors (grep for `\.c:[0-9]+:[0-9]+: error`).

```bash
# Repros: all 3 must go from FAIL/ICE to OK
mkdir -p /tmp/f4/a /tmp/f4/b /tmp/f4/c
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f4/a repro/mi_matrix/ptrcast_slice_field_type/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f4/a/*.c 2>&1
# Expected: gcc clean (was 's' undeclared)

sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f4/b repro/mi_matrix/ptrcast_slice_field_void/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f4/b/*.c 2>&1
# Expected: rc=0, gcc clean (was ICE 3043)

sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f4/c repro/mi_matrix/ptrcast_slice_field_xmod/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f4/c/*.c 2>&1
# Expected: rc=0, gcc clean (was ICE 3043)
```

```bash
# MD5 gate
sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/mud_server/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/game_of_life/main.zig | md5sum
```
All 4 must match baselines: mud `9fde02d8a05e951de738e2df5d12b4f7`, gol `d0d3051d1cb1bd0db3ffd29495a2e18e`, lisp `10d09c99f77c68e680f6ccce33eb81ed`, json `3492a935883ee91258feece576ba23d5`. (The 4 baselines have zero `@import` — verified — so the pass is a byte-identical no-op for them.)

- [ ] **Step 6: Commit**

```bash
git add sf/src/type_resolver.zig
git commit -m "fix(F-4): cross-module import-alias type resolution at definition time (I-R1#2 + I-R5 T2)"
```

---

### Task F-5: Temp-Zero Sentinel Removal (I-R6, 1 repro)

**Files:** `sf/src/lower.zig:1398, :937, :662, :1626`

**Pre-requisites:** None.

**Scope:** Temp id 0 is valid (first param) but used as secondary "no value" sentinel alongside `TEMP_NONE=0xFFFFFFFF` (:57). Fix: eliminate 0-sentinel, use TEMP_NONE consistently.

- [ ] **Step 1: Read source context**

Read `sf/src/lower.zig:54-58` (TEMP_NONE constant).
Read `sf/src/lower.zig:1390-1415` (plain_assign — note `src == TEMP_NONE or src == @intCast(u32, 0)` at :1398, and `src != TEMP_NONE and src != @intCast(u32, 0)` at :1410).
Read `sf/src/lower.zig:934-938` (nameMapGet — returns 0 as not-found).
Read `sf/src/lower.zig:655-664` (default operand_temp = 0 at :662).
Read `sf/src/lower.zig:1620-1627` (default arr_temp = 0 at :1626).

- [ ] **Step 2: Edit plain_assign guard — lower.zig:1398**

Drop `or src == @intCast(u32, 0)`:
```
OLD: if (src == TEMP_NONE or src == @intCast(u32, 0)) {
NEW: if (src == TEMP_NONE) {
```

Also fix line 1410 (same pattern, in the guard AFTER the `is_resolved` block):
```
OLD: if (src != TEMP_NONE and src != @intCast(u32, 0) and getTempType(self, src) == type_mod.TYPE_VOID) {
NEW: if (src != TEMP_NONE and getTempType(self, src) == type_mod.TYPE_VOID) {
```

- [ ] **Step 3: Edit nameMapGet not-found — lower.zig:937**

```
OLD: return @intCast(u32, 0);
NEW: return TEMP_NONE;
```

- [ ] **Step 4: Edit callers defaulting to 0**

lower.zig:662:
```
OLD: var operand_temp: u32 = @intCast(u32, 0);
NEW: var operand_temp: u32 = TEMP_NONE;
```

lower.zig:1626:
```
OLD: var arr_temp: u32 = @intCast(u32, 0);
NEW: var arr_temp: u32 = TEMP_NONE;
```

- [ ] **Step 5: Emitter companion — TEMP_NONE sentinel in c89_emit.zig (AMENDMENT F-5-A)**

`nameMapGet` (Edit 3) now returns `TEMP_NONE` (0xFFFFFFFF) for not-found. The C89 emitter consumes `load_field.name_id` / `store_field.name_id` with a `!= 0` sentinel, so `TEMP_NONE` passes the `!= 0` check → `mangleLocalName(0xFFFFFFFF)` → OOB → SEGV. Update both consumer sites to use `TEMP_NONE` as the "no name, use temp" sentinel — same sentinel contract, consumer side.

**Edit A1 — `sf/src/c89_emit.zig:3064`** (load_field base resolution — REQUIRED, prevents SEGV):
```
OLD: var base = if (lf.name_id != @intCast(u32, 0)) mangleLocalName(emitter.mangler, emitter.interner, lf.name_id) else resolveTempName(emitter, lf.base);
NEW: var base = if (lf.name_id != @intCast(u32, 0) and lf.name_id != @intCast(u32, 0xFFFFFFFF)) mangleLocalName(emitter.mangler, emitter.interner, lf.name_id) else resolveTempName(emitter, lf.base);
```
COMBINED GUARD (AMENDMENT F-5-A2, operator ruling 2026-08-04): accepts BOTH no-name sentinels — legacy `0` (hardcoded producers: lower.zig load_field :2845,:2943,:3016,:3616) AND `0xFFFFFFFF` (== TEMP_NONE, nameMapGet producers after Edit 3). Either → `resolveTempName` (use temp base). Any real name_id → mangle. A single `!= 0xFFFFFFFF` breaks the hardcoded-0 producers (0 passes → mangleLocalName(0) → empty base → broken C).

**Edit A2 — `sf/src/c89_emit.zig:3207`** (store_field base resolution — same combined guard):
```
OLD: var base = if (sf.name_id != @intCast(u32, 0)) mangleLocalName(emitter.mangler, emitter.interner, sf.name_id) else resolveTempName(emitter, sf.base);
NEW: var base = if (sf.name_id != @intCast(u32, 0) and sf.name_id != @intCast(u32, 0xFFFFFFFF)) mangleLocalName(emitter.mangler, emitter.interner, sf.name_id) else resolveTempName(emitter, sf.base);
```
All 5 store_field producers in lower.zig emit hardcoded `name_id = 0` today; combined guard keeps them on the use-temp path while also covering a future TEMP_NONE producer. AMENDMENT rationale (operator ruling 2026-08-04): the sentinel swap is ONE fix at two contract points (producer=lower.zig, consumer=c89_emit.zig); updating the consumer is the same design correction, NOT a patch.

- [ ] **Step 6: Build + gate**

```bash
# Build in /tmp/zb (operator ruling — DO NOT use sf/build/out_release/):
# reuse /tmp/zb/zig0; zig0 --header-priority-include -o /tmp/zb/zig1.c sf/src/main.zig; gcc link per QUICK_REF with /tmp/zb/*.c + src/include/zig_pal.c
```

```bash
# Runtime-verification gate (primary; replaces byte-identity for mud per AMENDMENT F-5-B):
# The fix's purpose is to emit stores previously dropped (first-param RHS). Different C output
# for CORRECT runtime behavior is intended, not a regression. Verify runtime behavior unchanged:
#   mud: build+run, confirm server still listens on port 4000
#   lisp: build+run, confirm (+ 1 2) -> > 3
#   json: build+run, confirm parses test.json
#   gol:  build+run, confirm glider pattern
#   tco examples: build+run unchanged
```

```bash
# MD5 gate (AMENDMENT F-5-B: re-baselined):
#   lisp: 10d09c99f77c68e680f6ccce33eb81ed  (must stay byte-identical — verified Edit3-alone is crash trigger)
#   json: 3492a935883ee91258feece576ba23d5  (must stay byte-identical)
#   gol:  d0d3051d1cb1bd0db3ffd29495a2e18e  (must stay byte-identical)
#   mud:  RE-BASELINE — capture new hash after fix; mud legitimately changes (first-param store now emitted)
# Capture new mud hash and record it in QUICK_REF.md
```

```bash
# Repro field_store_drop (AMENDMENT F-5-C):
# NOTE: fails frontend error[3048]: could not resolve imported file 'pal' on BOTH pristine and fixed builds —
# pre-existing import-resolver gap (F-S10 re-bucketed). NOT an F-5 deliverable. Document as known issue,
# do NOT fix here. F-5 validity comes from mud/lisp/json/gol runtime verification.
```

- [ ] **Step 7: Commit**

```bash
git add sf/src/lower.zig sf/src/c89_emit.zig
git commit -m "fix(F-5): temp-zero sentinel removal — use TEMP_NONE consistently (I-R6)"
```

---

### Task F-6: Orelse RHS Resolution (I-R4 Bug 1, 1 repro)

**Files:** `sf/src/semantic_analyzer.zig:814-819`

**Pre-requisites:** None.

**Scope:** `semanticAnalyzerResolveOrelseExpr` (:794-820) resolves `child_0` (optional) but never `child_1` (RHS fallback). Anon struct-init on RHS has no expected type → TYPE_VOID → gcc incompatible types. Fix: push `opt.payload` as expected type, resolve `child_1`, pop. Same pattern as var-decl init at :1602.

- [ ] **Step 1: Read source context**

Read `sf/src/semantic_analyzer.zig:794-820` (full orelse handler). Note: :796 resolves child_0, :814-819 unwrap optional + return `opt.payload`. child_1 never resolved.
Read `sf/src/semantic_analyzer.zig:1443-1468` (pushExpectedType/popExpectedType/topExpectedType — understanding the stack API).

- [ ] **Step 2: Add RHS resolution**

After the `return opt.payload;` at line 819, the function returns the unwrapped payload type. The RHS needs to be resolved BEFORE this return (or integrated into the control flow).

Edit the return at :817-819:
```zig
    var opt = self.registry.opt_items[@intCast(usize, ty.payload_idx)];
    coercion_mod.coercionTableAdd(self.coercion_table, node.child_0, coercion_mod.CoercionKind.unwrap_optional, opt.payload);
    // ADD: resolve RHS with expected type = opt.payload
    if (node.child_1 != @intCast(u32, 0)) {
        pushExpectedType(self, opt.payload);
        var rhs_result = semanticAnalyzerResolveExpr(self, node.child_1);
        popExpectedType(self);
        if (rhs_result != @intCast(u32, 0) and rhs_result != type_mod.TYPE_VOID) {
            tryRecordCoercion(self, node.child_1, rhs_result, opt.payload);
        }
    }
    return opt.payload;
```

The `tryRecordCoercion` call ensures the coercion table gets the resolution so the lowerer can `materializeInto(rhs, opt.payload, ...)`.

- [ ] **Step 3: Build + gate**

```bash
bash sf/scripts/build_release.sh
```

```bash
# Repro: was FAIL (gcc incompatible types), should now be OK
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f6 repro/mi_matrix/anon_init_orelse_rhs/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f6/*.c && gcc -m32 /tmp/f6/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f6/prog && /tmp/f6/prog
```
Expected: gcc clean, prints `6` (was incompatible types FAIL).

```bash
# Regression: verify orelse_void and optstar_void_orelse still byte-identical
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f6/r1 repro/mi_matrix/orelse_void/main.zig 2>&1 | head -1
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f6/r2 repro/mi_matrix/optstar_void_orelse/main.zig 2>&1 | head -1
```
Expected: no new errors.

```bash
# MD5 gate
sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/mud_server/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/game_of_life/main.zig | md5sum
```

- [ ] **Step 4: Commit**

```bash
git add sf/src/semantic_analyzer.zig
git commit -m "fix(F-6): orelse RHS resolution — resolve child_1 with expected type (I-R4 Bug1)"
```

---

### Task I-7: Investigate Module-Global Init Design (I-R1#1 + I-R7 comptime) — RUNS BEFORE F-7

**Added by operator ruling 2026-08-04 (m1250):** F-7 is the largest architectural task (~150 lines, 3 files, new pipeline concept). The plan's own Step 4 is self-declared wrong, and Step 3 contains a verified-wrong assumption (emitter `load_global`/`store_global` use `mangleLocalName` at c89_emit.zig:3043/:3054, NOT `nameManglerMangle(kind=3)` as the plan states). Investigation FIRST, amend F-7 with a concrete design, THEN STOP for operator decision before implementing.

**Files to investigate:**
- `sf/src/main.zig:570-589` (phase_LIRLowering module-decl loop — empty `else {}` at :587-588, only `fn_decl` lowered)
- `sf/src/lower.zig:1032-1041` (lowerGlobalRef — emits `decl_local`, not `load_global`)
- `sf/src/lower.zig:256` (lowererInit), `:4404` (lowerFn — how a LirFunction is built: blocks, hoisted_temps, params)
- `sf/src/lir.zig:73-74` (load_global/store_global variants), `sf/src/lir.zig:326-338` (LirFunction struct)
- `sf/src/c89_emit.zig:3041-3060` (load_global/store_global C emission — note `mangleLocalName`, NOT global mangler)
- `sf/src/c89_emit.zig:2105-2138` (emitModuleFile — where global declarations must be emitted), `:2041-2073` (emitModule stdout path)
- `sf/src/symbol_table.zig` (Symbol struct: kind, flags, type_id, decl_node)
- `sf/src/main.zig:600-612` (phase_LIRLowering tail — module-registry handling after decl loop)

**Investigation questions (write report to `.superpowers/sdd/I-R11-report.md`):**
1. **Module-decl lowering path:** Exactly how does main.zig:587-588 skip module-level var_decl/const? What is the full set of module-scope decl kinds (var_decl with init, const, type-alias, import)? Which need global C declarations + init, which are type-only (already handled)?
2. **store_global/load_global flow:** The LIR variants exist (lir.zig:73-74) and the C emitter handles them (c89_emit.zig:3041-3060) — but emits via `mangleLocalName`. What C name does a global get? Is `mangleLocalName` correct for globals, or is a global-mangler needed (nameManglerMangle kind=3)? Verify what C identifier a `store_global{name_id}` would produce and whether two modules with same-named globals would collide.
3. **Global declaration emission:** Where must `int x;` / `struct Writer out;` C declarations be emitted? In emitModuleFile (per-module .c, before fn loop at :2122)? In emitModule (stdout)? How does the emitter discover which globals to declare — from the fn list's load_global/store_global references, or from the symbol table (SymbolKind.global, type_id via resolved_type_table)?
4. **__module_init synthesis:** How is a LirFunction constructed (lowerFn pattern at lower.zig:4404)? Can a synthetic function be created with params_count=0, return_type=VOID, name_id=intern("__module_init")? How are `store_global` instructions emitted into its entry block? How does main.zig append it to ctx.lir_fns? How is it marked so the emitter emits it AND calls it before user main()?
5. **Init value lowering per kind:** module-level var_decl inits: int/float/char literal, fn call, struct-init, array-init, comptime-folded (comptime_values map). Which lower cleanly via lowerExpr into a temp then store_global? Which need special handling (comptime value lookup at lower.zig:2393-2407 intcast fold, module_const_fn_call needs fn call)?
6. **Immutable const globals:** `const x: i32 = 42;` — currently `lowerGlobalRef` emits decl_local for the READ (uninitialized local shadow). Does F-7 need to change const-reads too, or only mutable? Should const-literal globals emit a C `const`/initialized global, or inline the literal at use site? (module_var_mutable GREEN uses const and works today — how?)
7. **Interaction with existing green paths:** module_var_mutable/main_green.zig (`const x = 42`) works today — trace how (literal-inline path at lower.zig:1497-1549?). Ensure F-7 doesn't break it.
8. **Blast radius + A/B/C design:** What's the minimal correct design? Option A: synthesize __module_init + emit global decls + load_global/store_global. Option B: inline const literal at use, only mutable gets global+init. Option C: C-initializer for literal globals (int x = 42;) + __module_init only for fn-call inits. Recommend one with exact file:line targets. Consider MD5 impact on the 4 gated examples (do any have module-scope var/const? if yes, F-7 changes their emission).

**Output:** `.superpowers/sdd/I-R11-report.md` with A/B/C options + exact edit targets. No source changes. Empty gate commit optional. This is an INVESTIGATION task — NO implementation.

---

### Task F-7: Module-Global Init (I-R1#1 + I-R7 comptime, 6 repros) — OPTION B

**Pre-requisites:** I-7 (I-R11) report complete. **OPERATOR RULING 2026-08-04: Option B** (assessed A/B/C against architecture/scalability/maintainability — B approved). Full design in `.superpowers/sdd/I-R11-report.md`.

**Design (Option B):** inline literal consts stay inlined (lower.zig:1517-1570, compile-time constants — correct); mutable vars + non-literal consts become real globals via `load_global`/`store_global` + a synthesized `__module_init` function. Global mangler = `nameManglerMangle(kind=1)` (zG_hash_name, the natural third namespace; kind=3 in the old plan text was WRONG — falls to L prefix). **Must add `module_id` field to load_global/store_global LIR insts** (lir.zig:73-74) or cross-module globals collide. lisp+mud re-baseline (they have mutable module vars — correctness fix); json+gol byte-identical.

**Files:** `sf/src/lir.zig`, `sf/src/main.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`. ~150 lines across 4 files.

- [ ] **Step 1: Read I-7 evidence + source**

Read `.superpowers/sdd/I-R11-report.md` (full design, 9 edit targets). Read `.superpowers/sdd/I-R1-report.md`.
Read current source at the 9 target sites (line numbers below are from I-R11; verify against source before editing):
1. `lir.zig:73-74` — load_global/store_global (add module_id)
2. `main.zig:580-588` — phase_LIRLowering decl loop (empty else)
3. `lower.zig:4404` — lowerFn scaffolding (mirror for lowerModuleInit)
4. `lower.zig:1032-1041` — lowerGlobalRef (decl_local → load_global)
5. `lower.zig:1517-1570` — literal-inline path (KEEP untouched)
6. `c89_emit.zig:3041-3062` — load_global/store_global C emission (mangleLocalName → nameManglerMangle kind=1 + module_id; array copy-loop)
7. `c89_emit.zig:2145-2167` — emitModuleFile (global decl pass before fn loop)
8. `c89_emit.zig:2070-2102` — emitModule stdout (global decl pass before fn loop)
9. `c89_emit.zig:2104-2139` — emitMainWrapper (call __module_init before user main, only for modules with storage globals)

- [ ] **Step 2: lir.zig — add module_id to load_global/store_global**

Read `sf/src/lir.zig:68-78`. Change:
```
OLD: load_global: struct { name_id: u32, result: u32 },
     store_global: struct { name_id: u32, value: u32 },
NEW: load_global: struct { name_id: u32, module_id: u32, result: u32 },
     store_global: struct { name_id: u32, module_id: u32, value: u32 },
```

- [ ] **Step 3: lower.zig — new lowerModuleInit (mirror lowerFn scaffolding)**

Read `sf/src/lower.zig:4404-4501` (lowerFn). Add a new `pub fn lowerModuleInit(self: *LirLowerer, decls: []u32) LirFunction`:
- SandAlloc LirFunction, name_id = intern("__module_init"), return_type = TYPE_VOID, empty params, is_extern=0, is_pub=0
- Set self.func, current_bb = createBlock, emit loop_header, temp_counter = 0
- For each decl that is `var_decl` with a storage-global symbol and a runtime init (NOT undefined, NOT literal-const-inline, NOT type-only):
  - `var t = lowerExpr(self, node.child_1);`
  - `emitInst(LirInst{ .store_global = .{ .name_id, .module_id = <module>, .value = t } });`
- Skip `undefined` inits entirely (bare zero-init declaration)
- emit ret_void, hoistTemps, set func_ptr.hoisted_temps

- [ ] **Step 4: main.zig:580-588 — scan storage globals + build global registry + append __module_init**

Read `sf/src/main.zig:570-612`. Replace the empty `else {}` at :587-588 with:
1. For each module decl, classify via symbol table: `SymbolKind.global` storage global (mutable `var` OR non-literal `const`) → record `{ name_id, module_id, type_id (from resolvedTypeTableGet), has_runtime_init }` into a per-module global registry (new ctx-level structure)
2. Skip type-only (module/type_alias), literal-const (inline path), fn_decl (existing), test_decl, c_include
3. After the module's decl loop completes, if the module has any runtime-init storage globals: create a fresh lowerer (pattern :582-583), call `lowerModuleInit(&lowerer, decls)`, append result to `ctx.lir_fns` — appended AFTER the module's fns so lir_fns stays module-grouped (main.zig:663-667 slicing is load-bearing)

- [ ] **Step 5: lower.zig:1032-1041 — lowerGlobalRef emits load_global for non-inline globals**

Read `sf/src/lower.zig:1032-1041`. Keep the literal-inline path at :1517-1570. For globals that reach lowerGlobalRef (mutable var OR non-literal const), emit `load_global{ name_id, module_id (from symbol), result }` instead of `decl_local`. `module_id` comes from the resolved symbol.

- [ ] **Step 6: lower.zig — global-name base handling for field/index/addr ops**

For `load_field`/`load_index`/`assign_field`/`addr_of` whose base resolves to a global, preserve the global `name_id` in the LIR inst's name_id field (name path already supported by C handlers at c89_emit.zig:2790/2889/3064). Required for: module_pub_var_struct (`out.tag`), mud (`rooms[i]`), lisp (`&perm_buf_u64`). This is the array-global sub-piece.

- [ ] **Step 7: c89_emit.zig:3041-3062 — global mangler + array copy-loop**

Read `sf/src/c89_emit.zig:3041-3062`. Change:
- `mangleLocalName` → `nameManglerMangle(mangler, name_id, 1, module_id)` for both load_global and store_global (kind=1 = G prefix)
- Add array copy-loop for `load_global` when the global type is an array (mirror load_local at :2985-2994) and for `store_global` (mirror .assign at :2858-2877) — or rely on name-base access for arrays (Step 6) and only copy in value contexts

- [ ] **Step 8: c89_emit.zig — emit global C declarations**

In `emitModuleFile` (:2145-2167): after the `#include "<mod>.h"` line, before the fn loop, iterate the global registry filtered by module_id, emit `getCTypeName(type) zG_<hash>_<name>;` for each.
In `emitModule` (:2070-2102): after emitModuleHeader, before the fn loop, same pass.

- [ ] **Step 9: c89_emit.zig:2104-2139 — call __module_init before user main**

In `emitMainWrapper`, before `wfn_name();`, emit a call to each module's `__module_init` (mangled nameManglerMangle kind=0, module_id) — ONLY for modules that have storage globals (from the global registry), in module_reg order.

- [ ] **Step 10: main.zig phase_C89Emission — inject global registry into emitter**

Read `sf/src/main.zig:633-735`. Inject the global registry into the emitter (pattern: pointer_only_map injection at :636).

- [ ] **Step 11: Build + gate (in /tmp/zb per operator ruling)**

Build in /tmp/zb (reuse /tmp/zb/zig0; zig0 → C; gcc link). 0 gcc errors.

```bash
# Repro 1: module_var_mutable — was FAIL ('x' undeclared), should now be gcc clean
/tmp/zb/zig1 --dump-c89 --output-dir /tmp/f7/a repro/mi_matrix/module_var_mutable/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f7/a/*.c 2>&1
```
Expected: gcc clean.

```bash
# Repro 2: module_pub_var_int — was runtime gap, should print 43
/tmp/zb/zig1 --dump-c89 --output-dir /tmp/f7/b repro/mi_matrix/module_pub_var_int/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f7/b/*.c && gcc -m32 /tmp/f7/b/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f7/prog2 && /tmp/f7/prog2
```
Expected: prints `43`.

```bash
# Repro 3: module_pub_var_struct — was runtime gap, should print 7
/tmp/zb/zig1 --dump-c89 --output-dir /tmp/f7/c repro/mi_matrix/module_pub_var_struct/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f7/c/*.c && gcc -m32 /tmp/f7/c/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f7/prog3 && /tmp/f7/prog3
```
Expected: prints `7`.

```bash
# Repro 4: module_const_fn_call — was runtime gap, should print 42
/tmp/zb/zig1 --dump-c89 --output-dir /tmp/f7/d repro/mi_matrix/module_const_fn_call/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f7/d/*.c && gcc -m32 /tmp/f7/d/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f7/prog4 && /tmp/f7/prog4
```
Expected: prints `42`.

```bash
# Repro 5: comptime_neg_int — was runtime gap, should print -5
/tmp/zb/zig1 --dump-c89 --output-dir /tmp/f7/e repro/mi_matrix/comptime_neg_int/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f7/e/*.c && gcc -m32 /tmp/f7/e/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f7/prog5 && /tmp/f7/prog5
```
Expected: prints `-5`.

```bash
# Repro 6: var_declared_void — was FAIL, may still fail if sema doesn't reject void vars
/tmp/zb/zig1 --dump-c89 --output-dir /tmp/f7/f repro/mi_matrix/var_declared_void/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f7/f/*.c 2>&1
```
Expected: may stay FAIL (gcc error on void var) — deeper fix is sema rejecting void vars, out of scope.

```bash
# MD5 gate (Option B: lisp + mud RE-BASELINE; json + gol must stay byte-identical)
/tmp/zb/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig 2>/dev/null | md5sum   # NEW (has mutable vars)
/tmp/zb/zig1 --dump-c89 examples/z98/json_parser/main.zig 2>/dev/null | md5sum            # 3492a935... (must match)
/tmp/zb/zig1 --dump-c89 examples/z98/mud_server/main.zig 2>/dev/null | md5sum             # NEW (has mutable vars)
/tmp/zb/zig1 --dump-c89 examples/z98/game_of_life/main.zig 2>/dev/null | md5sum           # d0d3051d... (must match)
```
Capture NEW lisp+mud hashes. json/gol must stay byte-identical.

```bash
# Runtime verification (PRIMARY gate per AMENDMENT F-5-B): all 4 examples behave correctly
# lisp: printf '(+ 1 2)\n' | prog -> > 3 ; mud: "listening on port 4000" ; json: parses test.json ; gol: glider
```

```bash
# Corpus sweep — must not regress beyond pre-existing (QUICK_REF classifier, /tmp/zb/zig1)
```

- [ ] **Step 12: Commit**

```bash
git add sf/src/lir.zig sf/src/main.zig sf/src/lower.zig sf/src/c89_emit.zig
git commit -m "fix(F-7): module-global init — constructor synthesis + global emission, Option B (I-R1#1 + I-R7 comptime)"
```

**After F-7 commit:** update QUICK_REF.md MD5 table with the NEW lisp/mud hashes (F-D3 doc task, or note for final review).

---

### Task I-8: Investigate Shared-Header Ordering for By-Value Optional/Slice (I-R4 Bug 2 pre-blocker)

**Added by operator ruling 2026-08-04 (m1241):** F-6 exposed a pre-existing, independent bug blocking the `anon_init_orelse_rhs` gcc-clean gate. It is NOT covered by F-1..F-7 but IS in the whole-plan scope (resolve the corpus RED issues). Investigation FIRST, then fix as F-8.

**Files to investigate:** `sf/src/c89_emit.zig` (emitSharedHeader :983-1121, shared_set computation, ctypeGuardWrite), `sf/src/type_resolver.zig` (typeRegistryGetOrCreateOptional), `sf/src/c89_emit.zig` tstIsDep/c89NeedsEmitEdge (closure-edge model).

**Repros that exercise it:** `anon_init_orelse_rhs` (primary — optional-of-Command-by-value), `optstar_void_orelse`, any optional/slice of a by-value struct.

**Known symptom (from F-6 report):** `zig_special_types.h` emits optional `zT_..._Opt_21 { zT_C67C8F52_Command value; int has_value; }` while `Command` (by-value struct/tagged_union) is only forward-declared there → gcc `field 'value' has incomplete type`. Header byte-identical pre/post F-6.

**Known root-cause hypothesis (from F-6 report):** F-S8 AMENDMENT-4/Option-3 restricted `tstIsDep` optional/slice source branches to enum_type/error_set_type element targets ONLY. A shared synthetic optional embedding a by-value struct by value does NOT promote that struct into `shared_set` → the optional wrapper lands in the shared header before/without the full struct definition → fwd-decl insufficient for by-value embedding.

**Investigation questions (write report to `.superpowers/sdd/I-R10-report.md`):**
1. Confirm the exact emission order in `emitSharedHeader`: where does the optional wrapper get emitted relative to the struct it embeds by value? Is the struct even in `shared_set`?
2. Confirm whether `tstIsDep`'s optional/slice branch (restricted to enum/error_set) is the reason the by-value struct is NOT promoted. Does the synthetic optional (`name_id==0`, always in shared_set) create an edge to the struct via `fieldEmbedsByValue`/`tstIsDep`?
3. Determine the correct fix location: (a) extend tstIsDep optional/slice branches to also promote by-value struct/tagged_union/union targets (NOT just enum/error_set), or (b) reorder emitSharedHeader so by-value embedded structs are emitted before the wrappers, or (c) both.
4. Blast radius: which corpus repros + 4 gated examples would change if optional/slice-of-struct now promotes the struct into shared_set? Could this re-order types in the shared header for lisp/json/mud/gol (MD5 impact)?
5. Verify against the F-S8 rationale (b2): the fwd-decl pass emits `typedef struct X X;` for all named struct/TU/union — fwd-decl is sufficient ONLY when the reference is through a POINTER. Confirm optional-by-value embeds the struct INLINE (not via pointer) so fwd-decl is genuinely insufficient.
6. A/B/C fix options with exact file:line targets.

**Output:** `.superpowers/sdd/I-R10-report.md`. No source changes. Empty gate commit optional.

---

### Task F-8: Fix Shared-Header Ordering for By-Value Optional/Slice (I-R4 Bug 2)

**Pre-requisites:** I-8 report complete.

**Scope:** Implement the I-8-approved root fix so `anon_init_orelse_rhs` reaches gcc-clean + prints 6. Likely: extend the closure-edge model so a shared synthetic optional/slice embedding a by-value struct promotes that struct into shared_set (and/or reorder emitSharedHeader). Exact design per I-8.

**Gates:**
- Build 0 errors
- `anon_init_orelse_rhs`: dump rc=0, gcc clean, link+run prints `6` (completes F-6's unsatisfiable gate)
- Regression: `orelse_void`, `optstar_void_orelse`, `field_access_optional` behavior unchanged
- 4 MD5s (current post-F-7 baselines): lisp `f84c8748e6d0580ffac811d75e34e0e7`, json `3492a935883ee91258feece576ba23d5`, mud `4644ad1349c55af80fa1a18fe0e17989` (F-7 re-baselines), gol `d0d3051d1cb1bd0db3ffd29495a2e18e` — RE-BASELINE any that legitimately re-order the shared header, per AMENDMENT F-5-B runtime-behavior principle
- Corpus: no NEW regressions

**Commit:** `fix(F-8): shared-header ordering for by-value optional/slice (I-R4 Bug 2)`

---

## Execution Order

```
F-1 → F-2 → F-3 → F-4 → F-5 → F-6 → I-7 → [STOP for operator decision] → F-7 → I-8 → F-8
```

F-1..F-6 independent. **I-7 (investigate module-global init design) runs BEFORE F-7, then STOP for operator ruling on the A/B/C design** (operator ruling 2026-08-04). F-7 implements after ruling. I-8 (investigate shared-header ordering, added m1241) then F-8 completes the F-6-exposed header-ordering bug.

