# Z98 zig1 "Language Wins" — Repro + Investigation Plan (R→I → Decision Gate)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author a RED fixture suite (repro) and feasibility investigations for the Tier-A cheap-language wins and Tier-B packed/true-bitfield features, ordered by difficulty so packed lands last, ending in a Decision Gate that rules which features move to a follow-on F (implementation) plan. **No `sf/src` change, no compiler modification, no F work in this plan.**

**Architecture:** Two phases. R phase commits feature-gap RED fixtures (one dir per feature; packed ladder L0-L7; byte-exact GREEN contracts hand-computed). I phase traces each category's implementation path read-only and returns an `IMPLEMENT-NOW / SEPARATE-PLAN / DEFER / DROP-ZIG0-INCOMPATIBLE` verdict. G phase aggregates verdicts, reconciles the corpus, and STOP-presents. Design decisions locked in `docs/superpowers/specs/2026-09-03-language-wins-design.md` (LSB-first true bitfields; backend-agnostic bit-layout in type layer + LIR; C89 emitter materializes `unsigned char[N]` + shift/mask accessors; byte-buffer never C bitfields).

**Tech Stack:** zig1 (Z98, self-hosted, source still zig0-compilable), C89 emitter + `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign`, corpus classifier per `docs/sf/QUICK_REF.md`.

## Global Constraints

- NO permanent compiler change anywhere in this plan (boundary). No edit to `sf/src/`, `sf/build/`, `out_release/`. Working tree stays clean of `sf/src` drift.
- Compiler under test: fresh build of `sf/src` at HEAD via `timeout 900 bash sf/scripts/build_release.sh`; expected reference md5 `3b45184e...` at HEAD `5b620e3a`. If HEAD moved or md5 differs, record-actual, do not stop.
- Z98 dialect in every fixture: no `anytype`/`@Type`/method syntax/pointer-captures; `@intCast` on width changes; `else` prong present in every switch; `const std = @import("std");` + `pub fn main() void`; output via `std.io.write/writeByte/printInt`.
- RED classification per corpus buckets: `OK` / `FAIL` (clean, deterministic diagnostic) / `ICE` / `CRASH` / runtime-wrong (compiles but wrong output). **ICE or CRASH on a missing-feature fixture is a compiler defect — flag it, never paper over.**
- Each R task commits its fixture dir(s) + a `repro/mi_matrix/EXPECTED_FAIL.md` entry + ledger line. Commit message style `test: RED fixture — <name> (feature-gap <feature>)`.
- Every fixture header comment states: feature, hand-computed GREEN output (byte-exact), today's RED class. GREEN is not runnable today for features zig0 also lacks — the R task records only the RED side + writes the contract.
- Reports accumulate in `.superpowers/sdd/task-LANGWINS-report.md` (gitignored). Ledger: `.superpowers/sdd/progress.md`.
- Memory: `mnemoria --path .opencode/memory` (agent `swexpr-session`), per-feature at task end.
- Only plan-authorized actions; on ambiguity STOP-present; edit/fastedit only on tracked files (fixtures authored via Write); no `git checkout` to erase.
- The 4 gate programs (gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `53405b3b`) do NOT use these features ⇒ full battery on any future F commit must leave them byte-identical (this plan performs no F, so no battery).
- Corpus conventions: fixtures go under `repro/mi_matrix/<name>_xmod/`; cross-module fixtures use the import form of an existing multi-module fixture (verify convention before authoring).
- Report/evidence contract per task: status, fixture dirs + expected GREEN + observed RED (diagnostic verbatim, 3x determinism), classification, feasibility note, concerns.

---
## Phase 0 — Workspace

### Task 0: Workspace + compiler refresh + pre-baseline (no commit)

**Files:**
- Run: `timeout 900 bash sf/scripts/build_release.sh` (fresh reference under /tmp/fx_lw per QUICK_REF recipe)
- Record: `/tmp/fx_lw` bin md5 (expected `3b45184e...` at HEAD `5b620e3a`); record actual + tree state.
- Record: current corpus pre-count (from `repro/mi_matrix/` listing + EXPECTED_FAIL.md v-number) so R commits can report deltas.
- Create: `.superpowers/sdd/task-LANGWINS-report.md` with header + baseline rows.
- Verify: one clean FAIL fixture rerun (e.g. an existing green-guard) to confirm the classifier invocation from QUICK_REF works against the new compiler.

- [ ] Step 1: build reference compiler, record md5.
- [ ] Step 2: record corpus pre-count + EXPECTED_FAIL.md current version.
- [ ] Step 3: create report file header + baseline.
- [ ] Step 4: sanity-run one existing green-guard fixture; confirm classifier command.
- [ ] Step 5: no commit. Ledger line.

---
## Phase R — Repro authoring (all fixtures first, by category, ascending difficulty)

> Every R task: author fixture dir(s) with full code below, verify RED classification 3x against the
> Phase-0 compiler, append `## Langwins feature-gap fixtures` section (or extend it) in
> `repro/mi_matrix/EXPECTED_FAIL.md` with one row per fixture (dir, feature, RED class, expected
> GREEN), append report, commit fixture+EXPECTED_FAIL, ledger line.

### Task R1: Introspection builtins RED fixtures — `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf`

**Files:**
- Create: `repro/mi_matrix/builtin_offsetof_xmod/main.zig`
- Create: `repro/mi_matrix/builtin_bitsizeof_xmod/main.zig`
- Create: `repro/mi_matrix/builtin_bitoffsetof_xmod/main.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

**Interfaces:** Produces first three fixture rows + the `## Langwins feature-gap fixtures` section. Later tasks append rows.

- [ ] Step 1: author `builtin_offsetof_xmod/main.zig`:
```zig
// builtin_offsetof_xmod — FEATURE-GAP RED fixture (@offsetOf).
// Feature: comptime field byte offset builtin @offsetOf(T, "field").
// RED today: @offsetOf is unrecognized -> clean FAIL diagnostic.
// GREEN (contract): "0 4 8\n" — c:u8@0, b:u32@4 (align4), d:u16@8.
const std = @import("std");

const Mixed = struct {
    c: u8,
    b: u32,
    d: u16,
};

pub fn main() void {
    std.io.printInt(@intCast(i32, @offsetOf(Mixed, "c")));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @offsetOf(Mixed, "b")));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @offsetOf(Mixed, "d")));
    std.io.writeByte('\n');
}
```
- [ ] Step 2: author `builtin_bitsizeof_xmod/main.zig`:
```zig
// builtin_bitsizeof_xmod — FEATURE-GAP RED fixture (@bitSizeOf).
// Feature: comptime bit-size builtin @bitSizeOf(T).
// RED today: @bitSizeOf unrecognized -> clean FAIL.
// GREEN (contract): "1 8 32\n" (bool=1, u8=8, u32=32).
const std = @import("std");

pub fn main() void {
    std.io.printInt(@intCast(i32, @bitSizeOf(bool)));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @bitSizeOf(u8)));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @bitSizeOf(u32)));
    std.io.writeByte('\n');
}
```
- [ ] Step 3: author `builtin_bitoffsetof_xmod/main.zig`:
```zig
// builtin_bitoffsetof_xmod — FEATURE-GAP RED fixture (@bitOffsetOf).
// Feature: comptime bit offset builtin @bitOffsetOf(T, "field").
// RED today: @bitOffsetOf unrecognized -> clean FAIL.
// GREEN (contract): "0 32 64\n" (byte offsets 0/4/8 x 8 on a non-packed struct).
// Full value arrives with packed structs (bit-accurate) — see R8.
const std = @import("std");

const Mixed = struct {
    c: u8,
    b: u32,
    d: u16,
};

pub fn main() void {
    std.io.printInt(@intCast(i32, @bitOffsetOf(Mixed, "c")));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @bitOffsetOf(Mixed, "b")));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @bitOffsetOf(Mixed, "d")));
    std.io.writeByte('\n');
}
```
- [ ] Step 4: verify RED 3x each (dump via Phase-0 compiler, record diagnostic verbatim + class; must be FAIL, never ICE/CRASH).
- [ ] Step 5: EXPECTED_FAIL.md rows + report + commit (`test: RED fixtures — @offsetOf/@bitSizeOf/@bitOffsetOf (feature-gap)`).
- [ ] Step 6: ledger line.

### Task R2: Pointer builtins RED fixtures — `@intFromPtr`/`@ptrFromInt`, `@fieldParentPtr`

**Files:**
- Create: `repro/mi_matrix/builtin_ptr_roundtrip_xmod/main.zig`
- Create: `repro/mi_matrix/builtin_fieldparentptr_xmod/main.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

**Interfaces:** Consumes R1 section format.

- [ ] Step 1: first grep `sf/src` for `intFromPtr|ptrFromInt` to confirm absence (old names `@ptrToInt`/`@intToPtr` exist at lower.zig:438-440). Record.
- [ ] Step 2: author `builtin_ptr_roundtrip_xmod/main.zig`:
```zig
// builtin_ptr_roundtrip_xmod — FEATURE-GAP RED fixture (@intFromPtr/@ptrFromInt).
// Feature: modern pointer-int aliases @intFromPtr(p) and @ptrFromInt(a).
// RED today (if absent): unknown builtin -> clean FAIL.
// GREEN (contract): "42\n" — round-trip addr -> ptr, store through it.
const std = @import("std");

pub fn main() void {
    var v: i32 = 7;
    var p = &v;
    var a = @intFromPtr(p);
    var q = @ptrFromInt(a);
    q.* = 42;
    std.io.printInt(v);
    std.io.writeByte('\n');
}
```
- [ ] Step 3: author `builtin_fieldparentptr_xmod/main.zig`:
```zig
// builtin_fieldparentptr_xmod — FEATURE-GAP RED fixture (@fieldParentPtr).
// Feature: @fieldParentPtr(Outer, "field", &o.field) -> *Outer.
// RED today: unrecognized -> clean FAIL.
// GREEN (contract): "1\n" — recovered pointer equals &o.
const std = @import("std");

const Inner = struct { val: i32 };
const Outer = struct { tag: u8, inner: Inner };

pub fn main() void {
    var o: Outer = undefined;
    o.tag = 42;
    o.inner = Inner{ .val = 1 };
    var po = @fieldParentPtr(Outer, "inner", &o.inner);
    var ok: i32 = 0;
    if (@ptrToInt(po) == @ptrToInt(&o)) { ok = 1; }
    std.io.printInt(ok);
    std.io.writeByte('\n');
}
```
- [ ] Step 4: verify RED 3x each; if either fixture compiles today (name already present) record actual class and repurpose to old-name assertion, note in report.
- [ ] Step 5: EXPECTED_FAIL rows + report + commit (`test: RED fixtures — @intFromPtr/@ptrFromInt/@fieldParentPtr (feature-gap)`).
- [ ] Step 6: ledger line.

### Task R3: `@bitCast` RED fixture

**Files:**
- Create: `repro/mi_matrix/builtin_bitcast_xmod/main.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

- [ ] Step 1: author `builtin_bitcast_xmod/main.zig`:
```zig
// builtin_bitcast_xmod — FEATURE-GAP RED fixture (@bitCast).
// Feature: same-size reinterpretation @bitCast(Dest, src).
// RED today: unrecognized -> clean FAIL.
// GREEN (contract): "-1\n" — u32 0xFFFFFFFF reinterpreted as i32.
const std = @import("std");

pub fn main() void {
    var u: u32 = 0xFFFFFFFF;
    var s = @bitCast(i32, u);
    std.io.printInt(s);
    std.io.writeByte('\n');
}
```
- [ ] Step 2: verify RED 3x; record class.
- [ ] Step 3: EXPECTED_FAIL row + report + commit (`test: RED fixture — @bitCast (feature-gap)`).
- [ ] Step 4: ledger line.

### Task R4: `export` fn/var RED fixtures (incl. emitted-C symbol gate)

**Files:**
- Create: `repro/mi_matrix/export_fn_xmod/main.zig`
- Create: `repro/mi_matrix/export_var_xmod/main.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

- [ ] Step 1: author `export_fn_xmod/main.zig`:
```zig
// export_fn_xmod — FEATURE-GAP RED fixture (export fn).
// Feature: `export fn` = source-named, externally-visible C symbol.
// RED today: kw_export has no parser handler -> clean FAIL (parse).
// GREEN (contract): runtime "81\n" AND emitted C contains a non-static
//   definition named `square` (symbol gate; source name, not temp-mangled).
const std = @import("std");

export fn square(n: i32) i32 {
    return n * n;
}

pub fn main() void {
    std.io.printInt(square(9));
    std.io.writeByte('\n');
}
```
- [ ] Step 2: author `export_var_xmod/main.zig`:
```zig
// export_var_xmod — FEATURE-GAP RED fixture (export var).
// Feature: `export var` = source-named external storage symbol.
// RED today: parse FAIL.
// GREEN (contract): runtime "3\n" AND emitted C exposes non-static `counter`.
const std = @import("std");

export var counter: i32 = 0;

fn bump() void {
    counter += 1;
}

pub fn main() void {
    bump();
    bump();
    bump();
    std.io.printInt(counter);
    std.io.writeByte('\n');
}
```
- [ ] Step 3: verify RED 3x each; record whether parser diagnostic is clean (expect FAIL at `export`).
- [ ] Step 4: EXPECTED_FAIL rows + report (note symbol-gate is the real export contract; runtime gate is weak) + commit (`test: RED fixtures — export fn/var (feature-gap)`).
- [ ] Step 5: ledger line.

### Task R5: Cross-module `pub var` repro (asymmetry check vs zig0 oracle)

**Files:**
- Create: `repro/mi_matrix/crossmod_pubvar_xmod/main.zig`
- Create: `repro/mi_matrix/crossmod_pubvar_xmod/other.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

- [ ] Step 1: confirm the cross-module import form used by an existing multi-module fixture (e.g. an `emission_*` or examples multi-file dir); use the same form. Verify zig0 (`sf/build/zig0`) can compile the pair → oracle availability.
- [ ] Step 2: author `other.zig`:
```zig
pub var shared: i32 = 0;

pub fn read() i32 {
    return shared;
}
```
- [ ] Step 3: author `main.zig`:
```zig
// crossmod_pubvar_xmod — RED fixture (cross-module pub var; single storage).
// Feature: a module-scope `pub var` imported and written from another module
//   must refer to ONE storage cell (emitted C: extern decl in the importing
//   module's header, one definition in the owning module).
// RED today (per upstream P1-2 note): the extern header decl is missing or
//   duplicated -> runtime-wrong (0 0 / 7 0) or link failure. RECORD ACTUAL.
// GREEN (contract): "7 7\n" — importer write visible to owner's read().
const std = @import("std");
const other = @import("other");

pub fn main() void {
    other.shared = 7;
    std.io.printInt(other.shared);
    std.io.writeByte(' ');
    std.io.printInt(other.read());
    std.io.writeByte('\n');
}
```
- [ ] Step 4: verify 3x (zig1 RED class + zig0 oracle output). If zig1 is GREEN already, record that (fixture becomes a GREEN regression guard; EXPECTED_FAIL row notes "already OK — gap closed upstream").
- [ ] Step 5: EXPECTED_FAIL row + report (capture emitted-C extern evidence for both compilers) + commit (`test: fixture — cross-module pub var storage (RED or oracle-GREEN as recorded)`).
- [ ] Step 6: ledger line.

### Task R6: `switch` case-range RED fixture (char-class + int dispatch)

**Files:**
- Create: `repro/mi_matrix/switch_case_range_xmod/main.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

- [ ] Step 1: author `switch_case_range_xmod/main.zig`:
```zig
// switch_case_range_xmod — FEATURE-GAP RED fixture (switch case ranges).
// Feature: prong items `a...b` (inclusive) lowered to real dispatch, not dropped.
// RED today: range nodes parsed (parser.zig:977-981) but switch lowering
//   ignores them (lower.zig) -> prongs fall to `else`. Class = clean FAIL (if
//   ranges rejected) OR runtime-wrong (compiles, prints zeros). RECORD ACTUAL.
// GREEN (contract): "130 47\n" — int ranges 1..5=>10, 6..9=>20 over 1..9;
//   char ranges 'a'..'e'=>1, 'f'..'z'=>2 over 'a'..'z'.
const std = @import("std");

fn inRange(n: i32) i32 {
    return switch (n) {
        1...5 => 10,
        6...9 => 20,
        else => 0,
    };
}

fn charClass(ch: u8) i32 {
    return switch (ch) {
        'a'...'e' => 1,
        'f'...'z' => 2,
        else => 0,
    };
}

pub fn main() void {
    var total: i32 = 0;
    var i: i32 = 1;
    while (i <= 9) : (i += 1) { total += inRange(i); }
    std.io.printInt(total);
    std.io.writeByte(' ');
    var c: u8 = 'a';
    var ctotal: i32 = 0;
    while (c <= 'z') : (c += 1) { ctotal += charClass(c); }
    std.io.printInt(ctotal);
    std.io.writeByte('\n');
}
```
- [ ] Step 2: verify RED 3x; record exact class (clean FAIL vs runtime-wrong with observed stdout).
- [ ] Step 3: EXPECTED_FAIL row + report + commit (`test: RED fixture — switch case ranges dropped (feature-gap)`).
- [ ] Step 4: ledger line.

### Task R7: Arbitrary-width integer RED fixture (`u3`/`i7`/`u12`)

**Files:**
- Create: `repro/mi_matrix/int_arbitrary_width_xmod/main.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

- [ ] Step 1: author `int_arbitrary_width_xmod/main.zig`:
```zig
// int_arbitrary_width_xmod — FEATURE-GAP RED fixture (arbitrary-width ints).
// Feature: integer types uN/iN for any N in 1..65535 (u3, i7, u12, ...).
// RED today: only fixed widths register (TYPE_SYSTEM TypeKind) -> unknown type
//   `u3` -> clean FAIL. RECORD ACTUAL.
// GREEN (contract): "7 -3 3000 4\n" — u3 5+2=7; i7 -3; u12 3000; u3 7&4=4.
const std = @import("std");

pub fn main() void {
    var a: u3 = 5;
    a = a + 2;
    var b: i7 = -3;
    var c: u12 = 3000;
    var d: u3 = 0;
    d = a & 4;
    std.io.printInt(@intCast(i32, a));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, b));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, c));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, d));
    std.io.writeByte('\n');
}
```
- [ ] Step 2: verify RED 3x; record class + diagnostic (expect unknown-type clean FAIL at `u3`).
- [ ] Step 3: EXPECTED_FAIL row + report + commit (`test: RED fixture — arbitrary-width ints uN/iN (feature-gap)`).
- [ ] Step 4: ledger line.

### Task R8: Packed struct ladder part 1 — L0 flags / L1 mixed / L2 straddle

**Files:**
- Create: `repro/mi_matrix/packed_l0_flags_xmod/main.zig`
- Create: `repro/mi_matrix/packed_l1_mix_xmod/main.zig`
- Create: `repro/mi_matrix/packed_l2_straddle_xmod/main.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

**Interfaces:** GREEN contracts are hand-computed per design spec (LSB-first, `size=(bits+7)/8`, stride=size). These are the C89 padding/bit-accounting regression guards.

- [ ] Step 1: author `packed_l0_flags_xmod/main.zig`:
```zig
// packed_l0_flags_xmod — FEATURE-GAP RED fixture (packed struct, L0: bool flags).
// Feature: `packed struct` true bitfields, LSB-first, no padding.
// RED today: `packed` not a keyword -> clean FAIL (parse). RECORD ACTUAL.
// GREEN (contract): "1 5 1\n" — 3 bools = 1 byte; a=true(c=bit0), b=false,
//   c=true(bit2) => byte 0b00000101 = 5; field reads 1 (a&&!b&&c).
const std = @import("std");

const Flags = packed struct {
    a: bool,
    b: bool,
    c: bool,
};

pub fn main() void {
    var f: Flags = undefined;
    f.a = true;
    f.b = false;
    f.c = true;
    std.io.printInt(@intCast(i32, @sizeOf(Flags)));
    std.io.writeByte(' ');
    var bp = @ptrCast([*]const u8, &f);
    std.io.printInt(@intCast(i32, bp[0]));
    std.io.writeByte(' ');
    if (f.a and (!f.b) and f.c) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte('\n');
}
```
- [ ] Step 2: author `packed_l1_mix_xmod/main.zig`:
```zig
// packed_l1_mix_xmod — FEATURE-GAP RED fixture (packed struct, L1: u1+u3+u4 in 1 byte).
// GREEN (contract): "1 155 1 5 9\n" — size 1; x=1(bit0), y=5(bits1-3), z=9(bits4-7)
//   => byte 0b10011011 = 155; field reads 1 5 9.
const std = @import("std");

const Mix = packed struct {
    x: u1,
    y: u3,
    z: u4,
};

pub fn main() void {
    var m: Mix = undefined;
    m.x = 1;
    m.y = 5;
    m.z = 9;
    std.io.printInt(@intCast(i32, @sizeOf(Mix)));
    std.io.writeByte(' ');
    var bp = @ptrCast([*]const u8, &m);
    std.io.printInt(@intCast(i32, bp[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, m.x));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, m.y));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, m.z));
    std.io.writeByte('\n');
}
```
- [ ] Step 3: author `packed_l2_straddle_xmod/main.zig`:
```zig
// packed_l2_straddle_xmod — FEATURE-GAP RED fixture (packed struct, L2: straddle).
// b spans bytes 0-1 (bits 5..12). GREEN (contract): "2 255 31 31 255\n" —
//   size 2; a=31(11111 bits0-4), b=255(8 bits @5..12) => byte0 0xFF, byte1 0x1F;
//   field reads 31 255.
const std = @import("std");

const Strad = packed struct {
    a: u5,
    b: u8,
};

pub fn main() void {
    var s: Strad = undefined;
    s.a = 31;
    s.b = 255;
    std.io.printInt(@intCast(i32, @sizeOf(Strad)));
    std.io.writeByte(' ');
    var bp = @ptrCast([*]const u8, &s);
    std.io.printInt(@intCast(i32, bp[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, bp[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, s.a));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, s.b));
    std.io.writeByte('\n');
}
```
- [ ] Step 4: verify RED 3x each; record class (expect clean parse FAIL at `packed`).
- [ ] Step 5: EXPECTED_FAIL rows + report (note the L0-L2 contracts are the padding regression net) + commit (`test: RED fixtures — packed struct L0/L1/L2 ladder (feature-gap)`).
- [ ] Step 6: ledger line.

### Task R9: Packed struct ladder part 2 — L3 nested / L4 union

**Files:**
- Create: `repro/mi_matrix/packed_l3_nested_xmod/main.zig`
- Create: `repro/mi_matrix/packed_union_xmod/main.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

- [ ] Step 1: author `packed_l3_nested_xmod/main.zig`:
```zig
// packed_l3_nested_xmod — FEATURE-GAP RED fixture (packed struct, L3: nested
//   packed struct field, bit-contiguous). Nested-packable is a FEASIBILITY probe:
//   if zig1 must restrict fields to int/bool/enum only, this contract re-baselines
//   with the operator at the gate.
// GREEN (contract): "2 5 6 3 3\n" — 2+6+2 = 10 bits => size 2; reads back.
const std = @import("std");

const Inner = packed struct { a: u3, b: u3 };
const Outer = packed struct { head: u2, inner: Inner, tail: u2 };

pub fn main() void {
    var o: Outer = undefined;
    o.head = 3;
    o.inner.a = 5;
    o.inner.b = 6;
    o.tail = 3;
    std.io.printInt(@intCast(i32, @sizeOf(Outer)));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, o.inner.a));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, o.inner.b));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, o.head));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, o.tail));
    std.io.writeByte('\n');
}
```
- [ ] Step 2: author `packed_union_xmod/main.zig`:
```zig
// packed_union_xmod — FEATURE-GAP RED fixture (packed union, L4: overlap at bit0).
// GREEN (contract): "2 8\n" — members overlap at bit 0; 12 bits => size 2;
//   write b=3000, read a = low 4 bits of 3000 = 8.
const std = @import("std");

const U = packed union {
    a: u4,
    b: u12,
};

pub fn main() void {
    var u: U = undefined;
    u.b = 3000;
    std.io.printInt(@intCast(i32, @sizeOf(U)));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, u.a));
    std.io.writeByte('\n');
}
```
- [ ] Step 3: verify RED 3x each; record class.
- [ ] Step 4: EXPECTED_FAIL rows + report + commit (`test: RED fixtures — packed nested struct + packed union (feature-gap)`).
- [ ] Step 5: ledger line.

### Task R10: Packed ladder top — L5 array+global / L6 by-value+cross-module / L7 enum(u3) field

**Files:**
- Create: `repro/mi_matrix/packed_array_global_xmod/main.zig`
- Create: `repro/mi_matrix/packed_byvalue_module_xmod/main.zig`
- Create: `repro/mi_matrix/packed_byvalue_module_xmod/types.zig`
- Create: `repro/mi_matrix/packed_enum_field_xmod/main.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

- [ ] Step 1: author `packed_array_global_xmod/main.zig`:
```zig
// packed_array_global_xmod — FEATURE-GAP RED fixture (L5: array of packed in a
//   storage global). Also re-exercises whole-element global stores (store-drop fix).
// GREEN (contract): "1 33 3 4\n" — size 1 (stride 1, no pad); grid[1] byte =
//   x=1,y=2 => 0x21 = 33; grid[3].x=3, .y=4.
const std = @import("std");

const Cell = packed struct { x: u4, y: u4 };
var grid: [4]Cell = undefined;

pub fn main() void {
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        grid[i] = Cell{ .x = @intCast(u4, i), .y = @intCast(u4, i + 1) };
    }
    std.io.printInt(@intCast(i32, @sizeOf(Cell)));
    std.io.writeByte(' ');
    var bp = @ptrCast([*]const u8, &grid[0]);
    std.io.printInt(@intCast(i32, bp[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, grid[3].x));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, grid[3].y));
    std.io.writeByte('\n');
}
```
- [ ] Step 2: author `packed_byvalue_module_xmod/types.zig`:
```zig
pub const Pair = packed struct { lo: u4, hi: u4 };

pub fn build(lo: u4, hi: u4) Pair {
    return Pair{ .lo = lo, .hi = hi };
}

pub fn sum(p: Pair) i32 {
    return @intCast(i32, p.lo) + @intCast(i32, p.hi);
}
```
- [ ] Step 3: author `packed_byvalue_module_xmod/main.zig`:
```zig
// packed_byvalue_module_xmod — FEATURE-GAP RED fixture (L6: packed by-value +
//   cross-module layout identity). Two modules must agree on the packed layout.
// GREEN (contract): "1 21 187\n" — size 1; sum(10,11)=21; byte = hi<<4|lo =
//   0b1011_1010? no: lo=10(1010 bits0-3), hi=11(1011 bits4-7) => 0xBA = 186.
//   CONFIRM byte expectation in I8 (LSB-first) and fix header if wrong.
const std = @import("std");
const types = @import("types");

pub fn main() void {
    var p = types.build(@intCast(u4, 10), @intCast(u4, 11));
    std.io.printInt(@intCast(i32, @sizeOf(types.Pair)));
    std.io.writeByte(' ');
    std.io.printInt(types.sum(p));
    std.io.writeByte(' ');
    var bp = @ptrCast([*]const u8, &p);
    std.io.printInt(@intCast(i32, bp[0]));
    std.io.writeByte('\n');
}
```
Contract note: lo=10 = 0b1010 at bits 0..3, hi=11 = 0b1011 at bits 4..7 → byte = hi<<4 | lo = 0xB0|0xA = 0xBA = 186. Expected GREEN = `1 21 186`. (Header above flags the re-check; make it 186.)
- [ ] Step 4: author `packed_enum_field_xmod/main.zig`:
```zig
// packed_enum_field_xmod — FEATURE-GAP RED fixture (L7: enum(u3) field inside a
//   packed struct; exercises B0+B3). GREEN (contract): "1 3 1 1\n" — size 1;
//   on=true(bit0), color=green(enum 1, bits1-3) => byte 0b00000011 = 3;
//   @enumToInt(Color.blue)==2; @sizeOf(Color)=1.
const std = @import("std");

const Color = enum(u3) { red, green, blue };
const Pixel = packed struct { on: bool, color: Color };

pub fn main() void {
    var p: Pixel = undefined;
    p.on = true;
    p.color = Color.green;
    std.io.printInt(@intCast(i32, @sizeOf(Pixel)));
    std.io.writeByte(' ');
    var bp = @ptrCast([*]const u8, &p);
    std.io.printInt(@intCast(i32, bp[0]));
    std.io.writeByte(' ');
    var c: Color = Color.blue;
    if (@enumToInt(c) == 2) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @sizeOf(Color)));
    std.io.writeByte('\n');
}
```
- [ ] Step 5: verify RED 3x each; record classes.
- [ ] Step 6: EXPECTED_FAIL rows + report + commit (`test: RED fixtures — packed array/global + by-value/cross-module + enum(u3) field (feature-gap)`).
- [ ] Step 7: ledger line.

---
## Phase I — Investigation (consecutive, read-only, ascending difficulty)

> Each I task: READ-ONLY. No repo mutation (dumps/probes in /tmp only). Traces the implementation
> path for its category, returns verdict `IMPLEMENT-NOW | SEPARATE-PLAN | DEFER | DROP-ZIG0-INCOMPATIBLE`
> with evidence, and appends `## I<n>` to `.superpowers/sdd/task-LANGWINS-report.md`. No commit.

### Task I1: Introspection builtins — implementation path

**Files:** read `token.zig`, lexer builtin tokenization, parser builtin/primary handling, `comptime_eval.zig`, `type_registry.zig`, `lower.zig`.
- Trace how `@sizeOf`/`@alignOf` are recognized + folded today; identify the minimal add-point for `@offsetOf` (field offset from resolved container layout + field-name→payload lookup), `@bitSizeOf`, `@bitOffsetOf` (needs a per-type bit-size notion — census whether one exists or derives from `size*8`).
- Note `comptime_eval.zig` `width_bits` scaffolding (:16,25-28) as the seed for bit-size plumbing.
- Deliverable: add-point file:line list + verdict per builtin + report section. Verdict expected IMPLEMENT-NOW (small) unless census shows missing field-offset infra (then note `@offsetOf` may key off the same table packed needs — flag to I8).

### Task I2: Pointer builtins — `@intFromPtr`/`@ptrFromInt`/`@fieldParentPtr`

- Confirm `@intFromPtr`/`@ptrFromInt` absent; map the cast-builtin dispatch (`lower.zig:430-446`, incl. `@ptrToInt`/`@intToPtr` :438-440) → aliasing is near-trivial.
- `@fieldParentPtr`: requires container field *byte offset by name* at comptime + pointer arithmetic — same offset infra as `@offsetOf` (I1). Rate accordingly; likely IMPLEMENT-NOW after I1 infra or SEPARATE-PLAN if offsets don't exist.
- Deliverable: verdicts + evidence.

### Task I3: `@bitCast`

- Same-size reinterpret: needs type size equality check + no-op emission (value move). Trace sema + lower for a new builtin; confirm no C cast needed (bit-identical storage). Verdict expected IMPLEMENT-NOW.

### Task I4: `export` fn/var

- Read parser `kw_extern` handlers (parser.zig:1357,1489) as the template for a `kw_export` handler; trace symbol registration + visibility (AstNode flag bit3 `is_export` already reserved, ast.zig:120); name mangling (export = source name); c89_emit extern-vs-static emission + whether the mangler/C-symbol mapping can exempt export decls.
- Check zig0 for `export` support (oracle expectation).
- Deliverable: parse/symbol/mangle/emit touch-list + verdict.

### Task I5: Cross-module `pub var` extern emission

- Read c89_emit's module-scope var emission + header generation for imported modules; determine whether an imported storage global gets an `extern` decl (the P1-2 note) or duplicates storage per module; classify bug-vs-feature; record the R5 fixture's actual class + emitted-C evidence as the repro.
- Deliverable: root-cause (if bug) + verdict (likely IMPLEMENT-NOW as a bug-fix F, or note if it is already fixed upstream).

### Task I6: `switch` case-range lowering

- Read `lower.zig` switch expr (:4010-4219) + stmt (:4913-5064) paths, case mapping (:4055-4133), `SwitchCase{value:u64,target_bb}` (`lir.zig`), range nodes from parser (:977-981), and c89_emit switch emission (:6370-6411).
- Determine: represent ranges as (a) expansion to per-value cases, (b) a bounds-check chain in the else zone, or (c) a dedicated range-case LIR. Note the `@intCast(u32, c.value)` truncation (:6385) as a latent u64 bug the range work must respect.
- Deliverable: recommended lowering + verdict (IMPLEMENT-NOW likely; SEPARATE-PLAN if it needs LIR shape change).

### Task I7: Arbitrary-width integers — width-assumption census

- Census every hardcoded width assumption (8/16/32/64), pow2 mask, and int-type switch across lexer/parser/type resolution (`type_registry.zig` primitive registration), sema, `lower.zig`, `c89_emit.zig` (carrier type choice, truncation), `comptime_eval.zig` (`width_bits`), spill_store/serde of ints.
- Evaluate the enclosing-C-type + mask/truncate emission strategy vs risks (i32 defaulting, comparisons, shifts, `@intCast` width rules).
- Deliverable: census table + risk list + size estimate + verdict (likely SEPARATE-PLAN or DEFER if census is large).

### Task I8: Packed struct — full architecture (THE big I)

- Read parser container-decl path (struct/union/enum, pub/extern modifiers) → where `packed` slots in; `type_registry.zig` struct payload + layout resolution (:683-790 region per design doc) → how a backend-neutral bit-layout side table fits; size/align computation site.
- Design: new TypeKinds; bit-layout table (per-field bit_offset/bit_size; container bit_size; size=(bits+7)/8; align=1); enforcement set (B6: reject float/ptr/array/slice/optional/error/non-packed-struct) + error codes; LIR `load_bitfield`/`store_bitfield`; whole-value ops (aggregate init, struct literal, assignment, param/return ABI as memcpy, global array assign_index — must survive the store-drop DCE the same way structs now do); spill/serde of the new ops + kind payloads; c89_emit `unsigned char[N]` decl + shift/mask accessor math (incl. signed extension + mask on store) + array stride + no-address enforcement; interactions with `@sizeOf`/`@alignOf`/`@bitSizeOf`/`@bitOffsetOf` (R1/R8 companions); nested packed struct fields feasibility (contract `packed_l3_nested_xmod`).
- Produce a concrete implementation sketch + file-by-file change list + phasing suggestion (parse→type→LIR→emit→battery) + size/risk.
- Deliverable: architecture section + verdict (expected SEPARATE-PLAN, possibly split core / union / emitter).

### Task I9: Packed union — deltas from I8

- Deltas: overlap-at-bit0, size=max, enforcement; confirm no tagged packed union (Zig forbids `union(enum)` packed) so the tag machinery is untouched.
- Deliverable: delta list + verdict (IMPLEMENT-NOW within the I8 separate plan).

### Task I10: `enum(uN)` backing — deltas from I8/B0

- Read current enum backing support (does zig1 parse `enum(u8)` or only bare `enum`?) + registry; deltas for arbitrary-width backing (depends on I7); `@enumToInt`/`@intToEnum` width behavior.
- Deliverable: dependency matrix (I10 ⊃ I7/B0 ⊃ I8) + verdict (DEFER to the packed plan's tail or SEPARATE-PLAN).

---
## Phase G — Decision gate

### Task G1: Verdict aggregation + corpus reconciliation + STOP-present

- Aggregate I1..I10 verdicts into a per-feature table (feature → verdict → rationale → recommended F ordering → F-plan candidate name).
- Reconcile: corpus sweep count with the new R fixtures (each is FAIL/green-guard until F lands), EXPECTED_FAIL.md section status, QUICK_REF gate notes if any fixture changed a documented expectation.
- Resolve open contracts flagged during R (packed_l3 nested, packed_byvalue byte 186, any R5 asymmetry finding) into explicit re-baseline proposals for operator ruling.
- Deliverable: `## G1` decision report + STOP-present to operator with the recommended follow-on execution order. NO F work begins without the ruling.

---
## Plan Self-Review (performed at authoring time)

1. **Spec coverage:** A1 `@offsetOf`/A8 `@bitSizeOf`/`@bitOffsetOf` (R1/I1), A5 pointer aliases + A6 `@fieldParentPtr` (R2/I2), A7 `@bitCast` (R3/I3), A2 `export` (R4/I4), A4 cross-module `pub var` (R5/I5), A3 case ranges (R6/I6), B0 arbitrary ints (R7/I7), B1 packed struct ladder (R8-R10/I8), B2 packed union (R9/I9), B3 `enum(uN)` (R10/I10). All covered.
2. **Placeholder scan:** no TBD; fixture code complete; ladder byte contracts hand-computed and cross-checked.
3. **Type/name consistency:** fixture names `<feature>_xmod`; `main.zig`/`types.zig`/`other.zig` conventions uniform; std.io API usage consistent with existing fixtures.

## Execution Handoff

Plan complete. Two execution options once the operator takes this plan: (1) Subagent-Driven (recommended) — fresh subagent per task with two-stage review; (2) Inline execution with checkpoints. Execution requires a build-mode session (this plan commits R fixtures + docs, then runs read-only I investigations).

---
## AMENDMENT — G1 rulings + execution record (operator, 2026-09-03)

**Status of this plan:** R phase COMPLETE (Tasks R1-R10 committed, all review-Approved; 19 fixture rows; EXPECTED_FAIL v53→v63). I phase: I1-I8 DONE + review-Approved (I8 Approved after report fixes). **I9/I10 SKIPPED by operator ruling** (entailed by I8's SEPARATE-PLAN + hard narrow-int prereq; packed-union deltas + enum(uN) deps fold into the packed F-plans). G1 STOP-presented; rulings below. NO F work begins under this plan.

**Operator G1 rulings (verbatim intent):**
- **(a) packed_byvalue byte 186-vs-187:** CONFIRM **186** (0xBA = hi<<4|lo = 0xB0|0xA). Header literal `187` was a self-corrected arithmetic slip (kept verbatim in the fixture). L6 run-gate GREEN contract = `1 21 186`.
- **(b) packed_l3 nested field:** KEEP contract `2 5 6 3 3`; support **LEAF access through nested packed containers** (bit-offset chain accumulation via packed-container bit_size dispatch). Scope OUT: whole-sub-container value moves and `&packed.field`.
- **(c) cross-module pub-var ICE (R5):** fix in **F-CROSSMOD-STORE**. Defect confirmed CLEAR via I5 (review-Approved root cause: store-side module-base→`store_global` routing missing; load path lower.zig:2549-2591 has it; additive fix in `lowerFieldStore` head) — no additional prior-I task required. ICE-on-unimplemented-path pattern → F-CLEANDIAG.
- **(d) clean-diagnostics task:** ADD **F-CLEANDIAG** (unsupported-builtin silent mis-emission + `uN`→void false-green; error[3000]-class gates; byte-neutral for valid programs so 4 MD5 gates hold).

**Approved follow-on execution order** (future F-plans, dependency-first; each its own writing-plans → subagent-driven cycle):
1. F-INTRO (`@offsetOf`/`@bitSizeOf`/`@bitOffsetOf`)
2. F-PTRBUILTIN (`@intFromPtr`/`@fieldParentPtr`; `@ptrFromInt` conditional on R2 fixture amend `var q: *i32`)
3. F-BITCAST (@as-unchecked-arm + size/int-family gate + clean size-mismatch error)
4. Independents (order free): F-CROSSMOD-STORE (bug-fix), F-EXPORT, F-SWITCHRANGE (must carry `itoa64` hardening + case-literal vs C-int cap)
5. F-CLEANDIAG
6. PLAN-INTWIDTH (width-vs-byte-size refactor, `intWidthBits`/`intIsSigned`, ≤64 cap)
7. PLAN-PACK-CORE (P1-P3 → packed L0/L1/L2 GREEN)
8. PLAN-PACK-AGG (P4 → L3-L6 GREEN; packed-union folded)
9. PLAN-PACK-B3 (P5 → L7 `enum(u3)` GREEN; enum(uN) folded; defers on PLAN-INTWIDTH)

**Corpus post-R reconciliation** (reference compiler `/tmp/fx_subfolder/zig1` md5 `1a5056b2`, -s0, single run): 424 dirs = OK 397 / FAIL 15 / GCCFAIL 5 / GREEN 6 / ICE 1 / CRASH 0; GCCFAIL folded → FAIL-class 20. Pre-existing 405 subset reproduced exactly (OK 395/FAIL 5/GREEN 5/ICE 0/CRASH 0), 0 drift; gol/lisp/json/mud gates unaffected (no sf/src change). New fixtures bucket: 5 GCCFAIL (R1+R2 builtins), 10 parse-FAIL (export×2 + packed×8), 1 false-green GREEN (`int_arbitrary_width_xmod`), 1 ICE (`crossmod_pubvar_xmod`), 2 compile-OK runtime-wrong invisible to the compile-only sweep (@bitCast, case-ranges).

**Key feasibility findings carried into F-planning:** (i) unsupported builtins have NO clean diagnostic — silent mis-emission (GCCFAIL) or silent result-drop (runtime-wrong) or void-fallback (uN→void); (ii) unknown type names degrade to TYPE_VOID (sema var_declared_void); (iii) top-level fns/module vars already emit non-static — export = mangler source-name exemption; (iv) zig0 parses `export` but keeps mangled names → source-name GREEN is Zig-semantics, not oracle; (v) switch range prongs parse but drop to default in the shared case-map loop (EXPAND per-value is drop-in); (vi) packed needs a hard narrow-int `uN` registry prereq; width-vs-byte-size conflation is the INTWIDTH blocker.
