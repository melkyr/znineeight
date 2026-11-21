# F-SWITCHRANGE Implementation Plan — switch case-range expansion

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make zig1 lower switch-prong case RANGES (`1...5 =>` inclusive `...`, `1..5 =>` exclusive `..`) by EXPANDING each range into per-value case entries, so the committed R6 RED fixture `repro/mi_matrix/switch_case_range_xmod/main.zig` goes GREEN with byte-exact stdout `130 47`.

**Architecture:** one shared helper in `sf/src/lower.zig` + one hardening line in `sf/src/c89_emit.zig`. Both the switch-EXPRESSION and switch-STATEMENT lowering paths build their case list in byte-identical inner loops (expr lower.zig ~:4174-4231, stmt ~:5056-5112) that dispatch each prong item to a scalar `SwitchCase` and `continue` (drop) on anything else — range nodes hit that drop today. The loops are replaced by a call to ONE new method `lowerAppendSwitchCaseItem(self, item_idx, prong_bb_id, cond_ty_id)` that replicates the scalar dispatch AND expands inclusive/exclusive ranges (literal int/char endpoints) into consecutive `SwitchCase{value,target_bb}` entries. `cases_start` is snapshotted before the prong loop and `cases_count` computed after, so expansion needs no LIR/emitter/block/serde change. The c89_emit `case N:` line hardens from `itoa(u32)` (truncating) to `itoa64(u64)`. comptime_eval untouched.

**Tech Stack:** Z98 dialect in `sf/src/*.zig` (self-hosted compiler source); verified against the rebuilt zig0-bootstrap reference; R6 fixture run-gate.

## Global Constraints

- This plan is **F-SWITCHRANGE** = item 6 of the operator-approved follow-on execution order (I6 verdict IMPLEMENT-NOW, representation (a) EXPAND per-value). ONLY range-case expansion + the `itoa64` hardening; **no other F work, no other compiler changes.**
- Z98 dialect discipline: `@intCast` on every narrowing/widening; no `anytype`/`@Type`; `switch` must have `else`; no method syntax; no pointer captures. Follow the surrounding file style exactly.
- Source edits via `fastedit` ONLY per `docs/sf/AGENTS.md` X.7 (re-read the region immediately before every edit; absolute line numbers; edit bottom-to-top; an INSERT = replace the anchor line keeping the original at the end of `new_code` since `end_line = start_line - 1` errors; a multi-line replacement = delete the old line range then insert, or replace the range keeping nothing extra). No python/sed/bulk transforms. No `git checkout` to erase.
- **Files that MAY change: `sf/src/lower.zig`, `sf/src/c89_emit.zig`. NO other `sf/src` file; `comptime_eval.zig` MUST stay byte-identical; never touch `sf/build/out_release/`. The R6 fixture is committed verbatim and is NOT amended.**
- **Operator-authorized D1 dialect (carried from F-BITCAST AMENDMENT 1):** cross-module comptime-const local-init decls (`var x: u32 = type_mod.TYPE_*;`) dropped by zig0 during self-compile may be wrapped `@intCast(u32, type_mod.TYPE_*)` WITHOUT a fresh ruling. Any other drop/undeclared class → STOP-present.
- Reference rebuild: `timeout 900 bash sf/scripts/build_release.sh` → output `/tmp/fx_subfolder/zig1`. **CRITICAL:** this rebuild wipes `/tmp/fx_subfolder/lib` — after any rebuild re-install the canonical std lib (cp `sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig}` into `/tmp/fx_subfolder/lib/`).
- GREEN contract (byte-exact stdout, run-gate `RUNRC=0`): `switch_case_range_xmod` → `130 47`.
- The 4-MD5 gate programs contain NO range cases (`..` in their source is slice syntax) ⇒ their dump md5 MUST stay byte-identical: gol `302df36b…`, lisp `3591bad9…`, json `76056b97…`, mud `53405b3b…`. Any move is a bug → STOP-present. The `itoa64` change prints identical digits for values < 2³² (all existing scalar cases) so it is byte-neutral.
- Range semantics (locked): `...` inclusive ⇒ values lo..hi inclusive; `..` exclusive ⇒ values lo..hi-1; endpoints must be int or char LITERALS (resolved via `astStoreIntValue`); empty/`hi<lo` ranges contribute nothing; a range whose expansion width would exceed **16384** entries is NOT expanded (dropped, exactly today's behavior for that item — documented limitation, no new silent wrongness vs today); negative/computed endpoints (e.g. `negate` nodes) are NOT expanded (dropped as today). Overlapping/duplicate case values (scalar+range or range+range) surface as C duplicate-case gcc errors — Zig-equivalent intent, no dedup (documented limitation, out of scope).
- **Battery/docs deferral (operator scheme, F-BITCAST AMENDMENT 2):** this plan contains ONLY the implementation task. The full battery (golden/matrix/corpus) + fixed-point re-baseline STOP-present + EXPECTED_FAIL/QUICK_REF docs GATE for items 3-6 run COMBINED once this item lands. Per-commit gates that STILL hold here: fixture RED→GREEN byte-exact, 4-MD5 byte-identical, self-compile fixed point closes (record new md5), exact commit scope.
- Authoritative per-fixture classifier = Step-4 recipe in `.superpowers/sdd/task-LANGWINS-report.md` (`fixture_run.sh` run-gate; fresh output dir `rm -rf`+`mkdir -p` REQUIRED, else dump ICEs rc=3 spill-open). Pre-existing dirty/untracked repo files are NEVER staged or committed.
- Commit messages follow repo style (lowercase `feat:`/`test:`/`fix:`/`docs:` prefix + concise body).
- Operator standing rules: only plan-authorized actions; STOP-and-present on any issue or any plan-vs-evidence divergence; store memories as we go (mnemoria agent `fswitchrange-session`); NO context compression during this build session.

---

## Background (verified anchors — read before editing; line numbers at HEAD `9b2fef74`)

1. Parser: range nodes are plain prong-item nodes — `parserParseSwitchProng` builds `..` → `range_exclusive`, `...` → `range_inclusive` (parser.zig ~:974-991, ast.zig:96-97) with `child_0`=lo, `child_1`=hi; prong items live in a swt_prong extra-children list. `semantic_analyzer.zig:1806-1808` resolves a range node's type to TYPE_U32; NO endpoint/overlap/comptime check exists anywhere.
2. Switch lowering (both paths share the identical case-map shape): switch-EXPRESSION in `lowerExprImpl` (lower.zig ~:4122+, case-map prong loop :4168-4232, inner per-item loop :4174-4231 with scalar dispatch int/char/enum_literal/error_literal/field_access, `} else { continue; }` drop :4225-4227, append :4229-4230); switch-STATEMENT in `lowerStmt` (case-map :5050-5113, inner loop :5056-5112 identical text, drop :5107-5109, append :5110-5111). Both: `cases_start` snapshot (expr :4167 / stmt :5049) BEFORE the loop and `cases_count = len - cases_start` (expr :4233-4234 / stmt :5114-5115) AFTER — expansion is auto-counted. Cond type `cond_ty_id: ?u32` is in scope in both (from `resolvedTypeTableGet(node.child_0)`). The 4-MD5 gates exercise no range node, so none of the new paths run for them.
3. Lir/emitter: `SwitchCase{value:u64,target_bb:u32}` (lir.zig:6-9); `switchCaseArrayListAppend(&self.func.switch_cases, …)` is the only appender. c89_emit `.switch_br` :6376-6414 prints `case <v>: goto z_bb_<n>;` with `itoa_mod.itoa(@intCast(u32, c.value), val_buf[0..])` at **:6391** (the u32 truncation — the latent bug to harden). `itoa64` already imported + used at c89_emit.zig:5902/5912; `val_buf: [20]u8` fits the full 20-digit u64. Scalar int/char values are read with `ast_mod.astStoreIntValue(store, node_idx)` (ast.zig:625).
4. R6 fixture (committed, 37 lines): `inRange(n:i32)` = `switch (n) { 1...5 => 10, 6...9 => 20, else => 0 }`; `charClass(ch:u8)` = `switch (ch) { 'a'...'e' => 1, 'f'...'z' => 2, else => 0 }`; `main` sums both over 1..9 and 'a'..'z' → prints `130 47`. RED today: ranges dropped → both switches take `else` → prints `0 0` (runtime-wrong, valid C).

---

### Task 1: Implement range-case expansion + `itoa64` hardening

**Files:**
- Modify: `sf/src/lower.zig` (new helper method + replace the two identical inner case-item loops with a call to it)
- Modify: `sf/src/c89_emit.zig` (one line: `itoa`→`itoa64` at :6391)

**Interfaces:**
- Consumes: existing scalar case-item dispatch (moved verbatim into the helper), `cond_ty_id`, `SwitchCase`, `astStoreIntValue`, the R6 fixture.
- Produces: shared `lowerAppendSwitchCaseItem(self, item_idx, prong_bb_id, cond_ty_id)` used by both paths; ranges expanded; R6 fixture GREEN (`130 47`); 4-MD5 byte-identical; fixed-point closes on a NEW md5.

- [ ] **Step 1: Confirm the pre-edit RED + snapshot gates**

Against the current reference (repo-root CWD; `/tmp/fx_subfolder/zig1` md5 `4b19f77d…`, std lib already installed):
```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/switch_case_range_xmod/main.zig /tmp/fsr_red
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum; done
```
Expected: the fixture compiles but prints `0 0` (RED runtime-wrong — run-gate stdout `0 0\n`, NOT the contract `130 47\n`); the four md5s equal gol `302df36b…`/lisp `3591bad9…`/json `76056b97…`/mud `53405b3b…`. If the fixture is already GREEN or any gate hash moved, STOP-present.

- [ ] **Step 2: Add the helper to `sf/src/lower.zig`**

Insert the new method immediately BEFORE the existing `fn getTempType(self: *LirLowerer, temp_id: u32) u32 {` (currently ~:1299; re-read to confirm). INSERT = replace that anchor line keeping it at the END of `new_code`:
```zig
fn lowerAppendSwitchCaseItem(self: *LirLowerer, item_idx: u32, prong_bb_id: u32, cond_ty_id: ?u32) void {
    var node = ast_mod.astStoreNodeAt(self.ctx.store, item_idx);
    if (node.kind == AstKind.range_inclusive or node.kind == AstKind.range_exclusive) {
        var lo_node = ast_mod.astStoreNodeAt(self.ctx.store, node.child_0);
        var hi_node = ast_mod.astStoreNodeAt(self.ctx.store, node.child_1);
        var lo_is_lit: u8 = @intCast(u8, 0);
        if (lo_node.kind == AstKind.int_literal or lo_node.kind == AstKind.char_literal) { lo_is_lit = @intCast(u8, 1); }
        var hi_is_lit: u8 = @intCast(u8, 0);
        if (hi_node.kind == AstKind.int_literal or hi_node.kind == AstKind.char_literal) { hi_is_lit = @intCast(u8, 1); }
        if (lo_is_lit == @intCast(u8, 1) and hi_is_lit == @intCast(u8, 1)) {
            var lo = ast_mod.astStoreIntValue(self.ctx.store, node.child_0);
            var hi = ast_mod.astStoreIntValue(self.ctx.store, node.child_1);
            if (hi >= lo) {
                var one: u64 = @intCast(u64, 1);
                var count: u64 = if (node.kind == AstKind.range_inclusive) (hi - lo) + one else hi - lo;
                if (count <= @intCast(u64, 16384)) {
                    var vv: u64 = lo;
                    var ctr: u64 = @intCast(u64, 0);
                    while (ctr < count) : (ctr += @intCast(u64, 1)) {
                        lir_mod.switchCaseArrayListAppend(&self.func.switch_cases, lir_mod.SwitchCase{ .value = vv, .target_bb = prong_bb_id });
                        vv += @intCast(u64, 1);
                    }
                }
            }
        }
        return;
    }
    var case_val: u64 = @intCast(u64, 0);
    if (node.kind == AstKind.int_literal) {
        case_val = ast_mod.astStoreIntValue(self.ctx.store, item_idx);
    } else if (node.kind == AstKind.char_literal) {
        case_val = ast_mod.astStoreIntValue(self.ctx.store, item_idx);
    } else if (node.kind == AstKind.enum_literal) {
        var cval2: u64 = @intCast(u64, ast_mod.astStoreNodePayload(self.ctx.store, item_idx));
        var cev2 = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, item_idx);
        if (cev2) |v| { cval2 = @intCast(u64, v); }
        case_val = cval2;
    } else if (node.kind == AstKind.error_literal) {
        var cval3: u64 = @intCast(u64, hash_mod.u32ToU32MapGetOrAddDense(self.ctx.error_code_registry, ast_mod.astStoreNodePayload(self.ctx.store, item_idx)));
        var cev3 = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, item_idx);
        if (cev3) |v| { cval3 = @intCast(u64, v); }
        case_val = cval3;
    } else if (node.kind == AstKind.field_access) {
        var fa_name_id: u32 = ast_mod.astStoreNodePayload(self.ctx.store, item_idx);
        var fa_found: bool = false;
        if (cond_ty_id) |ct| {
            var ct_ty = self.ctx.registry.types_items[@intCast(usize, ct)];
            if (ct_ty.kind == type_mod.TypeKind.enum_type) {
                var ep = self.ctx.registry.en_items[@intCast(usize, ct_ty.payload_idx)];
                var estart: usize = @intCast(usize, ep.members_start);
                var ecount: usize = @intCast(usize, ep.members_count);
                var ei: usize = 0;
                while (ei < ecount) : (ei += 1) {
                    var member = self.ctx.registry.em_items[estart + ei];
                    if (member.name_id == fa_name_id) {
                        case_val = @intCast(u64, member.value);
                        fa_found = true;
                        break;
                    }
                }
            } else if (ct_ty.kind == type_mod.TypeKind.tagged_union_type) {
                var tp = self.ctx.registry.tu_items[@intCast(usize, ct_ty.payload_idx)];
                var fstart: usize = @intCast(usize, tp.fields_start);
                var fcount: usize = @intCast(usize, tp.fields_count);
                var fi: usize = 0;
                while (fi < fcount) : (fi += 1) {
                    if (self.ctx.registry.fe_items[fstart + fi].name_id == fa_name_id) {
                        case_val = @intCast(u64, fi);
                        fa_found = true;
                        break;
                    }
                }
            }
        }
        if (!fa_found) { return; }
    } else {
        return;
    }
    lir_mod.switchCaseArrayListAppend(&self.func.switch_cases, lir_mod.SwitchCase{ .value = case_val, .target_bb = prong_bb_id });
}

fn getTempType(self: *LirLowerer, temp_id: u32) u32 {
```
Notes: this is the EXACT scalar logic moved from the two inner loops plus the range arm on top; `self.ctx.store`/`registry`/`enum_value_table`/`error_code_registry`/`lir_mod`/`ast_mod`/`hash_mod`/`AstKind`/`type_mod` are all in scope (verified in the loops being replaced). The range arm `return`s on any non-literal/empty/over-cap case so such items contribute nothing (today's drop semantics).

- [ ] **Step 3: Replace the two identical inner case-item loops with a call**

Both loops are TEXTUALLY IDENTICAL. Replace, in BOTH the switch-EXPRESSION path (currently ~:4174-4231) and the switch-STATEMENT path (currently ~:5056-5112), the ENTIRE inner loop from `var ci: usize = 0;` through its closing `}` (the block that declares `case_node` and ends with the `switchCaseArrayListAppend(...)` + `}`), with:
```zig
            var ci: usize = 0;
            while (ci < case_ec.len) : (ci += 1) {
                lowerAppendSwitchCaseItem(self, case_ec[ci], prong_bb_id, cond_ty_id);
            }
```
Notes: do NOT touch the prong loop, the `cases_start` snapshot, the `cases_count` computation, the `switch_br` emission, or the else/capture/body loops. `prong_bb_id` and `cond_ty_id` are already in scope at both sites. Re-read each site immediately before editing to get its exact current line range; the deletion must remove ONLY the old inner-loop text (both copies), and the replacement must keep the surrounding `var prong_bb_id…` / case_ec / ci scaffolding intact. Verify no other textually identical block exists elsewhere in the file before editing (the two target copies are the only ones with `case_val`/`switchCaseArrayListAppend`).

- [ ] **Step 4: Harden the emitter case-value print in `sf/src/c89_emit.zig`**

Change :6391 from
```zig
                var val_len = itoa_mod.itoa(@intCast(u32, c.value), val_buf[0..]);
```
to
```zig
                var val_len = itoa_mod.itoa64(c.value, val_buf[0..]);
```
Notes: `c.value` is u64; identical decimal output for values < 2³², so non-range programs emit byte-identical C. `val_buf: [20]u8` fits the max 20-digit u64.

- [ ] **Step 5: Rebuild the reference compiler**

```bash
timeout 900 bash sf/scripts/build_release.sh
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```
Expected: release-Done, NEW `/tmp/fx_subfolder/zig1` md5 (≠ `4b19f77d…`), std lib re-installed. Record the md5.

- [ ] **Step 6: Verify the fixture flips RED→GREEN**

```bash
bash /tmp/sd_work/fixture_run.sh /tmp/fx_subfolder/zig1 repro/mi_matrix/switch_case_range_xmod/main.zig /tmp/fsr_green
```
Expected: `RUNRC=0`; stdout byte-exact `130 47`; gcc clean. Confirm the emitted `main_*.c` switch statements now carry the expanded per-value `case` labels (inRange: `case 1:…case 9:` → the 10/20 bodies; charClass: `case 97:`…`case 122:`) and NO range construct is silently dropped. If not GREEN with the exact contract, STOP-present.

- [ ] **Step 7: 4-MD5 gates byte-identical (repo-root CWD)**

```bash
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 examples/z98/$e/main.zig | md5sum; done
```
Expected: gol `302df36b…` / lisp `3591bad9…` / json `76056b97…` / mud `53405b3b…` — all four byte-identical. ANY move = a bug → STOP-present (do not re-baseline).

- [ ] **Step 8: comptime_eval.zig byte-identical check**

```bash
git diff --stat sf/src/comptime_eval.zig
```
Expected: NO output. If it changed, STOP-present.

- [ ] **Step 9: Self-compile round-trip (fixed point check)**

```bash
bash scripts/self_compile/build_next_gen.sh /tmp/fx_subfolder/zig1 /tmp/fsr_self
```
Expected: dump rc=0, 42 `.c`, 0 `error[`, 0 PANIC, hop binaries md5-identical to each other AND to the new reference (fixed point closed). Record the NEW fixed-point md5. If the fixed point does NOT close, STOP-present. (Fixed-point re-baseline is part of the COMBINED items-3-6 STOP-present — not here.)

- [ ] **Step 10: Commit + report**

```bash
git add sf/src/lower.zig sf/src/c89_emit.zig
git commit -m "feat: switch case-range expansion (per-value) + itoa64 case hardening (F-SWITCHRANGE)"
```
Stage ONLY those two files. Pre-existing dirty/untracked files stay unstaged. Append the full report to `.superpowers/sdd/task-F-SWITCHRANGE-report.md` (`## F-SWITCHRANGE-1`): RED proof, per-file hunk list, fixture GREEN evidence (stdout bytes + emitted-C case-label confirmation), 4-MD5 table, new reference md5, new fixed-point md5, commit sha, git-status-at-end. Ledger line in `.superpowers/sdd/progress.md`. Store a success memory via `mnemoria --path .opencode/memory add --agent fswitchrange-session ...`.

Report back: `DONE` + commit sha + one-line test summary + any concern.

---

## Plan Self-Review (performed at authoring time)

1. **Spec coverage:** I6 verdict (representation (a) EXPAND per-value, drop-in in the shared case-map loops, no LIR change; itoa64 hardening) → Task 1 implements exactly that via one shared helper used by both paths; the case-map loops' snapshots/counts are untouched so expansion is auto-counted. R6 GREEN contract (`130 47`) covers both int and char endpoints. comptime_eval untouched.
2. **Placeholder scan:** no TBD/TODO; every step carries exact file paths, complete edit content/anchors, and commands.
3. **Type/name consistency:** `lowerAppendSwitchCaseItem(self, item_idx, prong_bb_id, cond_ty_id)` matches the in-scope names at both call sites (`self`, `case_ec[ci]`, `prong_bb_id`, `cond_ty_id`); helper field access mirrors the existing loop code (`self.ctx.store/registry/enum_value_table/error_code_registry`, `lir_mod.switchCaseArrayListAppend`, `lir_mod.SwitchCase{value,target_bb}`); `itoa64` already imported in c89_emit.

## Execution Handoff

Plan complete. **Subagent-Driven (recommended per operator):** fresh implementer subagent per task + task reviewer (spec compliance + quality). No Task 2/Task 3 in this plan — battery + fixed-point re-baseline + docs GATE for items 3-6 run COMBINED after this item, per the operator deferral scheme (F-BITCAST AMENDMENT 2).
