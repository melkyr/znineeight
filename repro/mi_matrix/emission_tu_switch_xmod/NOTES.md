# emission_tu_switch_xmod — GREEN runtime-correctness fixtures for tagged-union switch forms (A/B/C)

Task 4 R-TUSWITCH (2026-08-25) of the Fidelity-Gap Fix plan
(`docs/superpowers/plans/2026-08-25-fidelity-gap-enum-switch-fix-plan.md`).
Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1` (the WORKING
reference built by zig0). Consumes the Task 2 fix (commit `5ec13efb` — qualified
enum-literal stmt-switch cases now collect). Build recipe: emit with
`--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`,
link `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c`, run.

## Purpose

Runtime-correctness coverage for the tagged-union (union(enum)) switch family.
Three shapes in one build, each printing an expected value on its own line:
- **A** — `switch (u)` over a tagged union with anonymous `.jump => |payload|`
  capture, access the payload value, print. CROSS-MODULE: the union value is
  produced by `mod_a.make_jump()`.
- **B** — tagged-union switch + tag-to-int. Uses the dialect's working tag-access
  idiom (switch assigns an int per prong, then prints it) — mirrors
  `sf/src/tests/test_union_dispatch.zig:12-24`. NOT direct `@enumToInt(u)`: the
  dialect lowers `@enumToInt` on a union value to `(int)u` (gcc "aggregate value
  used where an integer was expected"), and a direct `.tag` read lowers to an
  uninitialized temp (both latent, out of scope — see below).
- **C** — nested: `for` inside `if` inside `switch (tagged union)`, accessing the
  captured payload value, print.

All prints go through `std.io.printInt`, separated by `std.io.print("\n")`.

## Fixture (verbatim)

`mod_a.zig`:
```zig
pub const U = union(enum) {
    jump: u32,
    ret: void,
};

pub fn make_jump() U {
    return U{ .jump = @intCast(u32, 42) };
}

pub fn make_ret() U {
    return U{ .ret = {} };
}
```
`main.zig`:
```zig
const std = @import("std.zig");
const mod_a = @import("mod_a.zig");

const U = union(enum) {
    jump: u32,
    ret: void,
};

pub fn main() void {
    var ua = mod_a.make_jump();
    switch (ua) {
        .jump => |val| {
            std.io.printInt(val);
            std.io.print("\n");
        },
        .ret => {
            std.io.printInt(@intCast(u32, 0));
            std.io.print("\n");
        },
        else => {},
    }

    var ub = U{ .jump = @intCast(u32, 9) };
    var tag: u32 = @intCast(u32, 0);
    switch (ub) {
        .jump => |v| {
            tag = @intCast(u32, 1);
        },
        .ret => {
            tag = @intCast(u32, 2);
        },
        else => {},
    }
    std.io.printInt(tag);
    std.io.print("\n");

    var uc = U{ .jump = @intCast(u32, 5) };
    var arr: [2]u32 = [2]u32{ @intCast(u32, 10), @intCast(u32, 20) };
    var sum: u32 = @intCast(u32, 0);
    switch (uc) {
        .jump => |d| {
            if (d < @intCast(u32, 10)) {
                for (arr) |x| {
                    sum += d + x;
                }
            }
        },
        .ret => {},
        else => {},
    }
    std.io.printInt(sum);
    std.io.print("\n");
}
```

## GREEN evidence (measured 2026-08-25, /tmp/fx_subfolder/zig1)

```
$ cd /workspace/znineeight/repro/mi_matrix/emission_tu_switch_xmod
$ rm -rf /tmp/fx_tuout && mkdir -p /tmp/fx_tuout
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fx_tuout main.zig
dump rc=0
$ cd /tmp/fx_tuout && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc rc=0
$ gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include *.o \
    /workspace/znineeight/sf/src/include/zig_runtime.c \
    /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/fx_tubin
link rc=0
$ /tmp/fx_tubin
42
1
40
run rc=0
```

All three `switch` statements in `main_3DF5832C.c` carry real case labels
(`case 0/1 -> z_bb_N`, lines 70-72, 107-109, 157-159). Line 1 = A cross-module
payload `42`; line 2 = B tag-to-int `1` (jump prong); line 3 = C nested sum
`(5+10)+(5+20) = 40`.

## Which shape each covers

- **A** → tagged-union `switch` with anonymous label + payload capture, payload
  value accessed and printed; CROSS-MODULE variant (union produced by `mod_a`).
- **B** → tag-to-int via the dialect's working switch-set idiom (the
  `test_union_dispatch.zig` pattern), printing the discriminant as an int.
- **C** → nesting depth: `for` over an array inside `if` inside
  `switch (tagged union)`, captured payload referenced in the loop body.

## Known hazards / out of scope (documented, NOT tripped)

- ANONYMOUS labels only (`.jump => |payload|`) — this is the established,
  working form. A QUALIFIED label + capture (`mod_a.U.jump => |payload|`) would
  emit the label correctly post-Task-2 but the capture path
  (lower.zig:4019/:4841) reads `enum_value_table` keyed by `case_ec[0]`, which
  the pure-lowering fix does NOT populate for `field_access` nodes — out of
  scope, deliberately avoided here.
- Direct `@enumToInt(u)` on a union value: lowered to `(int)u` → gcc "aggregate
  value used where an integer was expected" (latent, out of scope).
- Direct `.tag` value read (`var t = u.tag;`): lowers to an uninitialized temp
  (prints garbage; latent `.tag` read-load asymmetry, out of scope). The
  switch-set idiom in shape B is the dialect's correct tag access.

## No GREEN impact

Fixture is new-only. gol MD5 spot-check from repo root unchanged:
`4afb203fdde7a880ec6e7aed32543691`.
