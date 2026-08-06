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

### Task I3: Investigate varargs — sema + LIR design

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
- Consumes: I3 LIR layout + va_list type design.
- Produces: exact lowerer mapping (builtins → va_* LIR) and c89_emit translation (va_* LIR → `va_start`/`va_arg`/`va_end`), A/B/C for F5.

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

### Task F3: Varargs — parser `...` acceptance + AST flag

**Files:** per I2 ruling (`sf/src/parser.zig`, possibly `sf/src/ast.zig`) + repro `fn_varargs_unsupported` already exists.

**Interfaces:**
- Consumes: I2 report (parser sites + oracle C form).
- Produces: fn_decl AST records varargs; `extern fn printf(fmt: [*]const u8, ...) void;` parses clean.

- [ ] **Step 1: Implement parser `...`**

Apply the operator-approved parser change: accept `...` as a trailing pseudo-parameter in `parserParseFnDecl` param lists. Set the varargs flag on the fn_decl AST node (per I2/I3 AST contract). Applies to both `extern fn` and Z98 `fn`.

- [ ] **Step 2: Verify `fn_varargs_unsupported` parses**

`zig1 --dump-c89` on `repro/mi_matrix/fn_varargs_unsupported/main.zig` → dump rc=0 (was error[2000]), emitted C has the extern fn declaration. (Emission of `...` in the C decl may still be pending F5 — check: if the decl lacks `...` the C is still valid, just not variadic. Document the intermediate state.)

- [ ] **Step 3: Gate + commit**

Build 0 err. 4 MD5s byte-identical (no baseline uses varargs). Corpus: `fn_varargs_unsupported` behavior recorded (may still be FAIL until F5 if gcc rejects; document). Commit:
```bash
git add sf/src/parser.zig [sf/src/ast.zig]
git commit -m "feat: parser accepts varargs ... in fn declarations"
```

---

### Task F4: Varargs — sema validation + LIR va_* instructions

**Files:** per I3 ruling (`sf/src/semantic_analyzer.zig`, `sf/src/lir.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`)

**Interfaces:**
- Consumes: I3 LIR layout + va_list type design; F3's AST varargs flag.
- Produces: va_* LIR variants + their switch arms; sema validation of `...`; va_list type in registry.

- [ ] **Step 1: LIR union extension**

Add `va_start`/`va_arg`/`va_end` to `lir.zig` union per I3 layout. Add the matching cases to every LirInst switch (decl_local dedup, written_type scan, emitInst dispatcher, hoisted decl_local emission — mirror the tail_call precedent). Empty/neutral arms where translation is deferred to F5.

- [ ] **Step 2: Sema validation**

In `semantic_analyzer.zig`, validate `...` (trailing-only; fixed params typed normally; reject in fn_ptr types). Use the existing diagnostic pattern (error[2000] family or a specific code per I3).

- [ ] **Step 3: va_list type**

Register the `va_list` type (per I3 design) in `type_registry.zig` + `c89_emit.zig` type emission (map to C `va_list`).

- [ ] **Step 4: Gate + commit**

Build 0 err. 4 MD5s byte-identical (neutral arms). Corpus unchanged. Commit:
```bash
git add sf/src/lir.zig sf/src/semantic_analyzer.zig sf/src/type_registry.zig sf/src/c89_emit.zig
git commit -m "feat: va_list type + LIR va_start/va_arg/va_end instructions"
```

---

### Task F5: Varargs — builtins + lowerer + emitter translation

**Files:** per I4 ruling (`sf/src/lower.zig`, `sf/src/c89_emit.zig`)

**Interfaces:**
- Consumes: I4 translation design; F4's va_* LIR + va_list type; F3's parser flag.
- Produces: `@cVaStart/@cVaArg/@cVaEnd` builtins working end-to-end; `extern fn printf` callable with variadic args; Z98 varargs fn bodies access args.

- [ ] **Step 1: Builtin dispatch**

Wire `@cVaStart(&vl)` / `@cVaArg(&vl, T)` / `@cVaEnd(&vl)` in the lowerer builtin dispatch (mirror `@intCast` handling). Lower to va_* LIR instructions.

- [ ] **Step 2: Emitter translation**

In c89_emit.zig, translate va_* LIR → `va_start(zT, last_param)` / `va_arg(zT, ctype)` / `va_end(zT)`. Add `#include <stdarg.h>` for varargs fns. Emit `...` in fn prototypes (forward decls + headers).

- [ ] **Step 3: Z98 varargs fn repro**

Create `repro/mi_matrix/fn_varargs_body/main.zig`:
```zig
extern fn printf(fmt: [*]const u8) i32;
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
    printf("sum=%d\n" +% 0);
}
```
(Adjust to corpus print idiom.) Verify: dumps rc=0, gcc-clean, runs printing the computed sum with variadic args.

- [ ] **Step 4: Gate sweep**

Build 0 err. `fn_varargs_unsupported` FAIL→OK (dump rc=0, gcc-clean, callable). `fn_varargs_body` OK. 4 MD5s — assess blast radius (no baseline uses varargs; expect byte-identical). Corpus: 208→210, +2 OK, FAIL 4→3.

- [ ] **Step 5: Commit**

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
