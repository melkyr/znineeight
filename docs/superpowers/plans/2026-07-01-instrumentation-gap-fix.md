# Instrumentation-Prove-Fix: Void-Payload & Literal-as-Temp Pipeline Gaps

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add diagnostic markers to prove root causes of 3 gap categories in C89 emission pipeline (void-payload compound types, void-typed variables, literal-as-temp in for-loops), then apply minimum fixes verified against existing and new extension repros. Final gates: all 10 repros 0 gcc errors, json_parser 0 gcc errors, baseline examples byte-identical.

**Architecture:** Instrumentation-first approach — zni-0003 lesson applied. Add marker calls at candidate code paths using existing `pal_mod.markerWrite` infrastructure, run repros with `--markers`, capture stderr output, confirm exact code path and type values before applying any fix. Fixes are minimum 1-2 line guards at proven locations. No refactoring, no cleanup, no speculative changes.

**Tech Stack:** zig0 C89 bootstrap compiler (Z98 dialect), marker infrastructure (pal_mod.markerWrite, itoa_mod.itoa)

---

## Global Constraints

- NO fix applied without marker proof of root cause
- Existing marker infrastructure only — `pal_mod.markerWrite`, `itoa_mod.itoa`
- Each fix is minimum viable (no refactoring, no cleanup, no extra guards)
- Z98 string literal rule: named `var` for each literal passed to function arguments
- All markers use distinct, grep-able prefixes (`INSTA:` for Cat 1, `INSTB:` for Cat 2, `INSTC:` for Cat 3)
- Build: `./sf/build/zig0 --header-priority-include -o $OUT/zig1.c sf/src/main.zig` then `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration $OUT/*.c -o $OUT/zig1`
- Manual edits only (no sed/python/replace-all)
- `fastedit` per AGENTS.md X.7: re-read region before every edit; edit bottom-to-top
- Gate: All repros (single + cross-module) produce ONLY targeted errors after instrumentation, 0 errors after fixes
- Gate: json_parser 0 gcc errors
- Gate: Baseline examples (mandelbrot, game_of_life, mud_server) byte-identical after all changes
- Stop on any gate failure, present results, do not continue without authorization
- NO compression during build sessions

---

## File Structure

| File | Change | Purpose |
|------|--------|---------|
| `repro/optional_void/main.zig` | Create | Repro for `?void` type gaps O1-O3 |
| `repro/tu_void_prong/main.zig` | Create | Repro for TU void-payload prong gaps T1-T3 |
| `repro_xmod/optional_void/main.zig` + `lib.zig` | Create | Cross-module optional void |
| `repro_xmod/tu_void_prong/main.zig` + `lib.zig` | Create | Cross-module TU void prong |
| `sf/src/c89_emit.zig` | Modify | Instrumentation markers + void-payload fixes |
| `sf/src/lower.zig` | Modify | Instrumentation markers + void-temp fix + literal fix |

---

## Gap Inventory

### Category 1: Void-payload compound types

| ID | Type | Gap | File:line |
|----|------|-----|-----------|
| A1 | `!void` unwrap | `unwrap_error_payload` always emits `.data.payload` | `c89_emit.zig:3105` |
| A2 | `!void` unwrap | `unwrap_error_code` always emits `.data.err` | `c89_emit.zig:3116` |
| O1 | `?void` type | `emitOptionalType` emits `void value;` in struct | `c89_emit.zig:1223` |
| O2 | `?void` wrap | `wrap_optional` emits `.value` void access | `c89_emit.zig:2942` |
| O3 | `?void` unwrap | `unwrap_optional` emits `.value` void access | `c89_emit.zig:3191` |
| T1 | TU void prong | `load_field` void result → `void zT_N = base.payload` | `c89_emit.zig:2390` |
| T2 | TU void prong | lowerer switch capture → void-typed temp | `lower.zig:2311` |
| T3 | TU void prong | Hoisted temp decl `void zT_N;` | `c89_emit.zig:1993` |

### Category 2: Void-typed variable/temp creation

| ID | Source | File:line |
|----|--------|-----------|
| V1 | `var x = voidFn()` | `lower.zig:3128,3133-3134` |
| V2 | `@enumToInt` fallback | `lower.zig:1825` |
| V3 | `builtin_call` fallback | `lower.zig:1914` |
| V4 | Empty `tuple_literal` | `lower.zig:2193` |
| V5 | Switch result void | `lower.zig:2232-2233` |
| V6 | Hoisted temp emission | `c89_emit.zig:1961-2000` |
| V7 | decl_local emission | `c89_emit.zig:3261-3290` |

### Category 3: Literal-as-temp in for-loop

| ID | Source | File:line |
|----|--------|-----------|
| L1 | For-range increment | `lower.zig:2886` |
| L2 | For-slice increment | `lower.zig:2921` |

---

## Repro Coverage Matrix

| Gap ID | Single-file Reproducer | Cross-module Reproducer |
|--------|----------------------|------------------------|
| A1, A2 | `repro/eu_void_payload/` ✓ | `repro_xmod/eu_void_payload/` ✓ |
| O1-O3 | `repro/optional_void/` (NEW) | `repro_xmod/optional_void/` (NEW) |
| T1-T3 | `repro/tu_void_prong/` (NEW) | `repro_xmod/tu_void_prong/` (NEW) |
| V1-V5 | `repro/var_declared_void/` ✓ | `repro_xmod/var_declared_void/` ✓ |
| L1, L2 | `repro/tagged_field_path/` ✓ | `repro_xmod/tagged_field_path/` ✓ |

---

## New Repro Programs

### `repro/optional_void/main.zig`

```zig
pub fn main() void {
    var opt: ?void = null;
    if (opt) |v| {
        _ = v;
    }
}
```

### `repro/tu_void_prong/main.zig`

```zig
const MyUnion = union(enum) {
    Empty: void,
    Value: i32,
};

pub fn main() void {
    var u: MyUnion = undefined;
    switch (u) {
        .Empty => |x| {
            _ = x;
        },
        .Value => |n| {
            _ = n;
        },
    }
}
```

### `repro_xmod/optional_void/lib.zig`

```zig
pub fn getOpt() ?void {
    return null;
}
```

### `repro_xmod/optional_void/main.zig`

```zig
const lib = @import("lib.zig");

pub fn main() void {
    var opt = lib.getOpt();
    if (opt) |v| {
        _ = v;
    }
}
```

### `repro_xmod/tu_void_prong/lib.zig`

```zig
pub const MyUnion = union(enum) {
    Empty: void,
    Value: i32,
};
```

### `repro_xmod/tu_void_prong/main.zig`

```zig
const lib = @import("lib.zig");

pub fn main() void {
    var u: lib.MyUnion = undefined;
    switch (u) {
        .Empty => |x| {
            _ = x;
        },
        .Value => |n| {
            _ = n;
        },
    }
}
```

---

### Task 0: Add extension repros

**Files:**
- Create: `repro/optional_void/main.zig`
- Create: `repro/tu_void_prong/main.zig`
- Create: `repro_xmod/optional_void/main.zig` + `repro_xmod/optional_void/lib.zig`
- Create: `repro_xmod/tu_void_prong/main.zig` + `repro_xmod/tu_void_prong/lib.zig`

**Interfaces:**
- Consumes: zig1 binary built from HEAD (commit 9c40be74)
- Produces: 4 new repro programs under repro/ and repro_xmod/

- [ ] **Step 1: Write repro files** — use exact code from the New Repro Programs section above.

- [ ] **Step 2: Build zig1 and verify each repro produces errors**

```bash
OUT=/tmp/zptr_inst && rm -rf $OUT && mkdir -p $OUT
./sf/build/zig0 --header-priority-include -o $OUT/zig1.c sf/src/main.zig 2>&1 >/dev/null
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration $OUT/*.c -o $OUT/zig1 2>&1 | grep -c 'error:'
# Expected: 0

for DIR in repro/optional_void repro/tu_void_prong repro_xmod/optional_void repro_xmod/tu_void_prong; do
  echo "=== $DIR ===" &&
  $OUT/zig1 --dump-c89 $DIR/main.zig > /tmp/inst_$(basename $DIR).c 2>/dev/null &&
  gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/inst_$(basename $DIR).c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/inst_$(basename $DIR) 2>&1 | grep 'error:' | sed 's/.*error: //' | sort -u
done
```

Expected: Each repro produces >= 1 gcc error matching its gap category.

- [ ] **Step 3: Commit**

```bash
git add repro/ repro_xmod/
git commit -m "feat: add extension repros for optional-void and tu-void-prong gaps"
```

---

### Task 1: Instrument Category 1 — void-payload compound types

**Files:**
- Modify: `sf/src/c89_emit.zig:1223-1254` (emitOptionalType)
- Modify: `sf/src/c89_emit.zig:3097-3107` (unwrap_error_payload)
- Modify: `sf/src/c89_emit.zig:3108-3118` (unwrap_error_code)
- Modify: `sf/src/c89_emit.zig:3191-3201` (unwrap_optional)
- Modify: `sf/src/c89_emit.zig:2942-2956` (wrap_optional)
- Modify: `sf/src/c89_emit.zig:2390-2418` (load_field tagged_union)

**Interfaces:**
- Consumes: Type registry (type items, EU items, opt items, TU items)
- Produces: Markers `INSTA:eup<tid>`, `INSTA:euc<tid>`, `INSTA:optt<tid>`, `INSTA:optw<tid>`, `INSTA:optu<tid>`, `INSTA:tulf<tid>` on stderr via `--markers`

- [ ] **Step 1: Read current code at all target locations**

Read each location: `sf/src/c89_emit.zig:1220-1260`, `sf/src/c89_emit.zig:3090-3120`, `sf/src/c89_emit.zig:3180-3210`, `sf/src/c89_emit.zig:2940-2960`, `sf/src/c89_emit.zig:2385-2425`.

- [ ] **Step 2: Add marker at emitOptionalType (line 1225)**

After the `opt` variable is set (payload extracted), insert:

```zig
var insta_ot_m: []const u8 = "INSTA:optt"; pal_mod.markerWrite(insta_ot_m);
var insta_ot_b: [10]u8 = undefined; var insta_ot_l = itoa_mod.itoa(opt.payload, insta_ot_b[0..]); var insta_ot_s: usize = @intCast(usize, 9) - @intCast(usize, insta_ot_l); pal_mod.markerWrite(insta_ot_b[insta_ot_s..@intCast(usize, 9)]);
var insta_ot_n: []const u8 = "\n"; pal_mod.markerWrite(insta_ot_n);
```

This records the payload type_id — value 1 = TYPE_VOID = void-payload optional.

- [ ] **Step 3: Add marker at unwrap_error_payload (lines 3097-3107)**

At line 3099 (after extracting the instruction), add marker with the value temp's type:

Read the lines around the handler to find where the src temp type can be obtained. Add:

```zig
var insta_p_m: []const u8 = "INSTA:eup\n"; pal_mod.markerWrite(insta_p_m);
```

- [ ] **Step 4: Add marker at unwrap_error_code (lines 3108-3118)**

Same pattern:

```zig
var insta_c_m: []const u8 = "INSTA:euc\n"; pal_mod.markerWrite(insta_c_m);
```

- [ ] **Step 5: Add marker at unwrap_optional (line 3191)**

```zig
var insta_ou_m: []const u8 = "INSTA:optu\n"; pal_mod.markerWrite(insta_ou_m);
```

- [ ] **Step 6: Add marker at load_field tagged_union (line 2390)**

At line 2401 where `res_ty != TYPE_VOID` check exists, add marker for both branches:

```zig
var insta_lf_m: []const u8 = "INSTA:tulf"; pal_mod.markerWrite(insta_lf_m);
var insta_lf_b: [10]u8 = undefined; var insta_lf_l = itoa_mod.itoa(res_ty, insta_lf_b[0..]); var insta_lf_s: usize = @intCast(usize, 9) - @intCast(usize, insta_lf_l); pal_mod.markerWrite(insta_lf_b[insta_lf_s..@intCast(usize, 9)]);
var insta_lf_n: []const u8 = "\n"; pal_mod.markerWrite(insta_lf_n);
```

- [ ] **Step 7: Build and run repros with --markers**

```bash
OUT=/tmp/zptr_inst && rm -rf $OUT && mkdir -p $OUT
./sf/build/zig0 --header-priority-include -o $OUT/zig1.c sf/src/main.zig 2>&1 >/dev/null
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration $OUT/*.c -o $OUT/zig1 2>&1 | grep -c 'error:'
# Expected: 0

for DIR in repro/eu_void_payload repro/optional_void repro/tu_void_prong; do
  echo "=== $DIR ===" &&
  $OUT/zig1 --markers --dump-c89 $DIR/main.zig > /dev/null 2>/tmp/inst1_$(basename $DIR).txt &&
  grep "^INSTA:" /tmp/inst1_$(basename $DIR).txt
done
```

Expected: Each repro fires grep-able markers showing exact code path. `INSTA:optt<1>` confirms TYPE_VOID payload. `INSTA:tulf<1>` confirms void result in TU load_field.

- [ ] **Step 8: Commit**

```bash
git add sf/src/c89_emit.zig
git commit -m "inst: add Category 1 void-payload diagnostic markers (INSTA)"
```

---

### Task 2: Instrument Category 2 — void-typed variable/temp creation

**Files:**
- Modify: `sf/src/lower.zig:309-339` (nextTemp)
- Modify: `sf/src/lower.zig:3125-3135` (var_decl void)
- Modify: `sf/src/c89_emit.zig:1978-1999` (emitHoistedDecls)
- Modify: `sf/src/c89_emit.zig:3281-3289` (decl_local emission)

**Interfaces:**
- Consumes: nextTemp type_id parameter, resolved type table
- Produces: Markers `INSTB:nt<tid>`, `INSTB:vd`, `INSTB:ehd<tid>`, `INSTB:edl<tid>`

- [ ] **Step 1: Read current code at target locations**

Read: `sf/src/lower.zig:305-345`, `sf/src/lower.zig:3120-3140`, `sf/src/c89_emit.zig:1960-2005`, `sf/src/c89_emit.zig:3260-3295`.

- [ ] **Step 2: Add marker at nextTemp entry (line 316)**

After the existing `NXT:i` marker, add:

```zig
if (type_id == @intCast(u32, 1)) {
    var instb_nt_m: []const u8 = "INSTB:ntv\n"; pal_mod.markerWrite(instb_nt_m);
}
```

TYPE_VOID = 1 per `type_registry.zig:11`. Marker only fires when void type passes through.

- [ ] **Step 3: Add marker at var_decl void detection (line 3128)**

After `decl_type` is resolved, add:

```zig
if (decl_type == type_mod.TYPE_VOID) {
    var instb_vd_m: []const u8 = "INSTB:vd\n"; pal_mod.markerWrite(instb_vd_m);
}
```

- [ ] **Step 4: Add marker at emitHoistedDecls void temp (line 1978)**

After `c_type` is obtained from `getCTypeName`, add:

```zig
if (eff_type == @intCast(u32, 1)) {
    var instb_eh_m: []const u8 = "INSTB:ehd\n"; pal_mod.markerWrite(instb_eh_m);
}
```

- [ ] **Step 5: Add marker at decl_local void emission (line 3281)**

After `dl_type` is obtained, add:

```zig
if (dl.type_id == @intCast(u32, 1)) {
    var instb_ed_m: []const u8 = "INSTB:edl\n"; pal_mod.markerWrite(instb_ed_m);
}
```

- [ ] **Step 6: Build and run repros with --markers**

```bash
for DIR in repro/var_declared_void repro/optional_void repro/tu_void_prong; do
  echo "=== $DIR ===" &&
  $OUT/zig1 --markers --dump-c89 $DIR/main.zig > /dev/null 2>/tmp/inst2_$(basename $DIR).txt &&
  grep "^INSTB:" /tmp/inst2_$(basename $DIR).txt
done
```

Expected: `INSTB:ntv` confirms TYPE_VOID enters nextTemp. `INSTB:vd` fires at var_decl path. `INSTB:ehd`/`INSTB:edl` confirm void-typed C variable emission.

- [ ] **Step 7: Commit**

```bash
git add sf/src/lower.zig sf/src/c89_emit.zig
git commit -m "inst: add Category 2 void-typed-variable diagnostic markers (INSTB)"
```

---

### Task 3: Instrument Category 3 — literal-as-temp in for-loop

**Files:**
- Modify: `sf/src/lower.zig:2886,2921` (for-loop binary rhs)
- Modify: `sf/src/c89_emit.zig:2607-2608` (binary handler rhs)

**Interfaces:**
- Consumes: binary instruction `.rhs` field, for-loop index
- Produces: Markers `INSTC:flr`, `INSTC:fls`, `INSTC:brhs<value>`

- [ ] **Step 1: Read current code at target locations**

Read: `sf/src/lower.zig:2880-2895`, `sf/src/lower.zig:2915-2930`, `sf/src/c89_emit.zig:2595-2630`.

- [ ] **Step 2: Add marker at for-range increment (line 2886)**

Before the binary emit at line 2886, add a single-line marker:

```zig
var instc_fr_m: []const u8 = "INSTC:flr\n"; pal_mod.markerWrite(instc_fr_m);
```

- [ ] **Step 3: Add marker at for-slice increment (line 2921)**

```zig
var instc_fs_m: []const u8 = "INSTC:fls\n"; pal_mod.markerWrite(instc_fs_m);
```

- [ ] **Step 4: Add marker at binary emission rhs (line 2607)**

When `resolveTempName` is called on `b.rhs`, add marker if rhs is small (likely literal):

```zig
if (b.rhs < @intCast(u32, 1000) and b.rhs != @intCast(u32, 0)) {
    var instc_br_m: []const u8 = "INSTC:brhs"; pal_mod.markerWrite(instc_br_m);
    var instc_br_b: [10]u8 = undefined; var instc_br_l = itoa_mod.itoa(b.rhs, instc_br_b[0..]); var instc_br_s: usize = @intCast(usize, 9) - @intCast(usize, instc_br_l); pal_mod.markerWrite(instc_br_b[instc_br_s..@intCast(usize, 9)]);
    var instc_br_n: []const u8 = "\n"; pal_mod.markerWrite(instc_br_n);
}
```

- [ ] **Step 5: Build and run repros with --markers**

```bash
for DIR in repro/tagged_field_path repro_xmod/tagged_field_path; do
  echo "=== $DIR ===" &&
  $OUT/zig1 --markers --dump-c89 $DIR/main.zig > /dev/null 2>/tmp/inst3_$(basename $DIR).txt &&
  grep "^INSTC:" /tmp/inst3_$(basename $DIR).txt
done
```

Expected: `INSTC:fls` from lowerer for-loop, `INSTC:brhs1` from emitter — proves rhs value is literal `1` being resolved as temp ID (not a real temp).

- [ ] **Step 6: Commit**

```bash
git add sf/src/lower.zig sf/src/c89_emit.zig
git commit -m "inst: add Category 3 literal-as-temp diagnostic markers (INSTC)"
```

---

### Task 4: Fix Category 2 — void-typed variable guards

**Files:**
- Modify: `sf/src/lower.zig:3128`
- Modify: `sf/src/c89_emit.zig:1992-1999`
- Modify: `sf/src/c89_emit.zig:3284-3289`

**Fix: Add void type_id check at three points (minimum, proven by Task 2 INSTB markers)**

- [ ] **Step 1: Add void guard at var_decl in lower.zig:3128**

Read current line 3128 context. Change:

```zig
if (decl_type != type_mod.TYPE_UNDEFINED) {
```

To:

```zig
if (decl_type != type_mod.TYPE_UNDEFINED and decl_type != type_mod.TYPE_VOID) {
```

- [ ] **Step 2: Add void guard at emitHoistedDecls in c89_emit.zig**

At the point where temp declaration is emitted (around line 1992-1993), wrap in void check. Read exact context. The fix wraps the emission lines:

```zig
if (eff_type != @intCast(u32, 1)) {
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, c_type);
    var sp: []const u8 = " "; bufferedWriterWrite(&emitter.writer, sp);
    bufferedWriterWrite(&emitter.writer, tn);
    var sm: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, sm);
}
```

- [ ] **Step 3: Add void guard at decl_local in c89_emit.zig**

Same pattern — wrap the local variable declaration emission in `if (dl.type_id != @intCast(u32, 1))`.

- [ ] **Step 4: Build and verify Gap B repros + baselines**

```bash
OUT=/tmp/zptr_fix && rm -rf $OUT && mkdir -p $OUT
./sf/build/zig0 --header-priority-include -o $OUT/zig1.c sf/src/main.zig 2>&1 >/dev/null
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration $OUT/*.c -o $OUT/zig1 2>&1 | grep -c 'error:'
# Expected: 0

# Verify Gap B repro 0 errors
$OUT/zig1 --dump-c89 repro/var_declared_void/main.zig > /tmp/fix2_b.c 2>/dev/null
gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/fix2_b.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/fix2_b 2>&1 | grep -c 'error:'
# Expected: 0

# Cross-module B
$OUT/zig1 --dump-c89 repro_xmod/var_declared_void/main.zig > /tmp/fix2_bx.c 2>/dev/null
gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/fix2_bx.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/fix2_bx 2>&1 | grep -c 'error:'
# Expected: 0

# Baselines byte-identical
BASELINE_OUT=/tmp/zptr_5b_baseline
for EXAMPLE in mandelbrot game_of_life mud_server; do
  BASE=$($BASELINE_OUT/zig1 --dump-c89 examples/$EXAMPLE/main.zig 2>/dev/null | md5sum | awk '{print $1}')
  FIX=$($OUT/zig1 --dump-c89 examples/$EXAMPLE/main.zig 2>/dev/null | md5sum | awk '{print $1}')
  if [ "$BASE" = "$FIX" ]; then echo "$EXAMPLE: MATCH"; else echo "$EXAMPLE: DIFFER"; fi
done
# Expected: All MATCH
```

- [ ] **Step 5: Commit**

```bash
git add sf/src/lower.zig sf/src/c89_emit.zig
git commit -m "fix: skip void-typed variable declarations in lowerer and emitter (Gap B)"
```

---

### Task 5: Fix Category 1 — void-payload compound type guards

**Files:**
- Modify: `sf/src/c89_emit.zig:3097-3107` (unwrap_error_payload)
- Modify: `sf/src/c89_emit.zig:3108-3118` (unwrap_error_code)
- Modify: `sf/src/c89_emit.zig:1223-1254` (emitOptionalType)
- Modify: `sf/src/c89_emit.zig:3191-3201` (unwrap_optional)
- Modify: `sf/src/c89_emit.zig:2942-2956` (wrap_optional)
- Modify: `sf/src/c89_emit.zig:2390-2418` (load_field tagged_union)

**Fix: Add void-payload branching in emission paths (proven by Task 1 INSTA markers)**

- [ ] **Step 1: Fix unwrap_error_payload (line 3097-3107)**

The LIR instruction `.unwrap_error_payload` carries no type_id. Must look up source temp's type from emitter state. Read the handler context to find how to get the source type from `uep.value` temp. Add void check:

```zig
// Existing code emits: bufferedWriterWrite(&emitter.writer, ".data.payload;");
// Fix: check if source EU has void payload, emit ".err;" or ".is_error;" instead
var uep_src_tid = getTempTypeByIndex(emitter, uep.value);
if (uep_src_tid != 0xFFFFFFFF) {
    var uep_src_t = emitter.registry.types_items[@intCast(usize, uep_src_tid)];
    if (uep_src_t.kind == TypeKind.error_union_type) {
        var uep_pay = emitter.registry.eu_items[@intCast(usize, uep_src_t.payload_idx)].payload;
        var uep_pay_t = emitter.registry.types_items[@intCast(usize, uep_pay)];
        if (uep_pay_t.kind == TypeKind.void_type) {
            var uep_dot_m: []const u8 = ".err;\n"; bufferedWriterWrite(&emitter.writer, uep_dot_m);
        } else {
            var uep_dot_m: []const u8 = ".data.payload;\n"; bufferedWriterWrite(&emitter.writer, uep_dot_m);
        }
    }
} else {
    var uep_dot_m: []const u8 = ".data.payload;\n"; bufferedWriterWrite(&emitter.writer, uep_dot_m);
}
```

If `getTempTypeByIndex` does not exist, add it to c89_emit.zig as a function that looks up a temp's type from the emitter's `temp_types` or by indexing into the LIR function's temp list.

- [ ] **Step 2: Fix unwrap_error_code (line 3108-3118)** — Same pattern: emit `.err;` for void payload, `.data.err;` for non-void.

- [ ] **Step 3: Fix emitOptionalType (line 1223-1254)**

After the `opt` variable is obtained, check if payload is void_type. If void, skip struct emission (or emit alias typedef). Read existing code to find exact insertion point.

```zig
var pay_t = emitter.registry.types_items[@intCast(usize, opt.payload)];
if (pay_t.kind != TypeKind.void_type) {
    // existing emitOptionalType code (struct with value + has_value)
} else {
    // void payload: emit no struct, or emit dummy placeholder
}
```

- [ ] **Step 4: Fix wrap_optional (line 2942-2956)** — Add void check; for void payload, skip `.value` assignment, only set `.has_value`.

- [ ] **Step 5: Fix unwrap_optional (line 3191-3201)** — Add void check; for void payload, skip `.value` extraction.

- [ ] **Step 6: Fix load_field tagged_union (line 2390-2418)** — Already has `res_ty != TYPE_VOID` check at line 2401. For void results, skip variable declaration entirely (don't emit `zT_N = base.payload`).

- [ ] **Step 7: Build and verify all Cat 1 repros**

```bash
for DIR in repro/eu_void_payload repro/optional_void repro/tu_void_prong \
           repro_xmod/eu_void_payload repro_xmod/optional_void repro_xmod/tu_void_prong; do
  echo "=== $DIR ===" &&
  $OUT/zig1 --dump-c89 $DIR/main.zig > /tmp/fix1_$(basename $DIR).c 2>/dev/null &&
  gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/fix1_$(basename $DIR).c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/fix1_$(basename $DIR) 2>&1 | grep -c 'error:'
done
# Expected: All 0
```

- [ ] **Step 8: Verify baselines byte-identical** — Same MD5 comparison as Task 4 Step 4.

- [ ] **Step 9: Commit**

```bash
git add sf/src/c89_emit.zig
git commit -m "fix: add void-payload guards to compound type emission (Gaps A,O,T)"
```

---

### Task 6: Fix Category 3 — literal-as-temp in for-loop

**Files:**
- Modify: `sf/src/lower.zig:2884-2890` (for-range increment)
- Modify: `sf/src/lower.zig:2918-2925` (for-slice increment)

**Fix: Use int_const for literal 1 (proven by Task 3 INSTC markers)**

- [ ] **Step 1: Read current for-range increment code (lines 2884-2890)**

- [ ] **Step 2: Replace for-range increment with int_const pattern**

Change from:
```zig
var nxt = nextTemp(self, type_mod.TYPE_U32);
emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = start_temp, .rhs = @intCast(u32, 1), .result = nxt } });
```

To:
```zig
var one_r = nextTemp(self, type_mod.TYPE_U32);
emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 1), .result = one_r } });
var nxt = nextTemp(self, type_mod.TYPE_U32);
emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = start_temp, .rhs = one_r, .result = nxt } });
```

This follows the existing pattern at line 2901 where `int_const` is used for literal 0.

- [ ] **Step 3: Replace for-slice increment with int_const pattern**

Same fix at line 2921:

```zig
var one_s = nextTemp(self, type_mod.TYPE_USIZE);
emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 1), .result = one_s } });
emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = idx_temp, .rhs = one_s, .result = nxt_idx } });
```

- [ ] **Step 4: Build and verify Gap E repros + baselines**

```bash
# Verify Gap E repro 0 errors
$OUT/zig1 --dump-c89 repro/tagged_field_path/main.zig > /tmp/fix3.c 2>/dev/null
gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/fix3.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/fix3 2>&1 | grep -c 'error:'
# Expected: 0

# Cross-module E
$OUT/zig1 --dump-c89 repro_xmod/tagged_field_path/main.zig > /tmp/fix3_x.c 2>/dev/null
gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/fix3_x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/fix3_x 2>&1 | grep -c 'error:'
# Expected: 0

# Baselines byte-identical
for EXAMPLE in mandelbrot game_of_life mud_server; do
  BASE=$($BASELINE_OUT/zig1 --dump-c89 examples/$EXAMPLE/main.zig 2>/dev/null | md5sum | awk '{print $1}')
  FIX=$($OUT/zig1 --dump-c89 examples/$EXAMPLE/main.zig 2>/dev/null | md5sum | awk '{print $1}')
  if [ "$BASE" = "$FIX" ]; then echo "$EXAMPLE: MATCH"; else echo "$EXAMPLE: DIFFER"; fi
done
# Expected: All MATCH
```

- [ ] **Step 5: Commit**

```bash
git add sf/src/lower.zig
git commit -m "fix: use int_const for for-loop literal 1, not raw temp ID (Gap E)"
```

---

### Task 7: Full integration verification

**Files:** None (verification only)

- [ ] **Step 1: All 10 repros — 0 gcc errors**

```bash
ALL_REPROS="repro/eu_void_payload repro/var_declared_void repro/optional_void \
            repro/tu_void_prong repro/tagged_field_path \
            repro_xmod/eu_void_payload repro_xmod/var_declared_void \
            repro_xmod/tagged_field_path repro_xmod/optional_void repro_xmod/tu_void_prong"

for DIR in $ALL_REPROS; do
  $OUT/zig1 --dump-c89 $DIR/main.zig > /tmp/verify_$(basename $DIR).c 2>/dev/null
  ERRORS=$(gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/verify_$(basename $DIR).c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/verify_$(basename $DIR) 2>&1 | grep -c 'error:')
  echo "$DIR: $ERRORS errors"
done
```

Expected: All `0 errors`.

- [ ] **Step 2: json_parser — 0 gcc errors**

```bash
$OUT/zig1 --dump-c89 json_parser/main.zig > /tmp/verify_json.c 2>/dev/null
gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/verify_json.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/verify_json 2>&1 | grep -c 'error:'
```

Expected: `0`.

- [ ] **Step 3: json_parser runtime test**

```bash
cd /workspace/znineeight/json_parser && /tmp/verify_json 2>&1 | head -15
```

Expected: Parsed JSON output with test.json contents.

- [ ] **Step 4: Baseline examples — 0 errors + byte-identical**

```bash
for EXAMPLE in mandelbrot game_of_life mud_server; do
  BASE=$($BASELINE_OUT/zig1 --dump-c89 examples/$EXAMPLE/main.zig 2>/dev/null | md5sum | awk '{print $1}')
  FIX=$($OUT/zig1 --dump-c89 examples/$EXAMPLE/main.zig 2>/dev/null | md5sum | awk '{print $1}')
  if [ "$BASE" = "$FIX" ]; then echo "$EXAMPLE: MATCH"; else echo "$EXAMPLE: DIFFER $BASE vs $FIX"; fi
  $OUT/zig1 --dump-c89 examples/$EXAMPLE/main.zig > /tmp/verify_$EXAMPLE.c 2>/dev/null
  gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include /tmp/verify_$EXAMPLE.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/verify_$EXAMPLE 2>&1 | grep -c 'error:'
done
```

Expected: All `MATCH` and `0` errors.

- [ ] **Step 5: lisp_interpreter_curr — 0 gcc errors** (if available in workspace)

- [ ] **Step 6: STOP — present results.**

---

## Self-Review

1. **Spec coverage:** All 3 gap categories covered with instrumentation → prove → fix → verify cycle. Analogous types (optional, tagged_union) covered. 4 new extension repros added beyond existing 5. Total 10 repro programs with cross-module coverage.

2. **Placeholder scan:** No TBD or TODO. Each task has exact file:line references, code snippets, commands, expected output. Task 5 Step 1 notes `getTempTypeByIndex` — implementer must verify it exists in c89_emit.zig or add it using existing temp lookup patterns.

3. **Type consistency:** Marker prefixes `INSTA:`, `INSTB:`, `INSTC:` are distinct and grep-able across all tasks. TYPE_VOID = 1 is consistent with `type_registry.zig:11`. All marker comparisons use `@intCast(u32, 1)`.

4. **Risk management:** Each fix task (4-6) depends on instrumentation proof (tasks 1-3 must complete before fixes). Each fix is minimum viable. Baseline gates at every fix task ensure no regression. Cat 1 fix is the most complex (6 sub-fixes) — Task 5 Steps 1-2 require the `getTempTypeByIndex` helper which may not exist; if blocked, STOP and present.

5. **zni-0003 lesson applied:** No root cause claimed without marker evidence. No fix applied before instrumentation proof. Clean separation: instrument (tasks 1-3) → fix (tasks 4-6) → verify (task 7).
