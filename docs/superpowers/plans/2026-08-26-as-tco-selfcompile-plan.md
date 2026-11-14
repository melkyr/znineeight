# `@as` Miscompilation + TCO Self-Emission — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three self-emission fidelity gaps of the self-compiled `zig1_5` — (A) missing fn-ptr typedefs, (B) compiler SEGV on `fn_ptr_struct_field`, (C) missing TCO back-edge — each verified against the `zig1` oracle.

**Architecture:** A and B share ONE root cause (`@as` unhandled in zig1's Zig source); R-A/R-B capture RED baselines, then a single F-AS fix adds `@as` builtin handling (faithful, mirrors the F-ASSOC `@intToEnum` precedent). C is separate (TCO back-edge missing; root cause NOT yet pinned — `findTailCall` + TCO condition verified emitted correctly): I-C pins it (read-only), F-C applies the fix. GATE-FINAL re-runs the full sweep + gates + reconciliation.

**Tech Stack:** Zig (sf/src), C89 (emitted code), gcc -m32, bash (build scripts).

## Global Constraints

- Compiler under test `/tmp/fx_subfolder/zig1`; rebuild = `timeout 900 bash sf/scripts/build_release.sh` from REPO ROOT — gate `=== [release] Done ===`. Rebuild WIPES `/tmp/fx_subfolder/lib` — reinstall std: `mkdir -p /tmp/fx_subfolder/lib && cp sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig} /tmp/fx_subfolder/lib/`.
- **No `sf/src` fixes outside the plan's pinned loci.** Never touch `sf/build/out_release/` (WEDGED).
- Byte-identity gates (authoritative): gol `eed963e0640a073ed4eebb292f136e05`, lisp `c3c5847798e4553b2e34950e085bb6c6` (repo-root CWD), json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. Must remain byte-identical.
- Correctness bar = RUNTIME behavior vs the zig1 oracle (zig1 emission is authoritative-correct; byte-parity vs zig0 not required).
- Compile recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 X.zig`; multi-module `gcc -m32 -std=c89 -c` INSIDE output dir with absolute `-I /workspace/znineeight/sf/src/include`; link `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c`.
- Z98 dialect for all probe/fixture `.zig`: no anytype/@Type; `@intCast` for int casts; `switch` requires `else`; no method syntax; no pointer captures.
- Editing discipline: `edit`/`fastedit` only; re-read region before each edit; edit bottom-to-top; never `end_line=start_line-1`; insert via replacing an anchor line.
- Enforce `timeout 120` on ALL compiler/binary invocations (`timeout 900` for build_release.sh / build_zig1_5.sh).
- Ledger: append one line per completed task to `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory add --agent as-tco-session --type <discovery|decision|bugfix|problem|pattern>` per task.
- Reports to `.superpowers/sdd/task-<N>-report.md` (gitignored). WARNING: `.superpowers/sdd/task-1-report.md` is TRACKED and holds an unrelated prior report — never reuse that exact name; use descriptive names like `task-AS-report.md`, `task-TCO-report.md`.
- Self-compiled build: `timeout 900 bash scripts/self_compile/build_zig1_5.sh` → `/tmp/zig1_5/{zig1_5_asan,zig1_5_clean,lib/,gen/}`.
- Reference emission for self-emission diffs: `/tmp/ref_zig1.c` (zig0 concat) AND `/tmp/fx_subfolder/*.c` (authoritative); self-emission in `/tmp/zig1_5/gen/*.c`.
- Runtime sweep harness (re-create if `/tmp` was cleared): per-dir build+run with `/tmp/zig1_5/zig1_5_clean` AND `/tmp/fx_subfolder/zig1`, compare rc + stdout; reference-build-and-run only for comparison. z98 entries: `main.zig`, else `<dirname>.zig`.

---

### Task R-A: RED baseline for missing fn-ptr typedefs (A)

**Files:**
- Report: `.superpowers/sdd/task-AS-report.md` (gitignored; append per task)
- No source changes, no commit.

**Interfaces:**
- Consumes: the A finding (self-emitted C references `_FN_*` fn-ptr names never typedef'd).
- Produces: measured RED baseline table for the 6 A-fixtures (4 corpus + 2 z98); confirms reference is GREEN.

- [ ] **Step 1: Build both compilers fresh**

`timeout 900 bash sf/scripts/build_release.sh` from repo root (gate `=== [release] Done ===`), reinstall std into `/tmp/fx_subfolder/lib/`. `timeout 900 bash scripts/self_compile/build_zig1_5.sh`.

- [ ] **Step 2: Measure RED on the 6 A-fixtures**

For each of `emission_void_call_xmod`, `emission_void_call_control_xmod`, `func_ptr_return_type`, `inferred_errorset_fnptr` (`repro/mi_matrix/`), `quicksort`, `func_ptr_return` (`examples/z98/`, entry = dirname `.zig`):
- Reference: `(cd DIR && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir OUT main.zig)`; `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c`; link `zig_runtime.c` + `zig_pal.c`; run. Expected: dump/gcc/link rc=0, run rc=0, output matches each dir's documented expected output.
- zig1_5: same recipe with `/tmp/zig1_5/zig1_5_clean`. Expected RED: dump rc=0 but gcc fails with `unknown type name 'zT_…_FN_…'`.

- [ ] **Step 3: Confirm the divergent emission**

For one fixture (e.g. `func_ptr_return_type`), show the reference `zig_special_types.h` typedefs `_FP_*` (e.g. `typedef void (*zT_…_FP_int_int_int)(int, int);`) consistently referenced by the var decl. In the zig1_5 emission show the MISMATCH: the `_FP_*` typedef body IS present (flag is set — `typeRegistryMarkFnPtrUsed` + `type_resolver.zig:916` emit correctly) but the var-decl references the hollow `_FN_*` guard name instead. Root cause: `getCTypeName`'s `@as(u32,1)`/`@as(u32,0)` flag read at `c89_emit.zig:736` is miscompiled (reads uninitialized temp) → non-deterministic `'P'`/`'N'` per call → names disagree.

- [ ] **Step 4: Report + ledger + memory**

Report to `.superpowers/sdd/task-AS-report.md`: RED table (6 dirs), reference-vs-self evidence, root-cause pointer. Ledger + mnemoria (discovery).

---

### Task R-B: RED baseline for `fn_ptr_struct_field` SEGV (B)

**Files:**
- Report: `.superpowers/sdd/task-AS-report.md` (append section)
- No source changes, no commit.

**Interfaces:**
- Consumes: the B finding (zig1_5 SEGVs in `typeRegistryIsAssignable`).
- Produces: measured RED baseline (rc=139, ASAN backtrace); reference is GREEN.

- [ ] **Step 1: Reproduce the SEGV**

`mkdir -p OUT; (cd repro/mi_matrix/fn_ptr_struct_field && timeout 120 /tmp/zig1_5/zig1_5_clean --dump-c89 --output-dir OUT main.zig)` → rc=139 (Segmentation fault). Run 3× to confirm reproducibility. ASAN build: same with `/tmp/zig1_5/zig1_5_asan` → backtrace must show `zF_…_typeRegistryIsAssig` ← `semanticAnalyzerRes` frames, READ SEGV.

- [ ] **Step 2: Confirm reference is GREEN**

Same recipe with `/tmp/fx_subfolder/zig1` → rc=0; gcc/link/run all rc=0.

- [ ] **Step 3: Confirm the divergent emission**

In `/tmp/zig1_5/gen/type_registry_*.c` `typeRegistryIsAssignable`, show `zT_130 = zT_128 + zT_129;` where `zT_129` (the `@as(u32, fi)` result) is never written (grep the function body for a write to `zT_129`). Source anchor: `type_registry.zig:851-852`.

- [ ] **Step 4: Report + ledger + memory**

Append to `task-AS-report.md`: SEGV evidence, ASAN backtrace, reference-GREEN confirmation, divergent-emission pointer. Ledger + mnemoria (discovery).

---

### Task F-AS: add `@as` builtin handling (fixes A + B)

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (struct field ~:53-59, intern ~:101, assign ~:186, `IsTypeValueCast` ~:214-222)
- Modify: `sf/src/lower.zig` (struct field ~:369, intern ~:429, assign ~:511, cast-branch ~:3545-3550)
- Commit: `fix: self-emitted compiler handles @as cast builtin (fn-ptr typedef + typeRegistryIsAssignable)`

**Interfaces:**
- Consumes: R-A/R-B baselines + design §Background (pinned `@as` root cause, exactly 3 sites).
- Produces: zig1_5 handles `@as(u32, …)`; A fixtures gcc-clean + run matching ref; `fn_ptr_struct_field` no longer SEGVs; 4 MD5s byte-identical; matrix 21/21; self-compile 0 errors.

- [ ] **Step 1: semantic_analyzer.zig — register `@as`**

Mirror the `@intToEnum`/`ie_id` pattern exactly (three additions + one rule):
- struct: after `inttoenum_name_id: u32,` add `as_name_id: u32,`
- init: after `var ie_s: []const u8 = "@intToEnum"; var ie_id = stringInternerIntern(interner, ie_s);` add `var as_s: []const u8 = "@as"; var as_id = stringInternerIntern(interner, as_s);`
- assignment: after `.inttoenum_name_id = ie_id,` add `.as_name_id = as_id,`
- `semanticAnalyzerIsTypeValueCast`: after `if (name_id == self.inttoenum_name_id) return true;` add `if (name_id == self.as_name_id) return true;`

- [ ] **Step 2: lower.zig — register `@as` + cast branch**

Mirror the `@intToEnum` F-ASSOC pattern:
- struct: after `inttoenum_name_id: u32,` add `as_name_id: u32,`
- init: after the `"@intToEnum"` intern line add `var as_s: []const u8 = "@as"; var as_id = stringInternerIntern(ctx.registry.interner, as_s);`
- assignment: after `.inttoenum_name_id = inttoenum_id,` add `.as_name_id = as_id,`
- cast block: after the `inttoenum_name_id` branch add:

```zig
} else if (node.child_0 == self.as_name_id) {
    emitInst(self, LirInst{ .int_cast = .{
        .value = val_temp, .target = t_target, .result = result,
        .is_checked = @intCast(u8, 0),
    } });
}
```

- [ ] **Step 3: Rebuild both compilers**

`timeout 900 bash sf/scripts/build_release.sh` (repo root; gate `=== [release] Done ===`), reinstall std into `/tmp/fx_subfolder/lib/`. `timeout 900 bash scripts/self_compile/build_zig1_5.sh`. Self-compile re-count: `ls /tmp/zig1_5/gen/*.c | wc -l` = 40, `grep -a -c "error["` = 0 (build script already gates this).

- [ ] **Step 4: Gate verification**

- A: re-run the R-A recipe on all 6 A-fixtures with rebuilt `/tmp/zig1_5/zig1_5_clean` → dump/gcc/link/run all rc=0; run output matches reference binary output.
- B: `fn_ptr_struct_field` → `/tmp/zig1_5/zig1_5_clean --dump-c89` rc=0 (no SEGV); gcc/link/run rc=0.
- 4 MD5s byte-identical (repo-root CWD): gol `eed963e0…`, lisp `c3c58477…`, json `089e4f04…`, mud `a1d0dd55…`.
- Matrix 21/21 (dump/gcc/link rc=0).

- [ ] **Step 5: Commit + report + ledger + memory**

Commit message verbatim (above). Report (append to `task-AS-report.md`): fix diff summary, gate evidence (A green, B green, 4 MD5s, matrix, self-compile), commit. Ledger + mnemoria (bugfix).

---

### Task I-C: pin the TCO back-edge mis-emission (read-only)

**Files:**
- Report: `.superpowers/sdd/task-TCO-report.md` (gitignored; append per task)

**Interfaces:**
- Consumes: the C finding (reference emits `goto z_bb_0;` for self-recursion; zig1_5 emits a real recursive call); design §Background C leads.
- Produces: pinned single-locus root cause file:line for the TCO gap, OR STOP-present if broad class.

- [ ] **Step 1: Reproduce + capture**

Build `tco_factorial` (`examples/z98/tco_factorial/main.zig`), `tco_return_try`, `tco_defer` with reference and with rebuilt `/tmp/zig1_5/zig1_5_clean`; capture outputs + rc. Confirm: ref emits `goto z_bb_0;` in `fact`/`count`/`countDown`, zig1_5 emits recursive calls; `tco_return_try` z5 rc=139, ref rc=0; `tco_defer` z5 prints ~100013 `D`, ref prints 3.

- [ ] **Step 2: Verify already-verified-correct emission (do not re-derive)**

Confirmed correct in the self-emission (design §Background): `findTailCall` tag ordinals (call=14, call_direct=23, unwrap_error_payload=34, unwrap_error_code=35, wrap_error_ok=32), the return_stmt TCO condition (`ci.is_self == 1 and ci.args_count == params.len`), `defer_bb_unchanged`, the `?CallInfo` has_value unwrap, `@enumToInt` no-op passthrough (`lower.zig:3286-3291`). Re-verify ONLY if the fix attempt later contradicts them.

- [ ] **Step 3: Focus on the remaining suspects**

Pin which of these mis-emits (diff `/tmp/zig1_5/gen/lower_*.c` against the `sf/src/lower.zig` semantics, and against the reference compiler's behavior by running instrumented/probe programs):
1. `hasOtherConsumers` (`lower.zig:5776-5851`) — if it returns true for the tail call's result, the TCO branch is skipped (empty `{}` at `:5094-5096`). Check its emitted branch conditions, especially the multi-branch `else if (tg == @enumToInt(LirInst.X))` dispatch and any `call_result` comparison.
2. `?CallInfo` optional return construction in `findTailCall` — the `CallInfo{…}` aggregate with `is_self`, `args_count`, `call_block_idx` etc.; verify the optional wrapper (`has_value`/`value`) is emitted correctly.
3. The `hops`/`found_any` scan loop in `findTailCall` (block/inst iteration, `break` semantics, `cur` chaining).
4. `expandDefers` / `defer_bb_unchanged` bookkeeping for the `countDown` (defer) case.
5. Any temp/instruction ordering that makes `hasOtherConsumers(self, ci.result, val)` see the call result as consumed.

- [ ] **Step 4: Single-locus vs broad class**

Single pin-able emission defect → pin F-C locus with exact file:line + emission shape. Broad class → STOP-present (do not fix piecemeal).

- [ ] **Step 5: Report + ledger + memory**

Append to `.superpowers/sdd/task-TCO-report.md`: repro outputs, suspects examined, pinned locus (or STOP), proof. Ledger + mnemoria (discovery).

---

### Task F-C: apply the pinned TCO fix

**Files:**
- Modify: the pinned `sf/src/*.zig` locus from I-C
- Commit: `fix: self-emitted compiler emits the TCO self-recursion back-edge` (adjust wording to actual locus)

**Interfaces:**
- Consumes: I-C pinned locus.
- Produces: `tco_return_try` rc=0 matching ref; `tco_defer` output byte-equal to ref; `tco_factorial` unchanged; 4 MD5s byte-identical; matrix 21/21; self-compile 0 errors.

- [ ] **Step 1: Apply the fix**

Per I-C's pinned locus, modify the single `sf/src` file. Z98-clean. Do NOT chase additional defects if I-C STOP applied.

- [ ] **Step 2: Gate verification**

Rebuild zig1 (repo root; reinstall std) + zig1_5. C fixtures: `tco_return_try` reference rc=0 unchanged AND self-compiled rc=0 (was 139); `tco_defer` self-compiled output byte-equal to reference; `tco_factorial` both rc=0 unchanged. 4 MD5s byte-identical. Matrix 21/21. Self-compile re-count 0 errors.

- [ ] **Step 3: Commit + report + ledger + memory**

Commit message verbatim (above). Report (append to `task-TCO-report.md`): fix summary, gate evidence, commit. Ledger + mnemoria (bugfix).

---

### Task GATE-FINAL: full sweep + reconciliation

**Files:**
- Modify: `EXPECTED_FAIL.md` (record the `@as` (A+B) + TCO (C) residuals as CLOSED with F-AS/F-C SHAs), `QUICK_REF.md` (new baseline paragraph)
- Commit: `docs: @as + TCO self-emission plan GATE + reconciliation`

**Interfaces:**
- Consumes: F-AS + F-C states; sweep harness; corpus/z98 expectations.
- Produces: measured GATE evidence; residuals reconciled; docs updated.

- [ ] **Step 1: 4 MD5 gates**

Repo-root CWD, `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 <entry> | md5sum` for gol/lisp/json/mud — all four MATCH the authoritative values (see Global Constraints).

- [ ] **Step 2: Matrix + corpus + examples sweep**

Matrix 21/21 (dump/gcc/link rc=0). Full runtime sweep with `/tmp/zig1_5/zig1_5_clean` vs reference over: `repro/mi_matrix/` 329 dirs, top-level `repro/*/` 53 dirs, `examples/z98/*/` 21 dirs (entry = `main.zig` else `<dirname>.zig`). Classification: RUN_OK (output+rc == ref), RUN_TIMEOUT (servers, both compilers), expected DUMP_FAIL (10 documented green-guards), LINK_FAIL (extern-dependent — reference also fails to link), garbage-print dirs (`voiddecl_payload_xmod`, `emission_void_temp_enum_xmod` — output non-deterministic by design), and any residual. Expected post-fix: the former 4 GCC_FAIL A-dirs, `fn_ptr_struct_field`, `quicksort`, `func_ptr_return` all RUN_OK; `tco_return_try` RUN_OK rc=0; `tco_defer` matches ref. Any NEW FAIL/ICE/CRASH not in the expected set → STOP-present.

- [ ] **Step 3: Self-compile**

`timeout 900 bash scripts/self_compile/build_zig1_5.sh`; verify 40 `.c`, 0 `error[`, 0 PANIC; rebuilt `zig1_5_clean` runs the R-A/R-B/C fixtures green.

- [ ] **Step 4: Reconcile docs**

EXPECTED_FAIL.md: record the `@as` root cause (A+B) + TCO (C) as CLOSED with F-AS/F-C SHAs; correct the stale `emission_void_call_xmod` "expected gcc error (class 5)" note if it now compiles clean (historical-snapshot convention: supersede, do not rewrite). QUICK_REF.md: new newest-first baseline paragraph (post-plan) with the sweep numbers; refresh corpus-gate header.

- [ ] **Step 5: Report + ledger + memory**

Report to `.superpowers/sdd/task-GATEFINAL-report.md`: all gate evidence, sweep table, reconciliation, commit. Ledger + mnemoria (success/pattern).
