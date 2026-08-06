# Compiler Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve four open compiler items: the `@intCast` range-check gap, the ICE on literals >= 2^32, full Z98 varargs support, and the lisp first-class-closures bug.

**Architecture:** Four independent items in one plan. Compiler items use the proven I-task (investigation → operator ruling) → F-task cadence; the two root-proven items (ICE marker, lisp closures) go straight to F-tasks. Varargs is the largest item (3 investigations + 3 fixes). Lisp closures is a lisp-SOURCE fix scheduled last.

**Tech Stack:** Z98 (zig0 → zig1 → gcc -m32 -std=c89)

## Global Constraints

- Build in /tmp via the QUICK_REF bootstrap recipe (NOT `sf/build/out_release/` — timeouts):
  ```bash
  OUT=/tmp/zigaps
  rm -rf "$OUT" && mkdir -p "$OUT"
  ./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
  gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
  ```
  Gate: 0 gcc errors (`error:` count == 0).
- 4 MD5 baselines byte-identical throughout unless an operator-approved re-baseline (F-5 AMENDMENT B precedent — runtime is the gate): mud `4644ad1349c55af80fa1a18fe0e17989`, gol `e2f4c62515b4ab5e5c5b1202f7c2e12e`, lisp `dd56cd23984d2533eebd244ffe593791`, json `900cb401779aab11bcf22ce35100323c`
- Corpus baseline: 206 repros, **OK=198/FAIL=4/green-guards=4** (raw 8). FAIL count must not increase. The varargs repro `fn_varargs_unsupported` flips FAIL→OK. 2 new repros (intcast, ICE) must be OK.
- test_analyzer_bin PASS. build_test.sh identical to baseline (5/4).
- fastedit/edit only for source edits. Read region before each edit. Bottom-to-top. NO scope creep.
- QUICK_REF.md reference mandatory for all gates.
- zig0 is a BLACK-BOX oracle for varargs: feed it a program, observe emitted C. NEVER read zig0 internals (its codegen is legacy/unmaintainable — has a "lifter" and other legacy structures).

---

### Task I1: Investigate @intCast range-check emission

**Files:** investigation → `.superpowers/sdd/I-intcast-range-report.md`; no source changes.

**Interfaces:**
- Produces: recommended fix site (lower.zig vs c89_emit) with exact file:line, the blast radius (which of the 4 MD5 gates use narrowing @intCast), and A/B/C options for F1.

- [ ] **Step 1: Confirm the gap**

Build `/tmp/zigaps/zig1`. Create and run a probe:
```zig
extern fn print_int(v: i32) void;
pub fn main() void {
    var i: i64 = 2147483647;
    i = i + 1;
    print_int(@intCast(i32, i));
}
```
Compile+run (link `sf/src/include/zig_runtime.c` + `zig_pal.c`). Expected pre-fix: prints garbage (overflow wraps) with rc=0. Grep emitted C for `(int)zT_` — confirm NO `__bootstrap_i32_from_i64` call is emitted.

- [ ] **Step 2: Trace the @intCast path**

Read `sf/src/lower.zig` `@intCast` handler (~line 2456-2520). Confirm how the cast is lowered today (raw C cast vs helper call). Read `sf/src/comptime_eval.zig` comptime `@intCast` path — confirm comptime-folded consts are value-checked already (they don't need runtime range checks).

- [ ] **Step 3: Check the bootstrap helpers**

Read `sf/src/include/zig_runtime.h` — confirm the `__bootstrap_DSTTYPE_from_SRCTYPE` inline helpers exist (e.g. `__bootstrap_i32_from_i64` at ~line 99-180), what pairs they cover, and the panic message convention (`__bootstrap_panic("integer cast overflow", ...)`).

- [ ] **Step 4: A/B/C options with blast radius**

Options for F1:
- **A:** Lowerer emits `call_direct` to `__bootstrap_DST_from_SRC` for narrowing @intCast (runtime values only)
- **B:** c89_emit wraps the cast in the helper call at emission time
- **C:** Leave as-is (reject — the gap is a real miscompile, lisp fact-13 proves it)

For each: which MD5 gates use narrowing @intCast on runtime values (lisp uses eval math — likely changes), blast radius, risk. Recommend one.

- [ ] **Step 5: Report + STOP**

Write `.superpowers/sdd/I-intcast-range-report.md` with the confirmed gap, trace, helper inventory, options, blast radius, and recommendation. STOP for operator ruling on the fix site before F1.

---

### Task F1: Implement @intCast range-check (Option B + scope b)

**Files:** `sf/src/lower.zig`, `sf/src/c89_emit.zig`, `sf/src/include/zig_runtime.h`, `sf/src/include/zig_runtime.c` + create `repro/mi_matrix/intcast_range_check/` + `repro/mi_matrix/EXPECTED_FAIL.md`

**Interfaces:**
- Consumes: I1 report (`.superpowers/sdd/I-intcast-range-report.md`) + operator ruling.
- Produces: `@intCast` narrowing AND same-width-reinterpret casts emit range-checked `__bootstrap_*_from_*` helper calls (scope b, full oracle semantics). Repro `intcast_range_check` classified OK + runtime panic.

**Operator ruling (I1, 2026-08-06):** Fix site = **Option B** (c89_emit wrap via the existing `int_cast.is_checked` field + source-aware per-pair `__bootstrap_<DST>_from_<SRC>` naming — proper architecture: LIR carries the backend-neutral "checked cast" semantic, lowerer marks narrowing/reinterpret casts, emitter implements for C89). Scope = **(b) full oracle rule**: check iff target_bits < source_bits (narrowing) OR target_bits == source_bits with signedness difference (reinterpret); pure widening → raw cast. All 4 MD5 gates re-baseline, runtime-verified (F-5 AMENDMENT B precedent).

- [ ] **Step 1: Write the failing repro**

`repro/mi_matrix/intcast_range_check/main.zig`:
```zig
extern fn __bootstrap_print_int(v: i32) void;
pub fn main() void {
    var i: i64 = 2147483647;
    i = i + 1;
    __bootstrap_print_int(@intCast(i32, i));
}
```
Verify the print idiom matches the corpus (I1 confirmed `extern fn __bootstrap_print_int(v: i32) void;` is the working idiom). The KEY property: a runtime i64 value that overflows i32 range narrows via @intCast.

- [ ] **Step 2: Run repro — verify it does NOT panic today**

Pre-fix: dump rc=0, gcc-clean, run prints `-2147483648` (wrapped), rc=0. Document in NOTES.md as the bug.

- [ ] **Step 3: Add the 19 `__bootstrap_*_from_*` helpers to the sf runtime**

In `sf/src/include/zig_runtime.c` (linkable) add all 19 per-pair signed-aware helpers from the oracle header (I1 report §3 table, lines 96-185 of `src/include/zig_runtime.h`): `usize_from_i64`, `i32_from_u32`, `u32_from_u64`, `u32_from_i32`, `usize_from_i32`, `i32_from_usize`, `u8_from_usize`, `u8_from_bool`, `f32_from_f64`, `i32_from_u8`, `u8_from_i32`, `u8_from_u32`, `u16_from_i32`, `u32_from_i64`, `u64_from_i64`, `i8_from_i32`, `i16_from_i32`, `i32_from_i64`, `c_char_from_u8`. Declare them in `sf/src/include/zig_runtime.h` (the emitted C `#include`s this — confirmed at mud emitted C line 52). Use `__bootstrap_panic(msg, __FILE__, __LINE__)`. Standardize the panic message to `"integer cast overflow in @intCast"` (message text is not gated). NOTE: the existing `std_checked_cast_*` family is NOT to be used — it is upper-bound-only and false-panics on in-range negatives (verified I1 §3).

- [ ] **Step 4: Wire `is_checked` in the lowerer**

In `sf/src/lower.zig:2603-2607` (the explicit `@intCast` handler): compute the source type via `getTempType(self, val_temp)` (lower.zig:824-831); set `is_checked = 1` when (src_bits > dst_bits) OR (src_bits == dst_bits AND signedness differs), else 0. The comptime branch (lower.zig:2540-2562) is untouched — comptime-folded consts are value-checked at fold time and skip the runtime cast. Pure-widening casts keep `is_checked = 0`.

- [ ] **Step 5: Emit source-aware helper in c89_emit**

In `sf/src/c89_emit.zig:4137-4171` (the `.int_cast` arm checked branch): replace target-only `getCheckedCastFnName(reg, c.target)` (c89_emit.zig:2856-2868 → the `std_checked_cast_*` family) with a source-aware `__bootstrap_<DST>_from_<SRC>` name built from `c.target` + `getTempTypeByIndex(emitter, c.value)` (c89_emit.zig:731-738). Reuse the existing `dst = fn(src);` emission shape verbatim. The checked branch becomes live; the raw `dst = (ctype)src;` path stays for `is_checked == 0`.

- [ ] **Step 6: Verify the repro panics**

Post-fix: repro links with `zig_runtime.c` (which now provides the helpers), runs and PANICS with `integer cast overflow in @intCast` → nonzero exit. Dump rc=0, gcc-clean.

- [ ] **Step 7: Gate sweep + re-baseline (scope b)**

Build 0 gcc errors. 4 MD5s — ALL 4 re-baseline (scope b: mud 5 sites, gol 4, lisp 5, json 1). Verify each runtime-identical EXCEPT lisp `(fact 13)` which now PANICS (the intended fix): mud (rc=124, listens :4000), gol (glider, 100 gen), lisp `(+ 1 2)` → 3 + full runtime battery, json (parses test.json). Update QUICK_REF.md MD5 table with new values + re-baseline note (F-5 AMENDMENT B). Corpus: 206→207, `intcast_range_check` OK, no FAIL increase. Add EXPECTED_FAIL.md row.

- [ ] **Step 8: Commit**

```bash
git add sf/src/lower.zig sf/src/c89_emit.zig sf/src/include/zig_runtime.h sf/src/include/zig_runtime.c repro/mi_matrix/intcast_range_check/ repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "fix: @intCast narrowing + reinterpret emits range-checked helper (intcast_range_check)"
```

---

### Task F2: Fix ICE on literal >= 2^32 (u64-safe marker)

**Files:** Modify `sf/src/pal.zig`, `sf/src/lower.zig:1105`; create `repro/mi_matrix/ice_literal_overflow/` + `repro/mi_matrix/EXPECTED_FAIL.md`

**Interfaces:**
- Consumes: nothing (root cause proven).
- Produces: `pal.markerWriteInt64(prefix: []const u8, value: u64)`; lower.zig:1105 uses it. Repro `ice_literal_overflow` OK.

- [ ] **Step 1: Write the failing repro**

`repro/mi_matrix/ice_literal_overflow/main.zig`:
```zig
pub const X: u64 = 5000000000;
pub const Y: u64 = 4294967296;
extern fn print_u64(v: u64) void;
pub fn main() void {
    print_u64(X);
    print_u64(Y);
}
```
Verify the print idiom matches corpus convention (e.g. `@cInclude`+`extern fn printf` with `%lu`, or a two-half split like F7's repro). Pre-fix: `zig1 --dump-c89` → dump rc=134 SIGABRT (compiler panics on the literal).

- [ ] **Step 2: Add `markerWriteInt64` to pal.zig**

Mirror `markerWriteInt` (pal.zig:131-142), using `itoa64` (itoa.zig:19) and a `[24]u8` buffer (u64 max = 20 digits + NUL + room):
```zig
pub fn markerWriteInt64(prefix: []const u8, value: u64) void {
    if (g_markers_enabled != @intCast(u32, 0)) {
        var s_p: []const u8 = prefix;
        markerWrite(s_p);
        var buf: [24]u8 = undefined;
        var vlen = itoa_mod.itoa64(value, buf[0..]);
        var start: usize = @intCast(usize, 24) - @intCast(usize, vlen) - @intCast(usize, 1);
        markerWrite(buf[start..@intCast(usize, 23)]);
        var s_nl: []const u8 = "\n";
        markerWrite(s_nl);
    }
}
```
Verify `itoa_mod` is already imported in pal.zig (it is, line 123).

- [ ] **Step 3: Fix lower.zig:1105**

Replace the `@intCast(u32, val)` inline-itoa marker at lower.zig:1105 with `pal.markerWriteInt64` (or inline `itoa64` on a `[22]u8` buffer). The marker prints the literal value; it must handle u64 without truncating. If using the marker directly, replace lines 1103-1105 pattern. Keep the surrounding `ILR:i`/`v`/`R`/`M` marker structure intact.

- [ ] **Step 4: Verify repro dumps clean**

Post-fix: `zig1 --dump-c89` on the repro → dump rc=0, emitted C has `zG_..._X` = 5000000000, gcc-clean, runs printing 50000000004294967296 (or per print idiom).

- [ ] **Step 5: Gate sweep + commit**

Build 0 err. 4 MD5s byte-identical (markers → stderr only; emitted C unchanged). Corpus: 207→208, `ice_literal_overflow` OK. EXPECTED_FAIL.md row.

```bash
git add sf/src/pal.zig sf/src/lower.zig repro/mi_matrix/ice_literal_overflow/ repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "fix: u64-safe marker for int_literal (ICE on literal >= 2^32)"
```

---

### Task I2: Investigate varargs — parser + oracle

**Files:** investigation → `.superpowers/sdd/I-varargs-parser-report.md`; no source changes.

**Interfaces:**
- Consumes: nothing.
- Produces: zig0's emitted C for a varargs extern fn (the target form), zig1 parser change sites for `...` acceptance, A/B/C options for F3.

- [ ] **Step 1: Oracle — what does zig0 emit?**

Build/use `sf/build/zig0`. Feed it:
```zig
extern fn printf(fmt: [*]const u8, ...) void;
```
Observe the emitted C forward-declaration for `printf`. Document exactly: does it carry `...`? What is the param type for `fmt`? This is the target C form.

- [ ] **Step 2: Oracle — Z98 varargs fn**

Feed zig0 a Z98 fn with `...` body (if zig0 accepts it):
```zig
fn sum(count: u32, ...) i32 { return 0; }
```
Document whether zig0 accepts it, and if so what C it emits (va_list preamble?).

- [ ] **Step 3: zig1 parser sites**

Read `sf/src/parser.zig` — `parserParseFnDecl` (~:1050-1100), `parserParseParamDeclList`, and the param parsing loop. Locate exactly where a `...` token would need to be accepted and what AST node/flag must record it. Check: does `fn_type` (parser.zig:991-1022) also need varargs? Are there existing fn-flag bits free?

- [ ] **Step 4: A/B/C options**

- **A:** Parser-only `...` acceptance for extern fns (declaration-only; Z98 varargs bodies unsupported — REJECTED per operator: "accepts but produces nothing useful is worse")
- **B:** Full: parser `...` + AST flag + c89_emit `...` in decl + extern fns callable (Tier A)
- **C:** Full Tier B: B + LIR va_* instructions + @cVaStart/@cVaArg/@cVaEnd builtins + Z98 varargs fn bodies

Recommend C (spec mandates full support). Provide the file:line for each sub-piece.

- [ ] **Step 5: Report + STOP**

Write `.superpowers/sdd/I-varargs-parser-report.md`. STOP for operator ruling before I3.

---

### Task I3: Investigate varargs — sema + LIR design ✅ COMPLETE (report .superpowers/sdd/I-varargs-lir-report.md; design FROZEN in AMENDMENT 2, operator ruling: Option B + C validation/repros folded in)

**Files:** investigation → `.superpowers/sdd/I-varargs-lir-report.md`; no source changes.

**Interfaces:**
- Consumes: I2 ruling (full support = Tier C confirmed).
- Produces: LIR va_* instruction layout (mirror the TCO `tail_call` precedent), sema validation rules, A/B/C for F4.

- [ ] **Step 1: LIR variant design**

Read `sf/src/lir.zig` union (~:22-77). Design the backend-neutral va_* instructions, mirroring how `tail_call` was added (lir.zig:46 — after `call_direct`, 8-field struct). Propose:
- `va_start: struct { va_list_temp: u32, fn_decl_temp: u32 }`
- `va_arg: struct { va_list_temp: u32, type_id: u32, result: u32 }`
- `va_end: struct { va_list_temp: u32 }`

Check every switch on LirInst (lower.zig, c89_emit.zig — ~4 sites) for the else=>{} arms that must gain the new cases (mirror the tail_call precedent: decl_local dedup, written_type scan, emitInst dispatcher, hoisted decl_local emission).

- [ ] **Step 2: AST representation**

How does the parser record `...` (I2)? Is it a flag on fn_decl, or a special child? Define the AST contract F3 produces and F4 consumes.

- [ ] **Step 3: Sema validation rules**

Where in `semantic_analyzer.zig` is fn signature validated? What checks for `...`: trailing position only, fixed params typed normally, not allowed in fn_ptr types. Define exact rejection diagnostics (which error[NNNN] code — follow existing conventions).

- [ ] **Step 4: va_list type**

How is `va_list` represented in the type registry? Options: a builtin `va_list` type (like `C_CHAR`), or a pointer to an opaque struct. Define the type + how `@cVaStart`'s argument is typed. Check c89_emit's type-emission needs (`stdarg.h` include).

- [ ] **Step 5: Report + STOP**

Write `.superpowers/sdd/I-varargs-lir-report.md` with the LIR layout, switch-arm inventory, sema rules, va_list type design, blast radius, and A/B/C. STOP for operator ruling before I4.

---

### Task I4: Investigate varargs — lowerer + c89_emit translation

**Files:** investigation → `.superpowers/sdd/I-varargs-emit-report.md`; no source changes.

**Interfaces:**
- Consumes: I3 frozen design (AMENDMENT 2) — LIR va_* layout, va_list type, flag contract already decided. F3/F4/F5 task splits are FROZEN (F3 parser+flag, F4 LIR+va_list+sema, F5 builtins+emitter+repros).
- Produces: exact lowerer builtin-dispatch mapping (@cVaStart/@cVaArg/@cVaEnd → va_* LIR) and the concrete c89_emit translation (va_* LIR → C `va_start`/`va_arg`/`va_end`, `#include <stdarg.h>` gating, `...` in fn prototypes, extern prototype emission), A/B/C if any refinement is needed for F5. STOP for operator ruling.

- [ ] **Step 1: Builtin wiring**

Read how existing builtins (`@intCast`, `@sizeOf`) are wired: parser `builtin_call` → lowerer dispatch (lower.zig:2456). Design `@cVaStart(&va_list)` / `@cVaArg(&va_list, T)` / `@cVaEnd(&va_list)` dispatch: builtin name lookup + arg lowering → va_* LIR emission.

- [ ] **Step 2: c89_emit translation**

Read `sf/src/c89_emit.zig` emitInst. Design the translation:
- `va_start` → `va_start(zT_n, <last_fixed_param>);` (C89 requires the last named param)
- `va_arg` → `zT_n = va_arg(zT_va, <ctype>);`
- `va_end` → `va_end(zT_va);`
- `stdarg.h` include at top of emitted files for varargs fns (or unconditionally — check blast radius)

- [ ] **Step 3: Fn declaration emission**

Where are fn prototypes emitted (c89_emit.zig emitFunctionForwardDecls / header pass ~:2057-2062)? Add `...` for varargs fns. For extern fns, the mangled name passes through as-is (extern naming precedent).

- [ ] **Step 4: Oracle verification plan**

Define the exact oracle-comparison gates: zig0's `printf` callable form vs zig1's (should match), and a Z98 varargs fn body (zig0 may not support — zig1 is the extension).

- [ ] **Step 5: Report + STOP**

Write `.superpowers/sdd/I-varargs-emit-report.md`. STOP for operator ruling on the F3+F4+F5 task split (likely F3=parser+AST, F4=sema+LIR, F5=builtins+lowerer+emitter).

---

### Task F3: Varargs — parser `...` acceptance + FnPayload flag threading

**Files:** `sf/src/parser.zig` (+ `sf/src/type_resolver.zig`, `sf/src/type_registry.zig`, `sf/src/semantic_analyzer.zig` for FnPayload threading)

**Interfaces:**
- Consumes: I3 frozen design (AMENDMENT 2) — Option F flag bit; I4 split refinement (AMENDMENT 3) — lowerFn flag-read is F5's job, not F3's.
- Produces: fn_decl records varargs via **flags bit0 (0x01)**; `FnPayload.flags_packed` written; `extern fn printf(fmt: [*]const u8, ...) void;` parses clean and the fn type carries `is_variadic`. The lowerer's flag-read (lower.zig:4647) is explicitly DEFERRED to F5.

- [ ] **Step 1: Implement parser `...` (flag bit, no marker param)**

In `parserParseFnDecl`'s param loop (`parser.zig:1371-1381`), branch on `parserPeek().kind == TokenKind.dot_dot_dot`: consume the token; set **bit0 (`0x01`) on the fn_decl node's `flags` byte**; `break` out of the loop (structural trailing-only — `fn(a, ..., b)` yields a `,` where `)` is expected → error[2000]); do NOT append a param node; `params_count` stays exact. Verify `FnProto` struct unchanged (ast_tests.zig:54 12-byte assertion preserved). bit0 = `is_const`, never set for fn_decl (parser uses only 0x02 pub / 0x04 extern / 0x20 test at parser.zig:1363-1365).

Also reject `...` in `parserParseFnType` (fn-ptr types, `parser.zig:1006-1017`): targeted `error[2000]` "varargs not allowed in function pointer types".

- [ ] **Step 2: Thread flag through fn-type creation**

`resolveFnSignatures` (`type_resolver.zig:1098-1149`): read `decl.flags & 0x01` → pass new `is_variadic` arg to `typeRegistryGetOrCreateFn` (type_registry.zig:497-518) → writes `FnPayload.flags_packed` (currently hard-coded 0 at type_registry.zig:508). Add the same arg at all 6 `typeRegistryGetOrCreateFn` sema call sites (semantic_analyzer.zig:310/320/326/410/418/423), passing the flag (0 for non-fn-decl construction). Rework the pre-wired marker-param site in the TYPE RESOLVER ONLY: drop the `else { xtAppend(TYPE_VOID) }` phantom for a `child_0==0` param at `type_resolver.zig:1139-1140`. (The lower.zig:4680 marker-param detection is left for F5 per AMENDMENT 3 — the lowerer flag-read belongs with the va_* producers.)

- [ ] **Step 3: Verify `fn_varargs_unsupported` parses**

`zig1 --dump-c89` on `repro/mi_matrix/fn_varargs_unsupported/main.zig` → dump rc=0 (was error[2000]), emitted C has the extern fn declaration. (Emission of `...` in the C decl may still be pending F5 — if the decl lacks `...` the C is still valid, just not variadic; document the intermediate state.) Also correct `fn_varargs_unsupported/NOTES.md` — its claim "zig0 accepts varargs" is FALSE (zig0 rejects all varargs forms).

- [ ] **Step 4: Gate + commit**

Build 0 err. 4 MD5s byte-identical (no baseline has a variadic fn; flag threading is write-only for non-variadic). Corpus: `fn_varargs_unsupported` behavior recorded (may still be FAIL until F5; document). Commit:
```bash
git add sf/src/parser.zig sf/src/type_resolver.zig sf/src/type_registry.zig sf/src/semantic_analyzer.zig sf/src/lower.zig
git commit -m "feat: parser accepts varargs ... + FnPayload is_variadic flag (fn_varargs_unsupported)"
```

---

### Task F4: Varargs — sema call-site fix + LIR va_* instructions + va_list type

**Files:** `sf/src/lir.zig`, `sf/src/c89_emit.zig`, `sf/src/type_registry.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/diagnostics.zig`

**Interfaces:**
- Consumes: I3 frozen design (AMENDMENT 2); F3's FnPayload flag.
- Produces: va_* LIR variants + switch arms; sema variadic-aware call typing; va_list builtin type; ERR_3012.

- [ ] **Step 1: LIR union extension**

Add to `lir.zig` after `call_direct` (lir.zig:45), mirroring `tail_call`:
```zig
va_start: struct { va_list_temp: u32, last_param_temp: u32 },
va_arg:   struct { va_list_temp: u32, type_id: u32, result: u32 },
va_end:   struct { va_list_temp: u32 },
```
Add matching cases to the 4 LirInst switches (all in c89_emit.zig):
- `:2362` decl_local dedup scan — explicit no-op arms `.va_start/.va_arg/.va_end => {}` (else covers; precedent)
- `:2403` written_type scan — REQUIRED: `.va_arg => |va|` sets `written_type[va.result]=va.type_id`, `written_flag=1`; `.va_start => |vs|` sets `written_type[vs.va_list_temp]=TYPE_VA_LIST`, `written_flag=1`; `.va_end => {}`
- `:2938` emitInst dispatcher — REQUIRED: 3 emitting arms (emission deferred to F5; empty bodies OK at F4 to keep build green)
- `:4554` hoisted decl_local scan — explicit no-op arms (else covers; precedent)

- [ ] **Step 2: va_list builtin type**

In `type_registry.zig`: append `TypeKind.va_list_type` at enum end (`:40-56`, after anon_union); add `TYPE_VA_LIST: TypeId = 21` (`:29`, after TYPE_TYPE=20); `registerPrimitive(self, TypeKind.va_list_type, 4, 4)` after type_type (`:600`) + `registerPrimitiveName(self, 21, "va_list")` (`:618`). NO keyword (resolves via nameCache). In `c89_emit.zig` `getCTypeName` (`:527+`): `if (ty.kind == TypeKind.va_list_type) { var s: []const u8 = "va_list"; return s; }` placed with the primitive arms (after c_char, `:557`).

- [ ] **Step 3: Sema call-site + validation**

Replace the hard `args.len != pcount` early-return (`semantic_analyzer.zig:759`) with:
```zig
var fixed = fnp.params_count;
if (isVariadic(fnp)) {
    if (args.len < fixed) return fnp.return_type;
    // type args[0..fixed] against xt[params_start..+fixed] (existing loop body)
    // resolve args[fixed..] with expected type 0 (generic) — new loop
} else if (args.len != pcount) {
    return fnp.return_type;
}
```
Add `ERR_3012_VARARGS_INVALID = 3012` to `diagnostics.zig` (explicit `= 3012`, next free after 3011, before 3048). Use it for: variadic fn with zero fixed params, `@cVaStart` outside a variadic fn. (The lowerer has `self.func.is_variadic` for the body check.)

- [ ] **Step 4: Gate + commit**

Build 0 err. **4 MD5s: re-baseline per AMENDMENT 4** — mud `e306b1874e51e06a23b708bcd79fec6d`, lisp `55044a1f64011bc644cddbcf73b5de93`, json `b5f56ebd51d2f0fcd379a1e083594462` (drift from the va_list primitive user-type-id shift, runtime byte-identical — controller-verified), gol stays `51d6d078bdecad022318bded23182f72`. Corpus unchanged. Commit:
```bash
git add sf/src/lir.zig sf/src/c89_emit.zig sf/src/type_registry.zig sf/src/semantic_analyzer.zig sf/src/diagnostics.zig
git commit -m "feat: va_list type + LIR va_start/va_arg/va_end + variadic call typing"
```

---

### Task F5: Varargs — builtins + lowerer + emitter translation + extern prototypes

**Files:** `sf/src/lower.zig`, `sf/src/c89_emit.zig`

**Interfaces:**
- Consumes: I3+I4 frozen design (AMENDMENTS 2+3); F3's flag; F4's va_* LIR + va_list type + ERR_3012.
- Produces: `@cVaStart/@cVaArg/@cVaEnd` working end-to-end; `extern fn printf` callable; Z98 varargs fn bodies access args. **stdarg.h gated on is_variadic** (3 sites). **Extern prototypes for variadic externs only (Option B)**. **lowerFn flag-read** (lower.zig:4647) wired.

- [ ] **Step 1: lowerFn is_variadic flag read**

In `lowerFn`, read the fn type's `FnPayload.flags_packed` (from `resolvedTypeTableGet(..., fn_node)` → fn_items[payload_idx].flags_packed, or the fn_decl node flag bit) and set `func_ptr.is_variadic` (lower.zig:4647). The existing `child_0==0` marker branch at lower.zig:4680 becomes a defensive no-op (per AMENDMENT 2).

- [ ] **Step 2: Builtin dispatch (lowerer, builtin branch `lower.zig:2543`)**

Insert after `@ptrToInt` check (:2545), BEFORE the `ec.len>=2` cast block (:2590) — else `@cVaArg`'s type arg mis-lowers:
- `@cVaStart(&vl)` → `va_start` inst. If arg is `AstKind.address_of`, unwrap one level to the base va_list temp (`findLocalTemp` of the inner ident). `last_param_temp = self.func.params[self.func.params.len-1].temp_id`. Guard `self.func.is_variadic` else ERR_3012.
- `@cVaArg(vl, T)` → `va_arg` inst with `result = nextTemp(resolveTypeExprFull(T))`.
- `@cVaEnd(vl)` → `va_end` inst.
Name_ids interned in `lowererInit` (:257-298).

- [ ] **Step 3: Emitter translation (c89_emit emitInst, next to `.tail_call` `:4042`)**

```c
va_start(zT_3, zL_fmt);   // .va_start arm  (va_list_temp name, last_param_temp name)
zT_5 = va_arg(zT_3, int); // .va_arg arm    (result = va_arg(vl, CType from type_id))
va_end(zT_3);             // .va_end arm
```
Names resolve via `fl_temps` (params pre-registered c89_emit:2341-2352, locals :2380). va_arg result is a hoisted temp → auto-declared via the existing hoisted-decl pass + F4's getCTypeName va_list arm.

- [ ] **Step 4: stdarg.h gating**

Add `#include <stdarg.h>` gated on **any `fns[i].is_variadic` in the TU** at THREE sites: `emitModuleHeader` (c89_emit:1937, after zig_compat/special_types includes), `emitModuleHeaderFile` (:2038), `emitModuleFile` (:2267). Gating keeps all 4 MD5 gates byte-identical.

- [ ] **Step 5: Extern prototypes (Option B — variadic-only)**

Add name-passthrough to `emitFunctionForwardDecl` (:1898-1900). Change the guards at :1962 and :2108 from `is_extern==0` to `is_extern==0 OR is_variadic!=0` — so ONLY variadic externs get C prototypes (all-externs Option A rejected: breaks json). Zero blast radius (no gate has a variadic extern).

- [ ] **Step 6: Z98 varargs fn repro**

Create `repro/mi_matrix/fn_varargs_body/main.zig` — a variadic fn with `@cVaArg` reading args. **CRITICAL: do NOT `@cInclude("<stdio.h>")` when declaring variadic `extern fn printf`** (type conflict: `unsigned char const*` vs stdio's `const char*`). Use the corpus fixed-arity print idiom for output:
```zig
extern fn printf(fmt: [*]const u8, ...) i32;
fn sum(count: u32, ...) i32 {
    var vl: va_list = undefined;
    @cVaStart(&vl);
    var total: i32 = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        total += @cVaArg(&vl, i32);
    }
    @cVaEnd(&vl);
    return total;
}
pub fn main() void {
    var s: i32 = sum(3, 10, 20, 30);
    // print s via a fixed-arity non-varargs extern (e.g. __bootstrap_print_int or a %d print)
}
```
(Adjust to corpus print idiom; the KEY proof is `sum(3, 10, 20, 30)` returning 60 via @cVaArg.) Verify: dumps rc=0, gcc-clean, runs printing 60.

- [ ] **Step 7: Gate sweep**

Build 0 err. `fn_varargs_unsupported` FAIL→OK (dump rc=0, gcc-clean, callable). `fn_varargs_body` OK (variadic body reads args). 4 MD5s byte-identical (stdarg.h gated; no baseline has variadic fns). Corpus: 208→210, +2 OK, FAIL 4→3. Update `fn_varargs_unsupported/NOTES.md` (correct the FALSE "zig0 accepts varargs" claim), EXPECTED_FAIL.md rows.

- [ ] **Step 8: Commit**

```bash
git add sf/src/lower.zig sf/src/c89_emit.zig repro/mi_matrix/fn_varargs_body/ repro/mi_matrix/fn_varargs_unsupported/ repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "feat: full varargs support (@cVaStart/@cVaArg/@cVaEnd + va_list emission)"
```

---

### Task F6: Fix lisp first-class closures (last)

**Files:** Modify `examples/z98/lisp_interpreter_curr/eval.zig:124`

**Interfaces:**
- Consumes: nothing (root cause proven).
- Produces: closures capture the current dynamic env; `((make-adder 5) 3)` → 8.

- [ ] **Step 1: The one-line fix**

In `eval.zig:124`, change:
```zig
const env_val = try env_to_value(env.*, temp_sand, perm_sand);
```
to:
```zig
const env_val = try env_to_value(curr_env.*, temp_sand, perm_sand);
```
Verify `curr_env` is in scope at that point (read the enclosing function's parameters — it is the lambda-eval path). If `curr_env` is named differently (e.g. `current_env`), use the actual parameter name.

- [ ] **Step 2: Verify closures work**

Rebuild the lisp example with `/tmp/zigaps/zig1`. Feed:
```
((make-adder 5) 3)
(define add5 (make-adder 5))
(add5 3)
```
Expected: `8` and `8` (was `UnboundSymbol`).

- [ ] **Step 3: Regression — 73-expression battery**

Run the arithmetic/define/recursion/conditionals/TCO/lists battery (the `.superpowers/sdd/lisp-curr-runtime-test.md` set). All previously-passing expressions must still pass.

- [ ] **Step 4: Re-baseline lisp MD5 + commit**

The lisp MD5 gate changes (eval.zig is part of the multi-file build). Re-baseline per F-5 AMENDMENT B precedent; verify runtime correctness is the gate. Update `docs/sf/QUICK_REF.md` lisp MD5 + a note. Commit:
```bash
git add examples/z98/lisp_interpreter_curr/eval.zig docs/sf/QUICK_REF.md
git commit -m "fix: lisp closures capture current env (eval.zig curr_env)"
```

---

### Task F7: Gate sweep + docs + final review prep

**Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, tech docs (per AGENTS §1.1.1)

**Interfaces:**
- Consumes: all completed fixes.
- Produces: final corpus accounting, MD5 table, updated tech docs.

- [ ] **Step 1: Full corpus sweep**

Run the corpus classifier (QUICK_REF corpus gate recipe). Record final accounting. Expected: 210 repros, OK=200/FAIL=3/gg=4 (raw 7) — FAILs = field_store_drop, test_stub_0, self_embed_optional_cycle (varargs repro rescued).

- [ ] **Step 2: MD5 gate**

Verify 4 MD5s (or re-baselined values). Document any re-baseline with runtime verification.

- [ ] **Step 3: Tech docs**

Update the affected tech docs per AGENTS §1.1.1: 07_lir_lowering.md (va_* instructions), 08_c89_emission.md (va_list/va_start emission + @intCast range-check), 05_semantic_analysis.md (varargs validation), 04_comptime_eval.md (if changed), 09_pipeline_orchestration.md (if changed). Add `[updated: 2026-08-06]` annotations.

- [ ] **Step 4: Update EXPECTED_FAIL.md + QUICK_REF.md**

Clear the 4 item rows (intcast, ICE, varargs, + note lisp closure fix in the example NOTES). Update corpus baseline + MD5 table.

- [ ] **Step 5: Commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md sf/docs/tech_docs/ examples/z98/lisp_interpreter_curr/NOTES.md
git commit -m "docs: gate sweep + tech docs for 4-item compiler gaps plan"
```

---

## Amendments Record

- **AMENDMENT 0 (2026-08-06):** Plan structure finalized from brainstorm. I-tasks for @intCast (I1) and varargs (I2/I3/I4); F-only for ICE marker (F2) and lisp closures (F6, last). Varargs is full Tier-B support (multi-backend, not C89-delegated) per operator. zig0 is a black-box oracle only for varargs emission — never read zig0 internals.
- **AMENDMENT 1 (2026-08-06, operator ruling on I1):** F1 fix site = **Option B** (c89_emit wrap via existing `int_cast.is_checked` + source-aware `__bootstrap_<DST>_from_<SRC>` naming), NOT the plan's original Option A (lowerer `call_direct`). Rationale: proper architecture — the LIR carries the backend-neutral "checked cast" semantic; lowerer marks narrowing/reinterpret casts; emitter implements for C89. `call_direct` would bake a C-specific runtime function name into the backend-neutral LIR. Scope = **(b) full oracle rule** (narrowing OR same-width-reinterpret; pure widening → raw cast). All 4 MD5 gates re-baseline, runtime-verified (F-5 AMENDMENT B precedent). F1 rewritten with 8 concrete steps (19 helpers to sf runtime, lower.zig is_checked wiring, c89_emit source-aware checked branch).
- **AMENDMENT 2 (2026-08-06, operator ruling on I3):** Varargs design FROZEN per I3 report (`.superpowers/sdd/I-varargs-lir-report.md`). Operator confirmed **Option B (full support) + C validation/repros folded in**, and the design as upstream-correct. Binding decisions:
  - **AST = Option F (fn_decl flag bit0/0x01)** on `dot_dot_dot`; NO marker param; `FnProto` unchanged (12B). `FnPayload.flags_packed` (type_registry.zig:77) written via new `typeRegistryGetOrCreateFn` is_variadic arg threaded through 6 sema sites (310/320/326/410/418/423) + type_resolver:1144. Reworks the pre-wired marker-param sites (type_resolver:1139-1140, lower.zig:4680) to read the flag.
  - **LIR va_* layout** (after `call_direct`, lir.zig:45): `va_start {va_list_temp, last_param_temp}`, `va_arg {va_list_temp, type_id, result}`, `va_end {va_list_temp}`. Exactly 4 LirInst switches, all in c89_emit.zig (2362, 2403, 2938, 4554); lower.zig emitInst is a plain append (no switch). Required arms: written_type scan (va_arg/va_start set written_type, va_end no-op) + emitInst dispatcher (3 emitting arms).
  - **va_list = builtin `TYPE_VA_LIST = 21`**, `TypeKind.va_list_type` appended at enum end, size/align 4, C name `va_list` via registerPrimitiveName/nameCache (NO keyword), `getCTypeName` arm in c89_emit. `stdarg.h` include gated on `fns[i].is_variadic` in emitModuleHeader + emitModuleFile → **4 MD5 gates unchanged, no re-baseline**.
  - **Sema:** replace `args.len != pcount` early-return (semantic_analyzer.zig:759) with `args.len < fixed` guard + generic resolve of extras. New `ERR_3012_VARARGS_INVALID = 3012` for: zero-fixed-param variadic fn, `@cVaStart` outside variadic body. `...` in fn_ptr rejected at parser level (error[2000]).
  - F3 = parser flag + FnPayload threading; F4 = LIR + va_list type + sema fix; F5 = builtins + emitter translation + repros. Task splits frozen as below.
- **AMENDMENT 3 (2026-08-06, operator ruling on I4):** Varargs lowerer/emitter design FROZEN per I4 report (`.superpowers/sdd/I-varargs-emit-report.md`). Binding decisions:
  - **Builtin dispatch:** `@cVa*` at lower.zig:2543 builtin branch, inserted after `@ptrToInt` (:2545) and BEFORE the `ec.len>=2` cast block (:2590, else `@cVaArg`'s type arg mis-lowers). Name_ids interned in lowererInit (:257-298). `@cVaStart(&vl)` unwraps `address_of` → lower inner ident → `findLocalTemp`; `last_param_temp = self.func.params[len-1].temp_id`; guard on `self.func.is_variadic`.
  - **Emitter arms:** 3 arms next to `.tail_call` (c89_emit:4042-4087): `va_start(<vl>, <last>);`, `<result> = va_arg(<vl>, <CType>);`, `va_end(<vl>);`. Names resolve via `fl_temps` (params pre-registered :2341-2352, locals :2380). va_arg result is a hoisted temp → auto-declared.
  - **stdarg.h gating:** gate on `any fns[i].is_variadic` in emitModuleHeader (:1937), emitModuleHeaderFile (:2038), emitModuleFile (:2267). Zero byte change on 4 gates.
  - **Extern prototypes = Option B (variadic-only):** add name-passthrough to `emitFunctionForwardDecl` (:1898-1900); change guards :1962/:2108 to `is_extern==0 OR is_variadic!=0`. Option A (all externs) REJECTED — breaks json hard (fopen `?*File`→`Opt_` struct vs stdio.h `FILE*` = gcc error, json `@cInclude`s stdio.h). Zero blast radius (no gate has a variadic extern).
  - **Split refinement:** the `lowerFn` is_variadic-from-flag read (lower.zig:4647) is an **F5 lowerer change**, NOT F3 (the flag must be consumed by the lowerer alongside the va_* producers). F4's sema:759 fix is only for fn-ptr varargs (direct variadic calls already work) — non-blocking.
  - **Repro constraint:** variadic extern + `@cInclude`'d same header conflicts (printf `unsigned char const*` vs `const char*`) — F5 repros must NOT `@cInclude stdio.h` for variadic printf.
- **AMENDMENT 4 (2026-08-06, operator ruling on F4):** The F4-mandated eager `registerPrimitive(va_list_type)` shifts every user type id +1 (sequential ids at type_registry.zig:157), leaking into mangled C type names → 3 of 4 MD5 gates drift (mud `0064a081`→`e306b1874e51e06a23b708bcd79fec6d`, lisp `e54be381`→`55044a1f64011bc644cddbcf73b5de93`, json `6528f26f`→`b5f56ebd51d2f0fcd379a1e083594462`; gol `51d6d078bdecad022318bded23182f72` coincidentally unchanged). Operator ruling: **"only rebase if runtime behavior is the same."** Controller independently verified ALL 4 gate runtimes are byte-identical F4 vs pristine (mud rc=124 listening, gol rc=0 glider gen-99, lisp `(+ 1 2)`→3, json parses test.json — md5s of captured outputs identical per pair). **Re-baseline authorized**: new MD5 gates mud `e306b1874e51e06a23b708bcd79fec6d`, lisp `55044a1f64011bc644cddbcf73b5de93`, json `b5f56ebd51d2f0fcd379a1e083594462`, gol stays `51d6d078bdecad022318bded23182f72`. (Re-baseline recorded at F4 commit b8deb732; QUICK_REF table updated in F7.) I3's claim "Primitive TypeIds 1-20 stable" was technically true (ids 1-20 unchanged) but the user-type START shifted — corrected understanding recorded here.
