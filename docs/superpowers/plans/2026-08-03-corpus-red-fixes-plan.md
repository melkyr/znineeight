# Corpus-RED Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 7 root-cause clusters spanning 19 RED repros (FAIL+ICE+runtime-gap) in the Z98→C89 compiler pipeline. Principle: fix root causes at their source, not symptoms at emission sites.

**Architecture:** Seven independent fix categories ordered by pipeline phase (most upstream first). Each fix touches 1-2 files, gates its own repros, and verifies corpus/MD5 regression-free. F-7 (module-global init, ~150 lines) is the largest.

**Tech Stack:** Z98 (zig0 → zig1 → gcc -m32 -std=c89). Source in `sf/src/`. Repro in `repro/mi_matrix/<name>/`.

## Global Constraints

- Build gate: `bash sf/scripts/build_release.sh` → `=== [release] Done ===`, 0 gcc errors
- Corpus: no regression from baseline `165/15/6/0` (FAIL count may decrease, must NOT increase)
- 4 MD5 baselines byte-identical: mud `9fde02d8a05e951de738e2df5d12b4f7`, gol `d0d3051d1cb1bd0db3ffd29495a2e18e`, lisp `10d09c99f77c68e680f6ccce33eb81ed`, json `3492a935883ee91258feece576ba23d5`
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

**Files:** `sf/src/type_resolver.zig:935`, `sf/src/lower.zig:792`

**Pre-requisites:** None.

**Scope:** `resolveDeclAggregateFieldTypes` (:886-937) has no `union_type` branch → bare union fields stay TYPE_VOID. Two symptoms: (a) emitStructType emits `void fieldname;` (I-R7 tu_uninit_data_void), (b) lowerFieldStore ICEs at :793 (I-R5 T1b). Fix: add union_type branch to resolveDeclAggregateFieldTypes + union_type branch to lowerFieldStore (mirrors struct_type).

- [ ] **Step 1: Read source context**

Read `sf/src/type_resolver.zig:886-937` (full function — note struct_type :894-910, tagged_union_type :911-934, NO union_type branch).
Read `sf/src/lower.zig:755-798` (lowerFieldStore — struct_type :763-774, slice :775-779, tagged_union :780-791, else/ICE :792-793).
Read `sf/src/type_registry.zig` for `UnionPayload` struct (find field layout — bare union uses same `st_items[payload_idx]` with `fields_start`/`fields_count`).

- [ ] **Step 2: Add union_type branch to resolveDeclAggregateFieldTypes**

At `sf/src/type_resolver.zig:935` (after tagged_union_type closing `}`, before the final `}` of the while/if), ADD:

```zig
        } else if (sty.kind == type_mod.TypeKind.union_type) {
            var up = env.typereg.st_items[@intCast(usize, sty.payload_idx)];
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

This mirrors the struct_type branch at :894-910. Bare unions use `st_items[payload_idx]` (same StructPayload layout as struct_type).

- [ ] **Step 3: Add union_type branch to lowerFieldStore**

At `sf/src/lower.zig:792` (before `} else { iceFieldStoreUnsupported(...); }`), ADD:

```zig
        } else if (kind == type_mod.TypeKind.union_type) {
            var fields: []FieldEntry = undefined;
            type_mod.typeRegistryGetStructFields(self.ctx.registry, type_box[0], &fields);
            var fi: usize = 0;
            var field_id: u32 = @intCast(u32, 0);
            while (fi < fields.len) : (fi += 1) {
                if (fields[fi].name_id == field_name_id) {
                    field_id = @intCast(u32, fi);
                    break;
                }
            }
            emitInst(self, LirInst{ .store_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = field_id, .value = value_temp } });
```

This mirrors the struct_type branch at :763-774. Bare unions have identical C struct representation — same field access/store pattern.

- [ ] **Step 4: Build + gate**

```bash
bash sf/scripts/build_release.sh
```

```bash
# Repros: all 4 must go from ICE/FAIL to OK
for d in tu_field_store_ptr tu_ptrcast_copy xmod_amp_arena_union_store tu_uninit_data_void; do
    sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f3/$d repro/mi_matrix/$d/main.zig
    gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f3/$d/*.c 2>&1 | head -5
done
```
Expected: all gcc clean, no ICE.

```bash
# MD5 gate
sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/mud_server/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/game_of_life/main.zig | md5sum
```

- [ ] **Step 5: Commit**

```bash
git add sf/src/type_resolver.zig sf/src/lower.zig
git commit -m "fix(F-3): bare union type resolution + field-store (I-R5 T1b + I-R7 void-union)"
```

---

### Task F-4: Cross-Module Resolved Type Cache (I-R1#2 + I-R5 T2, 3 repros)

**Files:** `sf/src/semantic_analyzer.zig:475, :937, :965`

**Pre-requisites:** None.

**Scope:** Lowerer queries `resolvedTypeTableGet` at two sites: (1) `lower.zig:3755` for `var s = S{...}` init expression, (2) `lower.zig:751` for `s.key = ...` field-store base. Cross-module types resolve correctly in sema but the cache entry at the query node is missing. Fix: ensure `resolvedTypeTableSet` fires at the struct_init node (:937/:965) and at the field_access node (:475) for cross-module as well as local types. Extend commit `9672c45f` precedent.

- [ ] **Step 1: Read source context**

Read `sf/src/semantic_analyzer.zig:903-969` (semanticAnalyzerResolveStructInit — tagged_union :912-938, struct :940-967). Note existing `resolvedTypeTableSet(self.type_table, node_idx, target_type)` at :937/:965.
Read `sf/src/semantic_analyzer.zig:460-485` (semanticAnalyzerResolveFieldAccess — note `resolvedTypeTableSet(self.type_table, node_idx, result)` at :475).
Read `sf/src/lower.zig:3748-3756` (var_decl lowering — queries `resolvedTypeTableGet(node.child_1)`).
Read `sf/src/lower.zig:750-751` (field-store base — queries `resolvedTypeTableGet(fa_node.child_0)`).

- [ ] **Step 2: Verify existing cache writes, add missing ones**

The existing code at :937 (tagged_union struct_init) and :965 (struct struct_init) DOES write `resolvedTypeTableSet(self.type_table, node_idx, target_type)`. The field_access handler at :475 writes `resolvedTypeTableSet(self.type_table, node_idx, result)`.

Verify whether these writes fire for cross-module types. The `target_type` at :937/:965 comes from `topExpectedType` or explicit `child_0` resolution. For imported structs, `topExpectedType` should be set by the var_decl init's `pushExpectedType(decl_type)` at `semantic_analyzer.zig:1602`.

If the writes DO fire (verified by marker trace or GDB at build time), the gap is in the lowerer querying the WRONG node. Check: does `lower.zig:3755` query `node.child_1` (the init expression node) — the same node that sema writes at :937/:965? Yes, they should be the same `AstKind.struct_init` node_idx.

If there IS a cache mismatch, the fix is to ALSO write the cache entry at the var_decl level: in the var_decl handler at `semantic_analyzer.zig:1658-1660`, extend to always write `resolvedTypeTableSet(self.type_table, node.child_1, decl_type)` for cross-module struct types, including when `decl_type` was inferred.

For field_store: the field_access node's `child_0` is the ident_expr for `s` in `s.key = ...`. The field_access handler at :475 writes `resolvedTypeTableSet(self.type_table, node_idx, result)` where `node_idx` is the field_access node and `result` is the individual field type. The lowerer at `lower.zig:751` queries `fa_node.child_0` which is the BASE ident_expr, not the field_access. So the cache write at :475 puts it at the wrong node — the lowerer queries a different node.

Fix for field_store: ALSO write the BASE type at the field_access node. After line 475, also set `resolvedTypeTableSet(self.type_table, node_idx, base_type)` where `base_type` is the type of the field_access base (e.g., the struct type). The lowerer needs this to determine `kind` for field_store dispatch.

- [ ] **Step 3: Build + gate**

```bash
bash sf/scripts/build_release.sh
```

```bash
# Repros: all 3 must go from FAIL/ICE to OK
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f4/a repro/mi_matrix/ptrcast_slice_field_type/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f4/a/*.c 2>&1
# Expected: gcc clean (was 's' undeclared)

sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f4/b repro/mi_matrix/ptrcast_slice_field_void/main.zig
# Expected: rc=0 (was ICE 3043)

sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f4/c repro/mi_matrix/ptrcast_slice_field_xmod/main.zig
# Expected: rc=0 (was ICE 3043)
```

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
git commit -m "fix(F-4): cross-module resolved type cache (I-R1#2 + I-R5 T2)"
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

- [ ] **Step 5: Build + gate**

```bash
bash sf/scripts/build_release.sh
```

```bash
# Repro: was FAIL (undeclared zT_N), should now be OK
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f5 repro/mi_matrix/field_store_drop/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f5/*.c 2>&1
```
Expected: gcc clean.

```bash
# MD5 gate
sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/mud_server/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/game_of_life/main.zig | md5sum
```

- [ ] **Step 6: Commit**

```bash
git add sf/src/lower.zig
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

### Task F-7: Module-Global Init (I-R1#1 + I-R7 comptime, 6 repros)

**Files:** `sf/src/main.zig:587-588`, `sf/src/lower.zig:1020-1028`, `sf/src/c89_emit.zig`

**Pre-requisites:** F-4 (cross-module cache) should complete first — ptrcast_slice_field_type shares cross-module type gap.

**Scope:** Pipeline wall — `phase_LIRLowering` only handles `fn_decl`. Module-scope `var_decl`/`const` correctly parsed + type-resolved + analyzed, but never lowered. Fix: synthesize module-constructor function + emit global C declarations + wire `load_global`/`store_global` (LIR insts exist at lir.zig:73-74, C89 emission at c89_emit.zig:3012-3033, but never emitted by lowerer). This is new architecture — the largest single fix, ~100-150 lines across 3 files.

- [ ] **Step 1: Read evidence + source**

Read `.superpowers/sdd/I-R1-report.md` for full root cause analysis.
Read `sf/src/main.zig:575-594` (phase_LIRLowering module-decl loop — note empty else at :587-588).
Read `sf/src/lower.zig:1020-1029` (lowerGlobalRef — emits decl_local, should emit load_global for mutable globals).
Read `sf/src/c89_emit.zig:2041-2073` (emitModule — stdout path, no global decl emission).
Read `sf/src/c89_emit.zig:2116-2138` (emitModuleFile — per-module .c path, no global decl emission).
Read `sf/src/lir.zig:73-74` (load_global + store_global variants — already defined, C89 handlers at c89_emit.zig:3012-3033).
Read `sf/src/lower.zig:4420-4455` (lowerFn — param temp assignment, shows how function-level temps work).

- [ ] **Step 2: Synthesize module-constructor function in main.zig:587-588**

Read `sf/src/main.zig:575-588`. The empty `else {}` at :587-588 needs to:

For each `var_decl` with `child_1 != 0` (has init expression):
- Lower the init expression via `lowerExpr`
- Emit `store_global` LIR instruction with the symbol's `name_id` and init value temp

BUT — the lowerer operates on function bodies, and `store_global` needs to be emitted inside a LIR function. The approach:

1. Collect all var_decl init expressions that need lowering
2. Synthesize a new `LirFunction` called `__module_init` with:
   - `name_id = intern("__module_init")`
   - `module_id = mods[mi].id`
   - `params_count = 0`
   - `return_type = TYPE_VOID`
3. For each var_decl init, lower the init into temps and emit `store_global` into the synthesized function's entry block
4. Append the function to `ctx.lir_fns`
5. Mark it with `is_pub = 1` so the emitter includes it

The actual lowerer invocation: create a fresh `LirLowerer` for the module (same pattern as `:582-583` for fn_decl), then lower each init. However, `lowerExpr` requires a function context (hoisted_temps, blocks, etc.). The synthesized function provides this.

Simpler approach for this task: scope to the `lowerGlobalRef` fix FIRST (Step 3), then the emission pass (Step 4), then the constructor synthesis (Step 5). Each step is independently gatable.

- [ ] **Step 3: Fix lowerGlobalRef — emit load_global for mutable/non-literal globals**

Read `sf/src/lower.zig:1020-1029`. Current code always emits `decl_local`:

```zig
fn lowerGlobalRef(self: *LirLowerer, s: sym_mod.Symbol, name_id: u32) u32 {
    ...
    var tid = nextTemp(self, tid_type);
    emitInst(self, LirInst{ .decl_local = .{ .name_id = name_id, .type_id = tid_type, .temp = tid } });
    return tid;
}
```

For mutable globals (`s.flags & 1 == 1`, i.e. `var` not `const`) and for non-literal inits, switch to `load_global`:

```zig
fn lowerGlobalRef(self: *LirLowerer, s: sym_mod.Symbol, name_id: u32) u32 {
    var lgr_m: []const u8 = "LGR:n"; pal.markerWrite(lgr_m);
    var lgr_b: [20]u8 = undefined; var lgr_l = itoa_mod.itoa(name_id, lgr_b[0..]); var lgr_s: usize = @intCast(usize, 19) - @intCast(usize, lgr_l); pal.markerWrite(lgr_b[lgr_s..@intCast(usize, 19)]);
    var lgr_nl: []const u8 = " "; pal.markerWrite(lgr_nl);
    var dn_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, s.decl_node);
    var tid_type = if (dn_type) |dt| dt else type_mod.TYPE_UNDEFINED;
    var is_mutable: u8 = @intCast(u8, (@intCast(u16, s.flags) & @intCast(u16, 1)));
    if (is_mutable != @intCast(u8, 0)) {
        var tid = nextTemp(self, tid_type);
        emitInst(self, LirInst{ .load_global = .{ .name_id = name_id, .result = tid } });
        return tid;
    }
    var tid = nextTemp(self, tid_type);
    emitInst(self, LirInst{ .decl_local = .{ .name_id = name_id, .type_id = tid_type, .temp = tid } });
    return tid;
}
```

Existing `load_global` C89 handler at `c89_emit.zig:3012-3026` emits `result = zG_<hash>_<name>;` — uses `nameManglerMangle(mangler, name_id, 3, 0)` (kind 3 = global). The `store_global` counterpart at :3027-3033 emits `zG_<hash>_<name> = src;`.

- [ ] **Step 4: Emit global C declarations in emitModule/emitModuleFile**

Read `sf/src/c89_emit.zig:2116-2138` (emitModuleFile). Before the fn loop at :2122, ADD a global variable declaration pass:

```zig
// Global variable declarations
var ig: usize = @intCast(usize, 0);
while (ig < emitter.registry.types_len) : (ig += @intCast(usize, 1)) {
    var gty = emitter.registry.types_items[ig];
    if (gty.kind != type_mod.TypeKind.struct_type and gty.kind != type_mod.TypeKind.tagged_union_type and gty.kind != type_mod.TypeKind.union_type and gty.kind != type_mod.TypeKind.enum_type and gty.kind != type_mod.TypeKind.error_set_type) {
        // Check if this type is a module-scope global via symbol table
        // For now: scan for globals registered with kind=SymbolKind.global and is_mutable=1
    }
}
```

THIS APPROACH IS WRONG — global declarations need to come from symbol tables, not type registry. The correct approach: scan module's symbol table for `SymbolKind.global` with `is_mutable=1`, emit `type name;` for each (and optionally `= init_value` for literal inits). This requires access to the symbol tables which are available in `main.zig:604` (phase_C89Emission context) and can be threaded into the emitter.

**Design decision for this subagent:** The exact emission pass design is complex. The implementer should:
1. In `emitModuleFile` / `emitModule`, scan the function list for any `load_global`/`store_global` references
2. For each unique `name_id` referenced by `load_global`, find the symbol's type from the type registry (via module's symbol table or the resolved_type_table)
3. Emit `type zG_<hash>_<name>;` C declaration at the top of the .c file (before function bodies)
4. Also scan for `__module_init` function in the fn list — if present, call it in the main wrapper before the user's main

This is the most involved step. The subagent should verify gate correctness after each incremental edit.

- [ ] **Step 5: Build + gate**

```bash
bash sf/scripts/build_release.sh
```

```bash
# Repro 1: module_var_mutable — was FAIL ('x' undeclared), should now be gcc clean
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f7/a repro/mi_matrix/module_var_mutable/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f7/a/*.c 2>&1
```

```bash
# Repro 2: module_pub_var_int — was runtime gap, should print 43
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f7/b repro/mi_matrix/module_pub_var_int/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f7/b/*.c && gcc -m32 /tmp/f7/b/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f7/prog2 && /tmp/f7/prog2
```
Expected: prints `43`.

```bash
# Repro 3: module_pub_var_struct — was runtime gap, should print 7
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f7/c repro/mi_matrix/module_pub_var_struct/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f7/c/*.c && gcc -m32 /tmp/f7/c/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f7/prog3 && /tmp/f7/prog3
```
Expected: prints `7`.

```bash
# Repro 4: module_const_fn_call — was runtime gap, should print 42
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f7/d repro/mi_matrix/module_const_fn_call/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f7/d/*.c && gcc -m32 /tmp/f7/d/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f7/prog4 && /tmp/f7/prog4
```
Expected: prints `42`.

```bash
# Repro 5: comptime_neg_int — was runtime gap, should print -5
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f7/e repro/mi_matrix/comptime_neg_int/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f7/e/*.c && gcc -m32 /tmp/f7/e/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/f7/prog5 && /tmp/f7/prog5
```
Expected: prints `-5`.

```bash
# Repro 6: var_declared_void — was FAIL, may still fail if sema doesn't reject void vars
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/f7/f repro/mi_matrix/var_declared_void/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/f7/f/*.c 2>&1
```
Expected: may stay FAIL (gcc error on void var) — the deeper fix is sema rejecting void vars, out of scope.

```bash
# MD5 gate
sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/mud_server/main.zig | md5sum
sf/build/out_release/zig1 --dump-c89 examples/z98/game_of_life/main.zig | md5sum
```

```bash
# Corpus sweep — must not regress from 165/15/6/0
# Full classifier per QUICK_REF.md recipe
```

- [ ] **Step 6: Commit**

```bash
git add sf/src/main.zig sf/src/lower.zig sf/src/c89_emit.zig
git commit -m "fix(F-7): module-global init — constructor synthesis + global emission (I-R1#1 + I-R7 comptime)"
```

---

## Execution Order

```
F-1 → F-2 → F-3 → F-4 → F-5 → F-6 → F-7
```

All are independent (no functional dependency). F-7 is recommended last as the most complex (requires subagent design decisions).
