# F-BITCAST Implementation Plan — `@bitCast(Dest, src)` same-size reinterpretation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make zig1 recognize and lower `@bitCast(Dest, src)` (same-size integer reinterpretation) so the committed R3 RED fixture `repro/mi_matrix/builtin_bitcast_xmod/main.zig` goes GREEN with byte-exact stdout `-1`.

**Architecture:** pure front-end additions to exactly two files — `sf/src/semantic_analyzer.zig` (dedicated dispatch branch that resolves the dest type + source expression and enforces the same-size integer gate with a clean `error[3000]`) and `sf/src/lower.zig` (dedicated branch emitting the EXISTING unchecked `.int_cast` Lir — the exact arm the `@as` type-value-cast already uses). The R3 fixture needs NO amend (it is verbatim from the R phase and already in the annotated-typed `var u: u32` form the gate requires). `comptime_eval.zig` is UNCHANGED (`@bitCast` is never comptime-folded). Emission reuses the unchecked int-cast (a C value cast, bit-identical on the sole gcc backend); no LIR/emitter/serde change.

**Tech Stack:** Z98 dialect in `sf/src/*.zig` (self-hosted compiler source); verified against the rebuilt zig0-bootstrap reference; battery via the established corpus/gate scripts.

## Global Constraints

- This plan is **F-BITCAST** = item 3 of the operator-approved follow-on execution order in `docs/superpowers/plans/2026-09-03-language-wins-r-i-plan.md` (AMENDMENT, G1 rulings). ONLY `@bitCast` support; **no other F work, no other compiler changes.**
- Z98 dialect discipline: `@intCast` on every narrowing/widening; no `anytype`/`@Type`; `switch` must have `else`; no method syntax; no pointer captures. Follow the surrounding file style exactly.
- Source edits via `fastedit` ONLY per `docs/sf/AGENTS.md` X.7 (re-read the region immediately before every edit; absolute line numbers; edit bottom-to-top; an INSERT = replace the anchor line keeping the original at the end of `new_code` since `end_line = start_line - 1` errors). No python/sed/bulk transforms. No `git checkout` to erase.
- Files that MAY change in this plan: `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`. NO other `sf/src` file; `comptime_eval.zig` MUST stay byte-identical. Never touch `sf/build/out_release/`. The R3 fixture is committed verbatim and is NOT amended.
- Reference rebuild: `timeout 900 bash sf/scripts/build_release.sh` → output `/tmp/fx_subfolder/zig1`. **CRITICAL:** this rebuild wipes `/tmp/fx_subfolder/lib` — after any rebuild re-install the canonical std lib (cp `sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig}` into `/tmp/fx_subfolder/lib/`) or every std-importing program fails `error[3048]` and the sweep misclassifies.
- GREEN contract (byte-exact stdout, run-gate `RUNRC=0`): `builtin_bitcast_xmod` → `-1`.
- The 4-MD5 gate programs use none of the new builtin ⇒ their dump md5 MUST stay byte-identical: gol `302df36b…`, lisp `3591bad9…`, json `76056b97…`, mud `53405b3b…`. Any move is a bug → STOP-present.
- `@bitCast` gate (I3 verdict, locked): BOTH `Dest` and `src` must be integer-family per `typeRegistryIsInteger` (type_registry.zig:728 — signed/unsigned ints + isize/usize; bool and float are EXCLUDED) AND both must be state==2 materialized types of EQUAL registry `.size`. Any violation → clean `error[3000]` "`@bitCast` requires same-size integer source and destination types" at sema (this is REQUIRED so the compiler never silently truncates — the `@as(u8, u32 0xFFFFFFFF)`→255 and `@as(u32, f32 1.5)`→1 probe results are exactly the silent-wrong class this gate prevents). A comptime-int literal `src` (TYPE_INT_LIT, not state==2) hits the same clean error; valid programs use typed vars.
- Emission = the UNCHECKED int cast (same `LirInst.int_cast{ .is_checked = 0 }` arm the `@as` type-value-cast already emits at lower.zig:3623-3627); never the checked `@intCast` path (lower.zig:3588-3605) which panics rc=134 on `0xFFFFFFFF → i32`.
- No comptime changes: `@bitCast` is NOT interned in `comptime_eval.zig`; the lower branch sits BEFORE the fold-map read (`u32ToU64MapGet` at lower.zig:3327) so it never reaches the generic cast tail or `iceUnresolvedComptime`.
- Self-compile round-trip fixed point WILL move (compiler source grows) ⇒ NEW fixed-point md5 recorded; re-baseline is operator-ruled in Task 2's STOP-present, never silent.
- Full battery on the F commit: golden 9/9, matrix 21/21, corpus sweep (424 dirs `-s0`), self-compile round-trip. **Corpus-delta expectation is special for @bitCast:** the R3 fixture classifies `OK` even on the pre-fix compiler (its RED class is compile-OK runtime-wrong — the sweep is compile-only). Therefore the sweep per-dir asymmetric count is expected to be **0**, and the ONLY behavioral flip is the run-gate of `builtin_bitcast_xmod` (stdout `0` → `-1`). A 0-asymmetric sweep is the SUCCESS signal here, not a no-op — verify the run-gate flip explicitly.
- Authoritative per-fixture classifier = Step-4 recipe in `.superpowers/sdd/task-LANGWINS-report.md` (`classify1.sh` compile-gate + `fixture_run.sh` run-gate; fresh output dir `rm -rf`+`mkdir -p` REQUIRED, else dump ICEs rc=3 spill-open). Pre-existing dirty/untracked repo files are NEVER staged or committed.
- Commit messages follow repo style (lowercase `feat:`/`test:`/`docs:` prefix + concise body).
- **Operator-authorized D1 dialect (AMENDMENT 1, 2026-09-03):** this plan's edit blocks may contain cross-module comptime-const local-init decls of the form `var x: u32 = type_mod.TYPE_VOID;` (or `type_mod.TYPE_USIZE`/any `type_mod.TYPE_*`). zig0 DROPS such decls during self-compile → `'x' undeclared` gcc error. THIS SPECIFIC situation (a dropped cross-module comptime-const local-init decl) is operator-authorized to be fixed WITHOUT a fresh ruling, by wrapping the initializer in the probe-proven form `var x: u32 = @intCast(u32, type_mod.TYPE_VOID);`. The authorization covers F-BITCAST and ALL subsequent F plans that encounter the same issue; any task step that applies this wrap proceeds without STOP-present. If a drop/undeclared situation does NOT match this exact class (e.g. a different decl or a genuinely wrong value), STOP-present as usual.
- Operator standing rules: only plan-authorized actions; STOP-and-present on any issue or any plan-vs-evidence divergence; store memories as we go (mnemoria agent `fbitcast-session`); NO context compression during this build session.

---

## Background (verified anchors — read before editing; line numbers at HEAD `8e80ed6b`)

The `@as` type-value-cast is the working template; `@bitCast` differs only by requiring equal-size int types instead of arbitrary int casts:

1. Lexer/parser: every `@name` is one generic `builtin_identifier` token → `parserParseBuiltinCall` is fully generic; `@bitCast(i32, u)` parses today into `AstKind.builtin_call` with `child_0` = the `@bitCast` name id and `ec[0]` = the `i32` type node, `ec[1]` = the `u` expression node (R3 fixture compiles silently today — the RED evidence is that the result is dropped → prints `0`).
2. Semantic dispatch `semantic_analyzer.zig`: name-id struct fields :54-59 (pointer builtins added by F-PTRBUILTIN), interned :103-108, struct-literal assigned :205-217; `semanticAnalyzerIsTypeValueCast` :243-252 (`@as` at :250). Builtin-name branch chain starts ~:1525 (`@sizeOf`/`@alignOf`/`@offsetOf`/`@bitSizeOf`/`@bitOffsetOf`), `@ptrToInt`/`@intFromPtr` branch :1531-1533, `@ptrFromInt` :1534-1550 (clean `error[3000]` + result fallback pattern), `@fieldParentPtr` :1551-1561, then `@getChar` at :1562. The clean-diagnostic pattern = `diag_mod.diagnosticCollectorAdd(self.diag, 0, @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3000_TYPE_MISMATCH)), self.source_file_id, node.span_start, node.span_start + node.span_len, msg)` (precedent :1547-1548). Int-family helper `typeRegistryIsInteger` (type_registry.zig:728-742); per-type size = `registry.types_items[tid].size` (state==2 primitives: bool=4/u8=1/i32=4/u32=4 etc., type_registry.zig:605-627). The per-node result type is stored at the tail of `semanticAnalyzerResolveExpr` (:1762-1763).
3. Lower `lower.zig` builtin dispatch: `@ptrToInt`/`@intFromPtr` branch :3264-3273, `@ptrFromInt` :3274-3290, `@fieldParentPtr` :3291-3326 (each a standalone `if (...)` with early `return`, ALL BEFORE the comptime fold-map read at :3327 `if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {`), `@sizeOf`… `iceUnresolvedComptime` guard :3354-3357. Name-id struct fields :372-385 (`as_name_id` near :380), interned :436-459 (`.as_name_id = as_id` intern at :458-459), struct-literal assigned :526-543 (`.as_name_id = as_id,` at :543). The unchecked-cast emission template (mirror EXACTLY) is the `@as` arm of the generic 2-arg cast tail at :3623-3627:
   ```zig
        } else if (node.child_0 == self.as_name_id) {
            emitInst(self, LirInst{ .int_cast = .{
                .value = val_temp, .target = t_target, .result = result,
                .is_checked = @intCast(u8, 0),
            } });
        }
   ```
   `emitInst`/`nextTemp`/`LirInst`/`type_resolver.resolveTypeExprFull`/`lowerExpr` are all in scope in the dispatch (see the `@fieldParentPtr` branch :3291-3326 for the exact `TypeResolveEnv` + `resolveTypeExprFull` idiom and the `ec` child-buf read at :3263).
4. The R3 fixture (committed, currently RED on the F-PTRBUILTIN compiler): `repro/mi_matrix/builtin_bitcast_xmod/main.zig` (source in Task 1 Step 1 below). Pre-fix behavior: silent dump rc=0, valid C, `@bitCast` result DROPPED (falls to zero-init), run prints `0` (not `-1`) — RED class runtime-wrong.

---

### Task 1: Implement `@bitCast`

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (struct ~:54-70; init interns ~:103-110; struct-literal assign ~:205-218; new dispatch branch between `@fieldParentPtr` :1561 and `@getChar` :1562)
- Modify: `sf/src/lower.zig` (struct ~:372-385; init interns ~:436-460; struct-literal assign ~:526-545; new dispatch branch between `@fieldParentPtr` :3326 and the fold-map read :3327)

**Interfaces:**
- Consumes: `typeRegistryIsInteger`, per-type registry `.size`, `diag_mod.diagnosticCollectorAdd` error[3000] template, `type_resolver.resolveTypeExprFull`, `LirInst.int_cast` unchecked arm; the R3 fixture.
- Produces: `@bitCast(Dest, src)` recognized (sema gate) + lowered (unchecked int_cast); R3 fixture GREEN (`-1`); 4-MD5 gates byte-identical; comptime_eval.zig untouched.

- [ ] **Step 1: Confirm the pre-edit RED + snapshot gates**

Against the current reference (repo-root CWD; `/tmp/fx_subfolder/zig1` md5 `d0da7204…`, std lib already in `/tmp/fx_subfolder/lib`):
```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/builtin_bitcast_xmod/main.zig /tmp/fbc_red
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum; done
```
Expected: the fixture compiles but prints `0` (RED runtime-wrong — run-gate stdout `0\n`, NOT the contract `-1\n`); the four md5s equal gol `302df36b…`/lisp `3591bad9…`/json `76056b97…`/mud `53405b3b…`. If the fixture is already GREEN or any gate hash moved, STOP-present.

- [ ] **Step 2: Edit `sf/src/semantic_analyzer.zig`**

(2a) Add one name-id field to the struct right after `.field_parent_ptr_name_id: u32,` (:59):
```
    bitcast_name_id: u32,
```

(2b) Intern `@bitCast` right after the `@fieldParentPtr` intern (:107-108) and assign in the struct literal right after `.field_parent_ptr_name_id = fpp_id,` (:207):
```
    var bc_s: []const u8 = "@bitCast";
    var bc_id = interner_mod.stringInternerIntern(interner, bc_s);
```
```
        .bitcast_name_id = bc_id,
```

(2c) Add a NEW branch immediately AFTER the `@fieldParentPtr` branch (after its `result = fpp_res;` / closing `}` at :1561) and BEFORE the `} else if (node.child_0 == self.getchar_name_id) {` line (:1562). The new branch must be a chained `} else if` so the surrounding if/else-if chain continues:
```zig
        } else if (node.child_0 == self.bitcast_name_id) {
            var bc_res: u32 = @intCast(u32, type_mod.TYPE_VOID);
            if (ec.len >= @intCast(usize, 2)) {
                var bc_env = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbols, .interner = self.interner, .module_id = self.module_id };
                var bc_dst = type_resolver.resolveTypeExprFull(&bc_env, ec[@intCast(usize, 0)], @intCast(u32, 0));
                if (bc_dst != type_mod.TYPE_UNDEFINED) {
                    var bc_src = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 1)]);
                    var bc_ok: u8 = @intCast(u8, 0);
                    if (bc_src != type_mod.TYPE_UNDEFINED and type_mod.typeRegistryIsInteger(self.registry, bc_dst) and type_mod.typeRegistryIsInteger(self.registry, bc_src)) {
                        var bc_dty = self.registry.types_items[@intCast(usize, bc_dst)];
                        var bc_sty = self.registry.types_items[@intCast(usize, bc_src)];
                        if (bc_dty.state == @intCast(u8, 2) and bc_sty.state == @intCast(u8, 2) and bc_dty.size == bc_sty.size) {
                            bc_ok = @intCast(u8, 1);
                        }
                    }
                    bc_res = bc_dst;
                    if (bc_ok == @intCast(u8, 0)) {
                        var bc_msg: []const u8 = "@bitCast requires same-size integer source and destination types";
                        _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3000_TYPE_MISMATCH)), self.source_file_id, node.span_start, node.span_start + @intCast(u32, node.span_len), bc_msg);
                    }
                }
            }
            result = bc_res;
```
Notes: `node`/`node_idx`/`ec`/`self.diag`/`result` are in scope in this dispatch (verify against the `@ptrFromInt`/`@fieldParentPtr` sibling branches :1534-1561). The `bc_res` initializer uses the operator-authorized D1 `@intCast(u32, ...)` wrap (AMENDMENT 1, Global Constraints) — the unwrapped `type_mod.TYPE_VOID` form is dropped by zig0 during self-compile. On gate failure the branch STILL returns `bc_dst` (`bc_res = bc_dst`) so the var-decl never sees a bogus `TYPE_VOID` cascade; the recorded `error[3000]` already stops the compile (rc=2, 0 `.c`). If `bc_dst` is unresolvable (`TYPE_UNDEFINED`), `bc_res` stays `TYPE_VOID`.

- [ ] **Step 3: Edit `sf/src/lower.zig`**

(3a) Add one name-id field to the struct right after `.as_name_id: u32,` (field list ~:372-385):
```
    bitcast_name_id: u32,
```

(3b) Intern `@bitCast` right after the `@as` intern (:458-459) and assign in the struct literal right after `.as_name_id = as_id,` (:543):
```
    var bc_s: []const u8 = "@bitCast";
    var bc_id = si_mod.stringInternerIntern(ctx.registry.interner, bc_s);
```
```
         .bitcast_name_id = bc_id,
```

(3c) Add a NEW standalone branch immediately AFTER the `@fieldParentPtr` branch's closing `}` (after its trailing `return nextTemp(self, type_mod.TYPE_VOID);` at :3325-3326) and BEFORE the fold-map read at :3327 (`if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {`):
```zig
            if (node.child_0 == self.bitcast_name_id) {
                if (ec.len >= @intCast(usize, 2)) {
                    var bc_env = type_resolver.TypeResolveEnv{ .store = self.ctx.store, .typereg = self.ctx.registry, .symbol_reg = self.ctx.symbol_tables, .interner = self.ctx.registry.interner, .module_id = self.module_id };
                    var bc_dst = type_resolver.resolveTypeExprFull(&bc_env, ec[@intCast(usize, 0)], @intCast(u32, 0));
                    if (bc_dst != type_mod.TYPE_UNDEFINED) {
                        var bc_arg = lowerExpr(self, ec[@intCast(usize, 1)]);
                        var bc_res = nextTemp(self, bc_dst);
                        emitInst(self, LirInst{ .int_cast = .{ .value = bc_arg, .target = bc_dst, .result = bc_res, .is_checked = @intCast(u8, 0) } });
                        return bc_res;
                    }
                }
                return nextTemp(self, type_mod.TYPE_VOID);
            }
```
Notes: match the exact variable names already in scope in the builtin dispatch — `node`, `node_idx`, `ec`, `self.ctx`, `type_mod`, `ast_mod`, `type_resolver`, `hash_mod`, `LirInst`, `emitInst`, `nextTemp`, `lowerExpr` (see the sibling branches :3264-3326). The `.int_cast` unchecked emission is byte-identical in shape to the `@as` arm at :3623-3627. Do NOT touch the checked `@intCast` path.

- [ ] **Step 4: Rebuild the reference compiler**

```bash
timeout 900 bash sf/scripts/build_release.sh
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```
Expected: release-Done, NEW `/tmp/fx_subfolder/zig1` md5 (≠ `d0da7204…`), std lib re-installed. Record the md5.

- [ ] **Step 5: Verify the fixture flips RED→GREEN**

```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/builtin_bitcast_xmod/main.zig /tmp/fbc_green
```
Expected: `RUNRC=0`; stdout byte-exact `-1`; gcc clean. Confirm the emitted `main_*.c` shows the result is now carried (an unchecked int-cast of the `u32` temp to `i32`, assigned to `s`) rather than dropped. If not GREEN with the exact contract, STOP-present.

- [ ] **Step 6: Negative gate probe (clean diagnostic, not silent/wrong)**

Create `/tmp/bc_probe.zig` (scratch, NOT committed):
```zig
const std = @import("std");

pub fn main() void {
    var u: u32 = 0xFFFFFFFF;
    var s = @bitCast(u8, u);
    std.io.printInt(@intCast(i32, s));
    std.io.writeByte('\n');
}
```
Run `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/bc_probe_out /tmp/bc_probe.zig` (fresh-dir `rm -rf`+`mkdir -p` first). Expected: clean `error[3000]` with the message `@bitCast requires same-size integer source and destination types`, rc=2, 0 `.c`, NO ICE, NO silent truncation, NO PANIC. Record the diagnostic line verbatim.

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
bash scripts/self_compile/build_next_gen.sh /tmp/fx_subfolder/zig1 /tmp/fbc_self
```
Expected: dump rc=0, 42 `.c`, 0 `error[`, 0 PANIC, hop binaries md5-identical to each other AND to the new reference (fixed point closed). Record the NEW fixed-point md5. If the fixed point does NOT close (hop1 ≠ reference or hop2 ≠ hop1), STOP-present.

- [ ] **Step 10: Commit + report**

```bash
git add sf/src/semantic_analyzer.zig sf/src/lower.zig
git commit -m "feat: @bitCast same-size integer reinterpretation (F-BITCAST)"
```
Stage ONLY the two source files. Pre-existing dirty/untracked files stay unstaged. Append the full report to `.superpowers/sdd/task-F-BITCAST-report.md` (`## F-BITCAST-1`): RED proof, exact edits (per-file hunk list), fixture GREEN evidence (stdout bytes + emitted-C shape), the negative-probe diagnostic, 4-MD5 table, new reference md5, fixed-point md5, commit sha, git-status-at-end. Ledger line in `.superpowers/sdd/progress.md`.

Report back: `DONE` + commit sha + one-line battery summary + any concern.

---

### Task 2: Full battery + corpus reconciliation + STOP-present re-baseline proposal

**Files:**
- Create report: `.superpowers/sdd/task-F-BITCAST-report.md` (`## F-BITCAST-2` appended; gitignored scratch)

**Interfaces:**
- Consumes: the Task-1 compiler `/tmp/fx_subfolder/zig1` (new md5), the GREEN fixture, `.superpowers/sdd/task-LANGWINS-report.md` G1 corpus numbers.
- Produces: full-battery evidence, corpus reconciliation table, STOP-present with a re-baseline proposal for the NEW self-compile fixed-point md5 (operator-ruled). NO commits in this task.

- [ ] **Step 1: Golden 9/9**

Run the 9 golden fixtures (emission_assoc_chain_xmod, fn_ptr_struct_field, emission_lower_crash_xmod, tco_return_try, tco_defer, tco_factorial, quicksort, func_ptr_return, hello) emit→gcc→link→run with the new compiler; stdout byte-identical to the pre-change golden. Record rc + stdout state.

- [ ] **Step 2: Matrix 21/21**

Run the 21 `examples/z98` programs emit→gcc→link→run; all rc=0; mud_server + rogue_mud timeout-gated rc=124 with correct output = PASS; runtime stdout byte-equal vs pre-change reference.

- [ ] **Step 3: Corpus sweep (424 dirs, `-s0`) + asymmetric reconciliation + run-gate flip proof**

Generate the 424-dir list (R-phase enumeration in task-LANGWINS-report.md G1). Sweep the new compiler with that list + `sweep.sh` into a fresh dir. The pre-edit reference no longer exists (rebuilt in Task 1); the stored pre-edit baseline for the IDENTICAL list+script+same-compiler-source-lineage is `/tmp/fptr_sweep_new/results.txt` (d0da7204-era, OK=402/FAIL=15/GCCFAIL=0/GREEN=6/ICE=1/CRASH=0) — reuse it as the pre-edit side (F-PTRBUILTIN-2 precedent).
Expected: **0 per-dir asymmetric** between the stored baseline and the new sweep (the R3 fixture classifies `OK` on BOTH sides because its RED class is compile-OK runtime-wrong — the compile-only sweep cannot see the flip). This 0-asymmetric is the SUCCESS signal, NOT a no-op. Then PROVE the behavioral flip explicitly via the run-gate:
```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/builtin_bitcast_xmod/main.zig /tmp/fbc_run2
```
Expected: `RUNRC=0`, stdout byte-exact `-1` (contract). Any per-dir delta OTHER than expected, or any NEW FAIL/ICE/CRASH anywhere, or a run-gate that does not print `-1` → STOP-present.

- [ ] **Step 4: Self-compile confirmation + fixed-point record**

Re-summarize the Task-1 round-trip; record the NEW fixed-point md5; state plainly it MOVED from `0468a42b…` because compiler source grew (expected).

- [ ] **Step 5: STOP-present re-baseline proposal**

Append `## F-BITCAST-2` with full evidence. STOP-present: re-baseline self-compile fixed point `(previous) → (new)` (operator-ruled); 4-MD5 gates unchanged → NO gate re-baseline; the R3 fixture is GREEN and its EXPECTED_FAIL.md row needs a RESOLVED docs update in Task 3 AFTER operator approval. Report back: `DONE` + summary + concerns. NO commit.

---

### Task 3: Docs GATE — EXPECTED_FAIL.md resolution + QUICK_REF baseline (operator-approved)

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`
- Modify: `docs/sf/QUICK_REF.md`

**Interfaces:**
- Consumes: operator approval of the Task-2 re-baseline proposal; the Task-2 evidence.
- Produces: committed docs reconciliation. THIS TASK RUNS ONLY AFTER THE OPERATOR APPROVES.

- [ ] **Step 1: EXPECTED_FAIL.md — mark the R3 row RESOLVED**

Header version bump (v65 → v66, file convention). For the Langwins section carrying `builtin_bitcast_xmod`: mark RESOLVED with the F-BITCAST fix commit sha + the GREEN contract (`-1`, run-gate verified). Preserve the historical RED text beneath (file convention — the RED record documents the silent-drop-prints-`0` class). Touch no other section.

- [ ] **Step 2: QUICK_REF.md — new newest-first baseline bullet**

Insert a dense dated bullet ABOVE the current newest (the `Post-F-PTRBUILTIN baseline`) recording: F-BITCAST commit sha, `@bitCast` same-size INTEGER reinterpretation only (semantic size-equality gate + clean `error[3000]`; unchecked-int-cast emission; bool/float/comptime-int excluded), R3 fixture GREEN (`-1`), the special corpus note (0 compile-sweep asymmetric; runtime-wrong RED only visible via run-gate), 4-MD5 gates byte-identical (unchanged hashes), golden 9/9, matrix 21/21, NEW reference md5 + NEW self-compile fixed-point md5 (operator-ruled re-baseline).

- [ ] **Step 3: Commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs: GATE — @bitCast GREEN + fixed-point re-baseline (F-BITCAST)"
```
Only the two doc files staged. Report back: `DONE` + commit sha.

---

## Plan Self-Review (performed at authoring time)

1. **Spec coverage:** A7 `@bitCast` (design spec §1, I3 verdict IMPLEMENT-NOW) → Task 1 implements exactly the I3 prescription (reuse of the `@as` unchecked-int-cast arm — NOT the checked `@intCast` path which panics rc=134; same-size gate via registry `.size`; int-family gate via `typeRegistryIsInteger`; clean `error[3000]` instead of the `@as` silent-truncation/wrong-conversion class; comptime_eval unchanged); Task 2 = regression discipline incl. the run-gate-flip proof that the compile-only sweep cannot see; Task 3 = EXPECTED_FAIL/QUICK_REF reconciliation. GREEN contract matches the committed R3 header exactly (`-1`). The probe-proven silent-wrong classes (`@as(u8,u32 0xFFFFFFFF)`→255; `@as(u32,f32 1.5)`→1) are exactly what the gate rejects.
2. **Placeholder scan:** no TBD/TODO; every step carries exact file paths, complete edit content, and commands; insertion blocks are complete code.
3. **Type/name consistency:** `bitcast_name_id` named identically across both files; intern string `@bitCast` matches the fixture call site. The sema result (`bc_res`) is the resolved dest type so the var-decl/print typing flows correctly (`var s = @bitCast(i32, u)` → `s: i32` → `printInt(s)` prints `-1`). Sema gate and lower branch both re-resolve `ec[0]` locally (mirroring F-PTRBUILTIN's ptr/field-parent pattern) — no cross-phase state coupling.

## Execution Handoff

Plan complete. **Subagent-Driven (recommended per operator):** fresh implementer subagent per task + task reviewer (spec compliance + quality) after each; Task 2 and Task 3 proceed only after the prior review approves and, for Task 3, after the operator approves the Task-2 re-baseline proposal.
