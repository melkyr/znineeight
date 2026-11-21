# Tagged-Union `==` Binary Emission Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tagged-union comparison (`s == Shape.Circle`) emit valid C that compiles and runs, superseding the zig0 oracle per operator ruling m0471 (Option A).

**Architecture:** Single emitter fix in the `.binary` handler — append `.tag` to tagged-union-typed operands for `BIN_EQ`/`BIN_NE`. Lowerer + sema already correct. One F-task, runtime-gated.

**Tech Stack:** Z98 compiler (`sf/src/c89_emit.zig`), zig1 (`sf/build/out_release/zig1`), gcc -m32 C89, repro `tagged_union_cmp_xmod/`, tech doc `08_c89_emission.md`.

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-60) is MANDATORY before any build/compile/run. Copy the exact commands; do not improvise flags.
- **Compiler under test:** `sf/build/out_release/zig1`. Build: `bash sf/scripts/build_release.sh`, gate on `=== [release] Done: sf/build/out_release/zig1 ===`.
- **Compile recipe:** `mkdir -p DIR && sf/build/out_release/zig1 --dump-c89 --output-dir DIR <main.zig> 2>/tmp/err` (multi-module) or `--dump-c89 <FILE.zig> > /tmp/x.c` (single). gcc: `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c *.c` then link with `zig_runtime.c zig_pal.c`.
- **RUNTIME gate mandatory** (AGENTS §2.5.3): the fixed repro must run rc=0 AND print the expected output. Compile-only gates are FORBIDDEN.
- **4 MD5 gates** byte-identical: mud `6c0a83f117f176f6875ce2c18c761890`, gol `0d8f0092c22c04375482a198691a3957`, lisp `a12f2fcebc30f2d8c2a148facb9d1174` (post-F1 re-baseline), json `c403f0799dbc5c56d548eee07bb9eebd`.
- **zig0 oracle is SUPERSEDED for this construct** (operator ruling m0471) — zig1 emits valid C where zig0 rejects. Do NOT gate on zig0 for union `==`.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; bottom-to-top). NO sed/python bulk transforms. NO scope creep.
- **The plan is the ONLY authority.** Plan says A → do A. On any issue, STOP.

---

### Task F: Fix tagged-union `==`/`!=` binary emission (Option A — emitter)

**Files:**
- Modify: `sf/src/c89_emit.zig` (`.binary` handler at `:3708-3744`)
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md`
- Test: `repro/mi_matrix/tagged_union_cmp_xmod/`

**Interfaces:**
- Consumes: repro `tagged_union_cmp_xmod/` (committed 119fda14), F6 fix (efbf4807 — lowerer already produces correct BIN_EQ operands).
- Produces: `s == Shape.Circle` emits `s.tag == <rhs>.tag` (valid C); repro runs printing `1`.

**Context:** The `.binary` handler (c89_emit.zig:3708-3744) is type-unaware — emits `result = lhs op rhs;` for all ops. For tagged-union operands (C struct with `.tag` + union payload) this is gcc-invalid. The fix: for `BIN_EQ` (10) / `BIN_NE` (11), resolve each operand's temp type; if `tagged_union_type`, append `.tag` to the emitted name. Valid Zig semantics: union `==` compares the active tags. Precedent: `.tag` access at c89_emit.zig:3441-3443 (load_field) and :3762-3784 (int_const init); temp-type lookup loop at :3768-3779.

- [ ] **Step 1: Verify red state**

Run `tagged_union_cmp_xmod/`: dump rc=0, then gcc compile → confirm rc≠0 with `error: invalid operands to binary ==`. Record the emitted C (`result = s == t;` with both operands union structs).

- [ ] **Step 2: Read the `.binary` handler `c89_emit.zig:3708-3744`**

Read the region. Identify: `resolveTempName` for result/lhs/rhs, `getBinOpStr(b.op)`, and the emission block. Also read `:3762-3784` (int_const tagged-union handling) and `:3768-3779` (the temp-type lookup loop) — you will mirror its pattern.

- [ ] **Step 3: Implement the fix**

In the `.binary` handler, after the `rhs = resolveTempName(...)` call and before the emission block, add the tagged-union suffix detection:

```zig
var lhs_tag: []const u8 = "";
var rhs_tag: []const u8 = "";
if (b.op == @intCast(u8, 10) or b.op == @intCast(u8, 11)) { // BIN_EQ, BIN_NE
    var ht_i: usize = 0;
    while (ht_i < emitter.current_fn.hoisted_temps.len) : (ht_i += 1) {
        var ht = emitter.current_fn.hoisted_temps.items[ht_i];
        if (ht.temp_id == b.lhs and ht.type_id != type_mod.TYPE_UNDEFINED) {
            var lty = emitter.registry.types_items[@intCast(usize, ht.type_id)];
            if (lty.kind == TypeKind.tagged_union_type) { lhs_tag = ".tag"; }
        }
        if (ht.temp_id == b.rhs and ht.type_id != type_mod.TYPE_UNDEFINED) {
            var rty = emitter.registry.types_items[@intCast(usize, ht.type_id)];
            if (rty.kind == TypeKind.tagged_union_type) { rhs_tag = ".tag"; }
        }
    }
}
```

Then emit the suffix after each operand name in the emission block (after `bufferedWriterWrite(&emitter.writer, lhs);` add `if (lhs_tag.len > 0) { bufferedWriterWrite(&emitter.writer, lhs_tag); }`, same for rhs). Verify the actual constant names (`BIN_EQ`, `TypeKind`, `hoisted_temps`, `types_items`) match the source — read the surrounding code first; adapt identifiers to the exact names used in this file. Do NOT change other ops' behavior.

- [ ] **Step 4: Build + verify repro green**

Rebuild: `bash sf/scripts/build_release.sh` (gate on the Done line). Run `tagged_union_cmp_xmod/`: dump rc=0, gcc compile rc=0, link rc=0, run rc=0 printing `1`. Inspect emitted C: `zT_result = zT_s.tag == zT_rhs.tag;`. Also verify a same-module union `==` variant emits `s.tag ==` (create a throwaway /tmp test if needed).

- [ ] **Step 5: Verify no regression + 4 MD5 gates**

F3 repros (`zT_missing_fwd_xmod/`, `examples/z98/json_parser_workaround/` gcc-clean) still green. 4 MD5 gates byte-identical (mud `6c0a83f1…`, gol `0d8f0092…`, lisp `a12f2fce…`, json `c403f079…`). test_analyzer_bin PASS.

- [ ] **Step 6: Update tech doc `08_c89_emission.md` to FIXED**

Document the `.binary` handler's tagged-union `.tag` emission for `==`/`!=`, corrected refs, `[updated: 2026-08-08]`. Note the zig0 oracle is superseded for this construct (operator ruling m0471).

- [ ] **Step 7: Commit**

```bash
git add sf/src/c89_emit.zig sf/docs/tech_docs/08_c89_emission.md
git commit -m "fix: tagged-union == and != emit valid C (tagged_union_cmp_xmod)"
```

**Gate:** repro dump/gcc/run rc=0 printing `1`; emitted C has `.tag` suffix; same-module union `==` gcc-clean; F3 repros still green; 4 MD5s byte-identical; test_analyzer_bin PASS; tech doc updated.
