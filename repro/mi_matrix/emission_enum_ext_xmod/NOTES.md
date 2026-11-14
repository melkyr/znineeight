# emission_enum_ext_xmod — GREEN runtime-correctness fixtures for enum-switch forms (A/B/C/D)

Task 3 R-ENUMEXT (2026-08-25), AMENDMENT 7 of the Self-Hosted zig1_5
Investigation Plan (`docs/superpowers/plans/2026-08-25-self-hosted-zig15-investigation-plan.md`).
Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1` (the WORKING
reference built by zig0). Consumes the Task 2 fix (commit `5ec13efb` — qualified
enum-literal stmt-switch cases now collect; `switch (k)` carries real `case`
labels). Build recipe: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`,
link `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c`, run.

## Purpose

Runtime-correctness coverage for the post-fix enum-switch family. Where the R1
repro (`emission_enum_switch_xmod`) proved the fix on ONE qualified multi-case
stmt-switch, this fixture exercises FOUR shapes in one build:
- **A** — qualified multi-case stmt-switch, CROSS-MODULE (`mod_a.zig`), value
  `star` → 3 (exercises the fixed field_access case-collection path AND the
  cross-module shape).
- **B** — anonymous `.plus`/`.minus`/`.star` case-label form (enum_literal case
  values) with qualified discriminant passed in, `minus` → 2.
- **C** — enum stmt-switch nested inside an `if` inside a `while` loop, printing
  per-iteration values 1, 2, 3 (`123`).
- **D** — enum-to-int print via `@intCast(i32, @enumToInt(Kind.star))` → 2
  (dialect has `@enumToInt`; verified it compiles).

All four print through `std.io.printInt`, separated by `std.io.print("\n")`.

## Fixture (verbatim)

`mod_a.zig`:
```zig
pub const Kind = enum(u16) { plus, minus, star };

pub fn pick(k: Kind) u32 {
    var r: u32 = 0;
    switch (k) {
        Kind.plus => r = 1,
        Kind.minus => r = 2,
        Kind.star => r = 3,
        else => {},
    }
    return r;
}
```
`main.zig`:
```zig
const std = @import("std.zig");
const mod_a = @import("mod_a.zig");

const Kind = enum(u16) { plus, minus, star };

fn b_pick(k: Kind) u32 {
    var r: u32 = 0;
    switch (k) {
        .plus => r = 1,
        .minus => r = 2,
        .star => r = 3,
        else => {},
    }
    return r;
}

pub fn main() void {
    std.io.printInt(mod_a.pick(mod_a.Kind.star));
    std.io.print("\n");
    std.io.printInt(b_pick(Kind.minus));
    std.io.print("\n");
    var i: i32 = 0;
    while (i < @intCast(i32, 3)) {
        if (i == 0) {
            switch (Kind.plus) {
                Kind.plus => std.io.printInt(1),
                Kind.minus => std.io.printInt(2),
                Kind.star => std.io.printInt(3),
                else => {},
            }
        } else if (i == 1) {
            switch (Kind.minus) {
                Kind.plus => std.io.printInt(1),
                Kind.minus => std.io.printInt(2),
                Kind.star => std.io.printInt(3),
                else => {},
            }
        } else {
            switch (Kind.star) {
                Kind.plus => std.io.printInt(1),
                Kind.minus => std.io.printInt(2),
                Kind.star => std.io.printInt(3),
                else => {},
            }
        }
        i = i + @intCast(i32, 1);
    }
    std.io.print("\n");
    std.io.printInt(@intCast(i32, @enumToInt(Kind.star)));
    std.io.print("\n");
}
```

## GREEN evidence (measured 2026-08-25, /tmp/fx_subfolder/zig1)

```
$ cd /workspace/znineeight/repro/mi_matrix/emission_enum_ext_xmod
$ rm -rf /tmp/fx_out3 && mkdir -p /tmp/fx_out3
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fx_out3 main.zig
dump rc=0
$ cd /tmp/fx_out3 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc rc=0
$ gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include *.o \
    /workspace/znineeight/sf/src/include/zig_runtime.c \
    /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/fx_bin3
link rc=0
$ /tmp/fx_bin3
3
2
123
2
run rc=0
```

All four emitted `switch` statements carry real case labels post-fix
(`mod_a_92C4EB73.c:20` — `case 0/1/2` for the cross-module A switch; the B switch
and the three C switches in `main_3DF5832C.c` likewise). Output matches expected
exactly: line 1 = A `star→3`, line 2 = B `minus→2`, line 3 = C per-iteration
`1|2|3`, line 4 = D `@enumToInt(star)=2`.

## Which shape each covers

- **A** → `emission_enum_switch_xmod` (R1) shape + cross-module: qualified labels
  `Kind.plus/minus/star` (field_access case values — the EXACT node shape Task 2
  fixed), multi-case stmt-switch, cross-module `mod_a` enum + `pick`.
- **B** → anonymous `.plus`/`.minus`/`.star` case-label form (enum_literal case
  values), qualified discriminant passed as argument.
- **C** → nesting: enum stmt-switch inside `if` inside `while`, three iterations,
  per-iteration print.
- **D** → enum-to-int conversion print via `@intCast(i32, @enumToInt(...))`
  (dialect supports `@enumToInt`).

## No GREEN impact

Fixture is new-only. gol MD5 spot-check from repo root unchanged:
`4afb203fdde7a880ec6e7aed32543691`.
