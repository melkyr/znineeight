# emission_type_storage_extern_threealias_xmod — RED fixture for residual A₂ (3+ aliasing modules, two types, single-file observation)

Task R-VAR (2026-08-21, AMENDMENT 7 Ruling 4). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Variation of the A₂ base fixture (`emission_type_storage_extern_xmod`) extending the shape space:
- **3+ aliasing modules** — main, mod_b, mod_c each ident-base-alias `Color` → **three** storage-global
  definitions of `zG_<hash>_Color` (base had 2).
- **two different types aliased ident-base in one module** — mod_b aliases BOTH `Color` and `Shape`
  (2 storage globals in one module).
- **ref-only module referencing TWO types** — mod_d references `zG_<hash>_Color` AND
  `zG_<hash>_Shape` with no `extern` in its include chain → both undeclared.
- **single-file `--dump-c89` observation** — the `all==1` path (`emitModule` `c89_emit.zig:2379`)
  emits duplicate **tentative** definitions which gcc merges → GREEN (not a gcc error; see note at
  the end).

## Fixture (verbatim)
`mod_a.zig` (type owner — two enum types):
```zig
pub const Color = enum(u8) {
    Red,
    Green,
    Blue,
};

pub const Shape = enum(u8) {
    Circle,
    Square,
};
```
`mod_b.zig` (ident-base alias of **two** types → def #2 for Color, def #1 for Shape):
```zig
const mod_a = @import("mod_a.zig");

pub const Color = mod_a.Color;
pub const Shape = mod_a.Shape;

pub fn name(c: Color) i32 {
    return switch (c) {
        .Red => 0,
        .Green => 1,
        .Blue => 2,
    };
}

pub fn sides(s: Shape) i32 {
    return switch (s) {
        .Circle => 0,
        .Square => 4,
    };
}
```
`mod_c.zig` (ident-base alias → def #3 for Color):
```zig
const mod_a = @import("mod_a.zig");

pub const Color = mod_a.Color;

pub fn kind() i32 {
    return switch (Color.Green) {
        .Red => 1,
        .Green => 2,
        .Blue => 3,
    };
}
```
`mod_d.zig` (reference-only — import-base aliases + type-as-value consts; references BOTH types'
storage globals; header chain reaches only mod_a.h):
```zig
const Color = @import("mod_a.zig").Color;
const Shape = @import("mod_a.zig").Shape;
const C = Color;
const S = Shape;

pub fn cval() i32 {
    return switch (C.Blue) {
        .Red => 1,
        .Green => 2,
        .Blue => 3,
    };
}

pub fn sval() i32 {
    return switch (S.Square) {
        .Circle => 1,
        .Square => 2,
    };
}
```
`main.zig` (ident-base aliases → def #1 for Color, def #2 for Shape):
```zig
const std = @import("std");
const mod_b = @import("mod_b.zig");
const mod_c = @import("mod_c.zig");
const mod_d = @import("mod_d.zig");
const Color = mod_b.Color;
const Shape = mod_b.Shape;

pub fn main() void {
    std.io.printInt(mod_d.cval() + mod_d.sval() + mod_c.kind() + mod_b.name(Color.Blue) + mod_b.sides(Shape.Square));
}
```
Import graph: `main → {mod_b, mod_c, mod_d} → mod_a`. 5 modules + std.

## RED baseline (measured 2026-08-21, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rA2 main.zig
rc=0
$ cd /tmp/rA2 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class A₂, BOTH types' storage globals undeclared):
```
mod_d_5B57D13A.c:77:12: error: 'zG_E5B43CF8_Color' undeclared (first use in this function); did you mean 'zT_E5B43CF8_Color'?
mod_d_5B57D13A.c:79:12: error: 'zG_4380DDC6_Shape' undeclared (first use in this function); did you mean 'zT_4380DDC6_Shape'?
```
Emitting C — definition multiplicity (3× Color, 2× Shape across main/mod_b/mod_c) + missing extern:
```
mod_d_*.c:2:  zT_E5B43CF8_Color zG_C60BF9F2_C;    // mod_d's own const-C storage global
mod_d_*.c:3:  zT_4380DDC6_Shape zG_D60C1322_S;    // mod_d's own const-S storage global
mod_d_*.c:77: zT_0 = zG_E5B43CF8_Color;           // ← ref, NO extern in chain
mod_d_*.c:78: zG_C60BF9F2_C = zG_E5B43CF8_Color;  // const-C init loads the type storage
mod_d_*.c:79: zT_1 = zG_4380DDC6_Shape;           // ← ref, NO extern in chain
mod_d_*.c:80: zG_D60C1322_S = zG_4380DDC6_Shape;
```
`mod_d.h` includes only `zig_compat.h`, `zig_special_types.h`, `mod_a.h` (×2) — no extern for either
storage global.

## Root cause pinned
Same A₂ as the base fixture: `emitGlobalDecls` (`c89_emit.zig:2448-2464`) emits a def per ident-base
aliasing module (here 3 for Color), and the `extern` (`:2344-2360`) is not propagated to the
reference-only module's header chain. Two types referenced → two independent undeclared errors.

## Single-file `--dump-c89` mode observation (the `all==1` duplicate-def path)
`zig1 --dump-c89 main.zig` (no `--output-dir`) merges all modules into one `output.c`
(`emitModule` `c89_emit.zig:2370`, `all==1` in `emitGlobalDecls` `:2379`). Measured on this fixture
and on the base A₂ fixture:
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > output.c
$ gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c output.c
gcc_rc=0   # 3+ duplicate `zT_..._Color zG_E5B43CF8_Color;` lines emitted — gcc MERGES tentative defs
```
The `all==1` path emits the duplicate tentative definitions (base fixture: 6 `zG_Color;` lines; this
fixture: 3) but gcc accepts multiple tentative definitions of one symbol in a TU, so **no gcc error** —
it compiles GREEN with latent duplicate defs. This is the "duplicate-def path" the I-report fix
explicitly mentions (`task-I-residual-report.md:77`: "makes the all==1 single-file mode emit one def
instead of today's duplicate") — a def-consolidation fix, NOT a gcc-error fix. Documented here as an
observation; no separate single-file fixture was created because it cannot be RED.

## Expected post-fix result
After the A₂ fix: exactly ONE def of `zG_E5B43CF8_Color` and `zG_4380DDC6_Shape` (in mod_a, the
owner), externs propagated to every header including mod_d.h → `gcc -c` rc=0; single-file mode emits
one def per storage global.
