# F-PTRBUILTIN Implementation Plan — `@intFromPtr` / `@ptrFromInt` / `@fieldParentPtr` pointer builtins

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make zig1 recognize and lower the three modern pointer builtins `@intFromPtr(p)`, `@ptrFromInt(a)`, and `@fieldParentPtr(T, "field", ptr)` so the two committed R2 RED fixtures (`builtin_ptr_roundtrip_xmod`, `builtin_fieldparentptr_xmod`) go GREEN with byte-exact stdout.

**Architecture:** pure front-end additions to exactly two files — `sf/src/semantic_analyzer.zig` (name dispatch) and `sf/src/lower.zig` (LIR emission) — reusing EXISTING Lir ops (`.ptr_to_int`, `.int_const`, `.binary` BIN_SUB, `.int_to_ptr`) and the EXISTING field-by-name byte-offset table (`FieldEntry.offset`, consumed by the F-INTRO `@offsetOf` fold). `comptime_eval.zig` is UNCHANGED (pointers never comptime-fold). `@intFromPtr` is a pure alias of `@ptrToInt` (extend its branch condition in both files); `@ptrFromInt` requires the operator-ruled R2 fixture amend to the annotated form `var q: *i32 = @ptrFromInt(a);` and reads the expected-type stack; `@fieldParentPtr` resolves its type arg + field string at lower time and emits a 4-inst runtime adjust chain.

**Tech Stack:** Z98 dialect in `sf/src/*.zig` (self-hosted compiler source); verified against the rebuilt zig0-bootstrap reference; battery via the established corpus/gate scripts.

## Global Constraints

- This plan is **F-PTRBUILTIN** = item 2 of the operator-approved follow-on execution order in `docs/superpowers/plans/2026-09-03-language-wins-r-i-plan.md` (AMENDMENT, G1 rulings). Only the three builtins above plus the R2 fixture amend; **no other F work, no other compiler changes.**
- Z98 dialect discipline: `@intCast` on every narrowing/widening; no `anytype`/`@Type`; `switch` must have `else`; no method syntax; no pointer captures. Follow the surrounding file style exactly.
- Source edits via `fastedit` ONLY per `docs/sf/AGENTS.md` X.7 (re-read the region immediately before every edit; absolute line numbers; edit bottom-to-top; an INSERT = replace the anchor line keeping the original at the end of `new_code` since `end_line = start_line - 1` errors). No python/sed/bulk transforms. No `git checkout` to erase.
- Files that MAY change in this plan: `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, and the single fixture `repro/mi_matrix/builtin_ptr_roundtrip_xmod/main.zig` (operator-ruled amend). NO other `sf/src` file; `comptime_eval.zig` MUST stay byte-identical. Never touch `sf/build/out_release/`.
- Reference rebuild: `timeout 900 bash sf/scripts/build_release.sh` → output `/tmp/fx_subfolder/zig1`. **CRITICAL:** this rebuild wipes `/tmp/fx_subfolder/lib` — after any rebuild re-install the canonical std lib (cp `sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig}` into `/tmp/fx_subfolder/lib/`) or every std-importing program fails `error[3048]` and the sweep misclassifies.
- GREEN contracts (byte-exact stdout, run-gate `RUNRC=0`): `builtin_ptr_roundtrip_xmod` → `42`; `builtin_fieldparentptr_xmod` → `1`.
- The 4-MD5 gate programs use none of the new builtins ⇒ their dump md5 MUST stay byte-identical: gol `302df36b…`, lisp `3591bad9…`, json `76056b97…`, mud `53405b3b…`. Any move is a bug → STOP-present.
- `@fieldParentPtr` supports plain `struct_type` containers only (matches the fixture `Outer{tag,inner}`). Non-struct type arg / missing field → dedicated branch returns a `TYPE_VOID` temp (never the generic cast tail, never silent wrong-value emission; clean user diagnostics are F-CLEANDIAG scope).
- `@ptrFromInt` is implemented for the ANNOTATED form only (pointer expected type on the stack). Un-annotated `var q = @ptrFromInt(a)` → clean `error[3000]` "cannot infer pointer type" at sema (this is REQUIRED so the compiler never silently mis-emits; valid code never hits it).
- No comptime changes: none of the three may be interned in `comptime_eval.zig`; lower branches sit BEFORE the fold-map read / `iceUnresolvedComptime` guard so they never fall to the generic cast tail.
- Self-compile round-trip fixed point WILL move (compiler source grows) ⇒ NEW fixed-point md5 recorded, re-baseline is operator-ruled in Task 2's STOP-present, never silent.
- Full battery on any F commit: golden 9/9, matrix 21/21, corpus sweep (424 dirs `-s0`), self-compile round-trip. Expected corpus delta: the 2 R2 builtin dirs flip GCCFAIL→OK/run-GREEN; all other 422 dirs unchanged (0 asymmetric vs the pre-edit reference).
- Authoritative per-fixture classifier = Step-4 recipe in `.superpowers/sdd/task-LANGWINS-report.md` (`classify1.sh` compile-gate + `fixture_run.sh` run-gate; fresh output dir `rm -rf`+`mkdir -p` REQUIRED, else dump ICEs rc=3 spill-open). Pre-existing dirty/untracked repo files are NEVER staged or committed.
- Commit messages follow repo style (lowercase `feat:`/`test:`/`docs:` prefix + concise body).
- Operator standing rules: only plan-authorized actions; STOP-and-present on any issue or any plan-vs-evidence divergence; store memories as we go (mnemoria agent `fptrbuiltin-session`); NO context compression during this build session.

---

## Background (verified anchors — read before editing; line numbers at HEAD `6751a8d0`)

Green path for `@ptrToInt`/`@intToPtr` (the working template) and the field-offset infra (from F-INTRO):

1. Lexer/parser: every `@name` is one generic `builtin_identifier` token → `parserParseBuiltinCall` (parser.zig:691-739) is fully generic; type-leading args parse as types, everything else as an expression, into the same child-buf → `AstKind.builtin_call` with `child_0` = name id and `ec` = arg node indices. The R2 calls (`@intFromPtr(p)`, `@ptrFromInt(a)`, `@fieldParentPtr(Outer, "inner", &o.inner)`) all parse today.
2. Semantic dispatch `semantic_analyzer.zig:1499+`; `@ptrToInt` dedicated branch at **:1519-1521** (`resolve ec[0]`, result `TYPE_USIZE`). Name ids: struct fields :54-56, interned :92-96, assigned :193-195. Expected-type stack: `pushExpectedType` :1821, `popExpectedType` :1837, `topExpectedType` :1843 (returns 0 when empty). For a var-decl init, `semanticAnalyzerResolveExpr` is called between `pushExpectedType(vd_exp)` / `popExpectedType` at **:1981-1984**; `vd_exp = decl_type` for annotated decls, `0` for unannotated. The per-node result type is stored to the resolved-type table at the tail of `semanticAnalyzerResolveExpr` (**:1762-1763** `rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, result)`).
3. Lower `lower.zig` builtin dispatch: `@ptrToInt` dedicated branch at **:3252-3261** (emit `.ptr_to_int`, result `TYPE_USIZE`); the comptime fold-map read starts at **:3262** (`u32ToU64MapGet`); `@sizeOf`/`@alignOf`/`@offsetOf`/`@bitSizeOf`/`@bitOffsetOf` ICE guard at **:3289-3292**; the generic 2-arg type-value-cast tail starts at **:3494** (`if (ec.len >= 2)`), where `@intToPtr` emits `.int_to_ptr` at :3549-3552 and `@intCast` etc. sit nearby. Name ids: struct fields :372-379, interned :436-452, assigned :526-528. Resolved-type reads use `resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx)` (import alias at :18).
4. Lir ops (lir.zig): `.ptr_to_int{value,result}` :65, `.int_to_ptr{value,target,result}` :66, `.int_const{value,result}` (fold precedent lower.zig:3283-3284), `.binary{op,lhs,rhs,result}` :35 with `BIN_SUB` op const at lower.zig:39. Emission precedents: `c89_emit.zig:6902-6913` (`dst = (usize)src;`), :6887-6900 (`dst = (*T*)(unsigned int)src;`), plain `a - b` sub at lower.zig:1852.
5. Field-by-name byte offset (F-INTRO infra, unchanged): `FieldEntry{name_id,type_id,offset}` (type_registry.zig:86), populated state-2 by `typeResolverResolveLayout` (type_resolver.zig:139-156); slice accessor `typeRegistryGetStructFields` (type_registry.zig:806); string-literal payload read = `store.string_values.items[astStoreNodePayload(store, node_idx)]` (precedent lower.zig:1670-1675). Pointer type manufacture: `typeRegistryGetOrCreatePtr(registry, base, is_const)` (type_registry.zig:352).
6. The two R2 fixtures (committed, currently RED GCCFAIL on the F-INTRO compiler): `repro/mi_matrix/builtin_ptr_roundtrip_xmod/main.zig` and `builtin_fieldparentptr_xmod/main.zig` (sources listed in Task 1 below).

---

### Task 1: Amend ptr_roundtrip fixture + implement the three pointer builtins

**Files:**
- Modify: `repro/mi_matrix/builtin_ptr_roundtrip_xmod/main.zig` (one line: `var q = @ptrFromInt(a);` → `var q: *i32 = @ptrFromInt(a);`)
- Modify: `sf/src/semantic_analyzer.zig` (struct ~:54-63; init interns ~:92-96; struct-literal assign ~:193-195; dispatch branches ~:1519-1521 + new branches after it)
- Modify: `sf/src/lower.zig` (struct :372-379; init interns :436-452; struct-literal assign :526-528; branch region :3252-3261 + new branches after it)

**Interfaces:**
- Consumes: `FieldEntry.offset`/`typeRegistryGetStructFields`, `typeRegistryGetOrCreatePtr`, expected-type stack, existing Lir ops; the two R2 fixtures.
- Produces: `@intFromPtr`/`@ptrFromInt`(annotated)/`@fieldParentPtr` recognized + lowered; R2 fixtures GREEN (`42`, `1`); 4-MD5 gates byte-identical; comptime_eval.zig untouched.

- [ ] **Step 1: Confirm the pre-edit RED + snapshot gates**

Against the current reference (repo-root CWD; if `/tmp/fx_subfolder/lib` is missing, re-install the std lib first per Global Constraints):
```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/builtin_ptr_roundtrip_xmod/main.zig /tmp/fptr_red_a
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/builtin_fieldparentptr_xmod/main.zig /tmp/fptr_red_b
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum; done
```
Expected: ptr_roundtrip + fieldparentptr run-gates each fail to compile (`DUMPFAIL`/`GCCFAIL` — the R2 silent-dump→invalid-C class) → RED confirmed; the four md5s equal gol `302df36b…`/lisp `3591bad9…`/json `76056b97…`/mud `53405b3b…`. If any fixture is already GREEN or any gate hash moved, STOP-present.

- [ ] **Step 2: Amend the ptr_roundtrip fixture (operator-ruled) + commit `test:`**

In `repro/mi_matrix/builtin_ptr_roundtrip_xmod/main.zig`, change line 9 (the only `@ptrFromInt` use):
```zig
    var q = @ptrFromInt(a);
```
to:
```zig
    var q: *i32 = @ptrFromInt(a);
```
Re-run the ptr_roundtrip fixture against the pre-fix reference; it must STILL be RED (GCCFAIL/DUMPFAIL — @intFromPtr/@ptrFromInt are still unrecognized). If the amended fixture suddenly classifies OK/GREEN on the pre-fix compiler, STOP-present (the amend would not be a faithful RED). Commit ONLY this fixture file:
```bash
git add repro/mi_matrix/builtin_ptr_roundtrip_xmod/main.zig
git commit -m "test: annotate @ptrFromInt target var in ptr_roundtrip fixture (F-PTRBUILTIN)"
```

- [ ] **Step 3: Edit `sf/src/semantic_analyzer.zig`**

(3a) Add three name-id fields to the struct after `.inttoptr_name_id: u32,` (:56):
```
    int_from_ptr_name_id: u32,
    ptr_from_int_name_id: u32,
    field_parent_ptr_name_id: u32,
```

(3b) Intern the three names after the `@intToPtr` intern (`itp_id`, ~:95-96) and assign in the struct literal after `.inttoptr_name_id = itp_id,` (:195):
```
    var ifp_s: []const u8 = "@intFromPtr";
    var ifp_id = interner_mod.stringInternerIntern(interner, ifp_s);
    var pfi_s: []const u8 = "@ptrFromInt";
    var pfi_id = interner_mod.stringInternerIntern(interner, pfi_s);
    var fpp_s: []const u8 = "@fieldParentPtr";
    var fpp_id = interner_mod.stringInternerIntern(interner, fpp_s);
```
```
        .int_from_ptr_name_id = ifp_id,
        .ptr_from_int_name_id = pfi_id,
        .field_parent_ptr_name_id = fpp_id,
```

(3c) Extend the `@ptrToInt` dispatch branch condition at **:1519** to also match `@intFromPtr` (pure alias, same body):
```zig
        } else if (node.child_0 == self.ptrtoint_name_id or node.child_0 == self.int_from_ptr_name_id) {
```

(3d) Add two NEW branches immediately AFTER the (now extended) ptrtoint branch (after its closing `}` ~:1521), before the `@getChar` branch:
```zig
        } else if (node.child_0 == self.ptr_from_int_name_id) {
            var pfi_res: u32 = type_mod.TYPE_VOID;
            if (ec.len >= @intCast(usize, 1)) {
                _ = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 0)]);
                var pfi_top = topExpectedType(self);
                if (pfi_top != @intCast(u32, 0) and pfi_top != type_mod.TYPE_UNDEFINED) {
                    var pfi_ty = self.registry.types_items[@intCast(usize, pfi_top)];
                    if (pfi_ty.kind == type_mod.TypeKind.ptr_type or pfi_ty.kind == type_mod.TypeKind.many_ptr_type) {
                        pfi_res = pfi_top;
                    }
                }
            }
            if (pfi_res == type_mod.TYPE_VOID) {
                var pfi_msg: []const u8 = "cannot infer pointer type for @ptrFromInt; annotate the target variable type";
                _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3000_TYPE_MISMATCH)), self.source_file_id, node.span_start, node.span_start + @intCast(u32, node.span_len), pfi_msg);
            }
            result = pfi_res;
        } else if (node.child_0 == self.field_parent_ptr_name_id) {
            var fpp_res: u32 = type_mod.TYPE_VOID;
            if (ec.len >= @intCast(usize, 3)) {
                var fpp_env = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbols, .interner = self.interner, .module_id = self.module_id };
                var fpp_outer = type_resolver.resolveTypeExprFull(&fpp_env, ec[@intCast(usize, 0)], @intCast(u32, 0));
                if (fpp_outer != type_mod.TYPE_UNDEFINED) {
                    _ = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 2)]);
                    fpp_res = type_mod.typeRegistryGetOrCreatePtr(self.registry, fpp_outer, false);
                }
            }
            result = fpp_res;
        }
```
Notes: `node` is in scope in this dispatch (`astStoreNodeAt` result); verify the surrounding branch uses the same `result = ...` pattern. The string-literal arg `ec[1]` needs no semantic resolution. If `node` is not the variable name in scope at :1519, match the local used by the ptrtoint branch's sibling code.

- [ ] **Step 4: Edit `sf/src/lower.zig`**

(4a) Add three name-id fields after `.inttoptr_name_id: u32,` (:374):
```
    int_from_ptr_name_id: u32,
    ptr_from_int_name_id: u32,
    field_parent_ptr_name_id: u32,
```

(4b) Intern after the `@intToPtr` intern (`itp_id`, ~:440-441) and assign after `.inttoptr_name_id = itp_id,` (:528):
```
    var ifp_s: []const u8 = "@intFromPtr";
    var ifp_id = si_mod.stringInternerIntern(ctx.registry.interner, ifp_s);
    var pfi_s: []const u8 = "@ptrFromInt";
    var pfi_id = si_mod.stringInternerIntern(ctx.registry.interner, pfi_s);
    var fpp_s: []const u8 = "@fieldParentPtr";
    var fpp_id = si_mod.stringInternerIntern(ctx.registry.interner, fpp_s);
```
```
         .int_from_ptr_name_id = ifp_id,
         .ptr_from_int_name_id = pfi_id,
         .field_parent_ptr_name_id = fpp_id,
```

(4c) Extend the `@ptrToInt` lower-branch condition at **:3252** to also match `@intFromPtr` (same body):
```zig
            if (node.child_0 == self.ptrtoint_name_id or node.child_0 == self.int_from_ptr_name_id) {
```

(4d) Add two NEW branches immediately AFTER the ptrtoint branch's closing `}` (~:3261) and BEFORE the fold-map read at :3262 (never let them reach the generic tail):
```zig
            if (node.child_0 == self.ptr_from_int_name_id) {
                var pfi_t: u32 = type_mod.TYPE_USIZE;
                var pfi_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
                if (pfi_rt) |prt| {
                    var pfi_ty = self.ctx.registry.types_items[@intCast(usize, prt)];
                    if (pfi_ty.kind == type_mod.TypeKind.ptr_type or pfi_ty.kind == type_mod.TypeKind.many_ptr_type) {
                        pfi_t = prt;
                    }
                }
                if (ec.len >= @intCast(usize, 1)) {
                    var pfi_arg = lowerExpr(self, ec[@intCast(usize, 0)]);
                    var pfi_res = nextTemp(self, pfi_t);
                    emitInst(self, LirInst{ .int_to_ptr = .{ .value = pfi_arg, .target = pfi_t, .result = pfi_res } });
                    return pfi_res;
                }
                return nextTemp(self, pfi_t);
            }
            if (node.child_0 == self.field_parent_ptr_name_id) {
                if (ec.len >= @intCast(usize, 3)) {
                    var fpp_env = type_resolver.TypeResolveEnv{ .store = self.ctx.store, .typereg = self.ctx.registry, .symbol_reg = self.ctx.symbol_tables, .interner = self.ctx.registry.interner, .module_id = self.module_id };
                    var fpp_outer = type_resolver.resolveTypeExprFull(&fpp_env, ec[@intCast(usize, 0)], @intCast(u32, 0));
                    if (fpp_outer != type_mod.TYPE_UNDEFINED) {
                        var fpp_oty = self.ctx.registry.types_items[@intCast(usize, fpp_outer)];
                        if (fpp_oty.state == @intCast(u8, 2) and fpp_oty.kind == type_mod.TypeKind.struct_type) {
                            var fpp_fields: []type_mod.FieldEntry = undefined;
                            type_mod.typeRegistryGetStructFields(self.ctx.registry, fpp_outer, &fpp_fields);
                            var fpp_fnode = ast_mod.astStoreNodeAt(self.ctx.store, ec[@intCast(usize, 1)]);
                            if (fpp_fnode.kind == AstKind.string_literal) {
                                var fpp_sv = ast_mod.astStoreNodePayload(self.ctx.store, ec[@intCast(usize, 1)]);
                                var fpp_want = self.ctx.store.string_values.items[@intCast(usize, fpp_sv)];
                                var fpp_i: usize = 0;
                                while (fpp_i < fpp_fields.len) : (fpp_i += 1) {
                                    if (fpp_fields[fpp_i].name_id == fpp_want) {
                                        var fpp_off: u64 = @intCast(u64, fpp_fields[fpp_i].offset);
                                        var fpp_base = lowerExpr(self, ec[@intCast(usize, 2)]);
                                        var fpp_t1 = nextTemp(self, type_mod.TYPE_USIZE);
                                        emitInst(self, LirInst{ .ptr_to_int = .{ .value = fpp_base, .result = fpp_t1 } });
                                        var fpp_t2 = nextTemp(self, type_mod.TYPE_USIZE);
                                        emitInst(self, LirInst{ .int_const = .{ .value = fpp_off, .result = fpp_t2 } });
                                        var fpp_t3 = nextTemp(self, type_mod.TYPE_USIZE);
                                        emitInst(self, LirInst{ .binary = .{ .op = BIN_SUB, .lhs = fpp_t1, .rhs = fpp_t2, .result = fpp_t3 } });
                                        var fpp_ptr = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, fpp_outer, false);
                                        var fpp_res = nextTemp(self, fpp_ptr);
                                        emitInst(self, LirInst{ .int_to_ptr = .{ .value = fpp_t3, .target = fpp_ptr, .result = fpp_res } });
                                        return fpp_res;
                                    }
                                }
                            }
                        }
                    }
                }
                return nextTemp(self, type_mod.TYPE_VOID);
            }
```
Notes: match the exact variable names already in scope in the builtin dispatch (`store` local at :3251, `node`, `node_idx`, `ec`, `type_mod`, `AstKind`, `ast_mod`, `resolved_mod`, `type_resolver` — all confirmed in that region). `BIN_SUB` is the module-level const at lower.zig:39. If the surrounding code names the store local differently than `store` (check ~:3239), align the `ast_mod.astStoreNodeAt`/`astStoreNodePayload`/`string_values` calls accordingly.

- [ ] **Step 5: Rebuild the reference compiler**

```bash
timeout 900 bash sf/scripts/build_release.sh
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```
Expected: release-Done, NEW `/tmp/fx_subfolder/zig1` md5 (≠ `ecdec6f4…`), std lib re-installed. Record the md5.

- [ ] **Step 6: Verify the two fixtures flip RED→GREEN**

```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/builtin_ptr_roundtrip_xmod/main.zig /tmp/fptr_g_a
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/builtin_fieldparentptr_xmod/main.zig /tmp/fptr_g_b
```
Expected: each `RUNRC=0`; stdout byte-exact `42` / `1`; gcc clean. Confirm the emitted `main_*.c` shows the expected shapes — ptr_roundtrip: `zT_.. = (usize)p;` / `q = (*i32*)(unsigned int)a;` (`.int_to_ptr`); fieldparentptr: the 4-inst chain `ptr_to_int` → sub by the `inner` offset (4) → `int_to_ptr` to `*Outer`, and the `==` prints `1`. If not GREEN with exact contracts, STOP-present.

- [ ] **Step 7: 4-MD5 gates byte-identical (repo-root CWD)**

```bash
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum; done
```
Expected: gol `302df36b…` / lisp `3591bad9…` / json `76056b97…` / mud `53405b3b…` — all four byte-identical. ANY move = a bug → STOP-present (do not re-baseline).

- [ ] **Step 8: comptime_eval.zig byte-identical check**

```bash
git diff --stat sf/src/comptime_eval.zig
```
Expected: NO output (untouched). If it changed, STOP-present.

- [ ] **Step 9: Self-compile round-trip (fixed point check)**

```bash
bash scripts/self_compile/build_next_gen.sh /tmp/fx_subfolder/zig1 /tmp/fptr_self
```
Expected: dump rc=0, 42 `.c`, 0 `error[`, 0 PANIC, hop binaries md5-identical to each other AND to the new reference (fixed point closed). Record the NEW fixed-point md5. If the fixed point does NOT close (hop1 ≠ reference or hop2 ≠ hop1), STOP-present.

- [ ] **Step 10: Commit + report**

```bash
git add sf/src/semantic_analyzer.zig sf/src/lower.zig
git commit -m "feat: pointer builtins @intFromPtr/@ptrFromInt/@fieldParentPtr (F-PTRBUILTIN)"
```
Stage ONLY the two source files (the fixture `test:` commit already landed in Step 2). Pre-existing dirty/untracked files stay unstaged. Append the full report to `.superpowers/sdd/task-F-PTRBUILTIN-report.md` (`## F-PTRBUILTIN-1`): RED proof, exact edits (per-file hunk list incl. the fixture amend commit), fixture GREEN evidence (stdout bytes + emitted-C shape), 4-MD5 table, new reference md5, fixed-point md5, both commit shas, git-status-at-end. Ledger line in `.superpowers/sdd/progress.md`.

Report back: `DONE` + commit shas + one-line battery summary + any concern.

---

### Task 2: Full battery + corpus reconciliation + STOP-present re-baseline proposal

**Files:**
- Create report: `.superpowers/sdd/task-F-PTRBUILTIN-report.md` (`## F-PTRBUILTIN-2` appended; gitignored scratch)

**Interfaces:**
- Consumes: the Task-1 compiler `/tmp/fx_subfolder/zig1` (new md5), the two GREEN fixtures, `.superpowers/sdd/task-LANGWINS-report.md` G1 corpus numbers.
- Produces: full-battery evidence, corpus reconciliation table, STOP-present with a re-baseline proposal for the NEW self-compile fixed-point md5 (operator-ruled). NO commits in this task.

- [ ] **Step 1: Golden 9/9**

Run the 9 golden fixtures (emission_assoc_chain_xmod, fn_ptr_struct_field, emission_lower_crash_xmod, tco_return_try, tco_defer, tco_factorial, quicksort, func_ptr_return, hello) emit→gcc→link→run with the new compiler; stdout byte-identical to the pre-change golden. Record rc + stdout state.

- [ ] **Step 2: Matrix 21/21**

Run the 21 `examples/z98` programs emit→gcc→link→run; all rc=0; mud_server + rogue_mud timeout-gated rc=124 with correct output = PASS; runtime stdout byte-equal vs pre-change reference.

- [ ] **Step 3: Corpus sweep (424 dirs, `-s0`) + asymmetric reconciliation**

Generate the 424-dir list (R-phase enumeration in task-LANGWINS-report.md G1). Sweep BOTH the pre-edit reference and the new compiler with the same list + `sweep.sh`. Expected: exactly the 2 R2 dirs change (GCCFAIL → OK; run-gate prints `42`/`1`) → `OK=400→402 / GCCFAIL=2→0`; per-dir asymmetric = exactly those 2 dirs, 0 NEW FAIL/ICE/CRASH anywhere. Any other delta → STOP-present.

- [ ] **Step 4: Self-compile confirmation + fixed-point record**

Re-summarize the Task-1 round-trip; record the NEW fixed-point md5; state plainly it MOVED from `d9b3e041…` because compiler source grew (expected).

- [ ] **Step 5: STOP-present re-baseline proposal**

Append `## F-PTRBUILTIN-2` with full evidence. STOP-present: re-baseline self-compile fixed point `(previous) → (new)` (operator-ruled); 4-MD5 gates unchanged → NO gate re-baseline; the 2 R2 fixtures are GREEN and their EXPECTED_FAIL.md rows need a RESOLVED docs update in Task 3 AFTER operator approval. Report back: `DONE` + summary + concerns. NO commit.

---

### Task 3: Docs GATE — EXPECTED_FAIL.md resolution + QUICK_REF baseline (operator-approved)

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`
- Modify: `docs/sf/QUICK_REF.md`

**Interfaces:**
- Consumes: operator approval of the Task-2 re-baseline proposal; the Task-2 evidence.
- Produces: committed docs reconciliation. THIS TASK RUNS ONLY AFTER THE OPERATOR APPROVES.

- [ ] **Step 1: EXPECTED_FAIL.md — mark the two R2 rows RESOLVED**

Header version bump (v64 → v65, file convention). For each Langwins section carrying `builtin_ptr_roundtrip_xmod` / `builtin_fieldparentptr_xmod`: mark RESOLVED with the F-PTRBUILTIN fix commits (the `test:` fixture-amend sha + the `feat:` sha) + GREEN contracts (`42` / `1`, run-gate verified). Preserve the historical RED text beneath (file convention). Touch no other section.

- [ ] **Step 2: QUICK_REF.md — new newest-first baseline bullet**

Insert a dense dated bullet ABOVE the current newest (the `Post-F-INTRO baseline`) recording: F-PTRBUILTIN commit shas, three pointer builtins (`@intFromPtr` alias of `@ptrToInt`; `@ptrFromInt` annotated-form via expected-type stack; `@fieldParentPtr` struct byte-offset chain), R2 fixtures GREEN (`42`/`1`), 4-MD5 gates byte-identical (unchanged hashes), golden 9/9, matrix 21/21, corpus post counts (2-dir delta only, 0 asymmetric), NEW reference md5 + NEW self-compile fixed-point md5 (operator-ruled re-baseline).

- [ ] **Step 3: Commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs: GATE — pointer builtins GREEN + fixed-point re-baseline (F-PTRBUILTIN)"
```
Only the two doc files staged. Report back: `DONE` + commit sha.

---

## Plan Self-Review (performed at authoring time)

1. **Spec coverage:** A5 `@intFromPtr`/`@ptrFromInt` + A6 `@fieldParentPtr` (design spec semantics §1, I2 verdicts) → Task 1 implements exactly these (alias branch-extension + expected-type annotated form + struct-offset chain); the operator-ruled fixture amend is an explicit Task-1 step; Task 2 = regression discipline; Task 3 = EXPECTED_FAIL/QUICK_REF reconciliation. Fixture GREEN contracts match the committed R2 headers exactly (`42`, `1`). No comptime change anywhere (matches I2 Step-4: comptime_eval UNCHANGED).
2. **Placeholder scan:** no TBD/TODO; every step carries exact file paths, edit content, and commands; the insertion blocks are complete code.
3. **Type/name consistency:** the three new name-id fields are named identically across the two files (`int_from_ptr_name_id`/`ptr_from_int_name_id`/`field_parent_ptr_name_id`), matching each file's existing `ptrtoint_name_id`/`inttoptr_name_id` convention. Intern strings match the fixture call sites (`@intFromPtr`, `@ptrFromInt`, `@fieldParentPtr`). Fixture field name `"inner"` matches `FieldEntry.name_id` after interning; `Outer` byte offset of `inner` = 4 (tag u8@0, Inner align-4) → sub-4 chain recovers `&o`.

## Execution Handoff

Plan complete. **Subagent-Driven (recommended per operator):** fresh implementer subagent per task + task reviewer (spec compliance + quality) after each; Task 2 and Task 3 proceed only after the prior review approves and, for Task 3, after the operator approves the Task-2 re-baseline proposal.
