# emission_opt10_assign_xmod — RED fixture for the residual Opt_10 assign class (unsigned int ← Opt_10)

Task R-R1 (2026-08-24), R2/R1 self-compile closeout plan. Compiler under test:
`/tmp/fx_subfolder/zig1`. This is the last residual R1 error — the self-compile re-count after
F-R2 (array-.len) + F-ORELSEBLK (orelse-block) is exactly **1** (`incompatible types … unsigned int
← Opt_10` at lower_1EB7D337.c:31469 `zT_970 = rt;`).

## Purpose

Full-graph (3-module: main/mod_a/mod_b + std) reproducer of the **if_expr optional-capture
invisibility** class: an if-expr `if (opt) |rt| rt else <u32>` whose capture name `rt` collides with
a function-scope `var rt: ?u32`. The then-branch ident `rt` resolves to the **outer Opt_10-typed
local** instead of the u32 capture payload, so the if-expr result temp (u32) is assigned the
`Opt_10` struct → `incompatible types when assigning to type 'unsigned int' from type
'zT_BAEE192E_Opt_10'`. Byte-identical to the self-compile residual (lower_1EB7D337.c:31469).

## Fixture (verbatim)

`mod_a.zig` (the optional-returning callee — `maybeVal` yields null for `seed == 0`):
```zig
pub fn maybeVal(seed: u32) ?u32 {
    if (seed == 0) return null;
    return seed;
}
```

`mod_b.zig` (THE collision site — function-scope `var rt: ?u32` + later if-expr capture `|rt|`):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");

pub fn collide(seed: u32) u32 {
    var rt: ?u32 = mod_a.maybeVal(seed);
    var res: ?u32 = mod_a.maybeVal(seed);
    var rtype: u32 = if (res) |rt| rt else 7;
    return rtype;
}

pub fn run() void {
    var v = collide(1);
    std.io.printInt(@intCast(i32, v));
}
```

`main.zig` (graph filler — consumes `run` so `collide` lowers):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    mod_b.run();
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 fixture modules + std.
`zig1` accepts the program with **rc=0 and no diagnostics**.

## RED evidence (measured 2026-08-24, /tmp/fx_subfolder/zig1)

```
$ rm -rf /tmp/r1_opt10 && mkdir -p /tmp/r1_opt10
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r1_opt10 \
    repro/mi_matrix/emission_opt10_assign_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd /tmp/r1_opt10 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```

Exact gcc error (single, clean — byte-identical class text to the residual):
```
mod_b_95DEBDB7.c: In function 'zF_9979969D_collide':
mod_b_95DEBDB7.c:35:12: error: incompatible types when assigning to type 'unsigned int' from type 'zT_BAEE192E_Opt_10'
   35 |     zT_9 = rt;
      |            ^~
```

Residual for comparison (`/tmp/emit_errs_fc5.txt:24859`):
```
lower_1EB7D337.c:31469:14: error: incompatible types when assigning to type 'unsigned int' from type 'zT_BAEE192E_Opt_10'
31469 |     zT_970 = rt;
      |              ^~
```

The message `incompatible types when assigning to type 'unsigned int' from type
'zT_BAEE192E_Opt_10'` is byte-identical; only file/line/temp-name differ (self-compile snapshot vs
this fixture's own module hash / temp numbering).

Emitted C (mod_b_95DEBDB7.c):
```
    zT_BAEE192E_Opt_10 rt;        <- outer var rt: ?u32 (Opt_10)
    zT_BAEE192E_Opt_10 res;
    unsigned int rtype;
    unsigned int rt_1;            <- capture |rt| WAS renamed rt_1 (u32 payload)
    ...
    zT_8 = res.has_value;
    if (zT_8) goto z_bb_1; else goto z_bb_2;
    z_bb_1:
    rt_1 = res.value;             <- capture payload unwrapped into rt_1
    zT_9 = rt;                    <- THE BUG: then-branch ident `rt` reads the OUTER Opt_10 rt,
                                    NOT the capture payload rt_1
    goto z_bb_3;
    z_bb_2:
    zT_11 = 7;
    zT_12 = (unsigned int)zT_11;
    zT_9 = zT_12;
    goto z_bb_3;
    z_bb_3:
    rtype = zT_9;
```

Self-compile shape (lower_1EB7D337.c, add handler — same shape):
```
    zT_969 = res.has_value;
    if (zT_969) goto z_bb_97; else goto z_bb_98;
    z_bb_97:
    zT_971 = res.value;
    zT_970 = rt;                  <- reads outer rt (Opt_10), assigned into u32 temp zT_970
    goto z_bb_99;
    z_bb_98:
    zT_972 = 10;
    zT_970 = zT_972;
    goto z_bb_99;
    z_bb_99:
    rtype_14 = zT_970;
```

## Root-cause hypothesis

`bindOptionalCapture` (`sf/src/lower.zig:1411-1463`) registers the if-expr capture local at
**`scope_depth + 1`** (`:1460`), but the `if_expr` handler (`:3620-3687`) lowers the then/else
branch expressions at the **current `scope_depth`** (no `lowerStmtBody`/scope push — contrast the
`if_stmt` path which does push at `:4527`). Both ident resolvers — `resolveLocalSrcName`
(`:1318-1326`, filter `local_decl_scopes[li] <= self.scope_depth` at `:1323`) and `findLocalTemp`
(`:1308-1316`, same filter at `:1313`) — require `scope <= scope_depth`. The capture local (depth+1)
is therefore **invisible** to the then-branch ident read, which falls through to the nearest
same-named visible local — here the function-scope `var rt: ?u32`, an `Opt_10` struct. The
then-branch value is materialized into the if-expr result temp (`nextTemp(rtype)`, u32) → `zT_9 =
rt` → gcc: assigning an `Opt_10` into `unsigned int`. This is the same capture-invisibility /
name-collision family as `emission_assign_xmod`, but reached through the **if-expr optional-capture
path** (self-compile: the `add`-handler `if (res) |rt| rt else TYPE_U32` at lower.zig:1670 colliding
with the function-top `var rt` at lower.zig:1501, both `?u32`). Fix candidates (untested): push the
scope (mirror `if_stmt`/`lowerStmtBody`) around the if-expr branch lowering, or register the capture
at the current `scope_depth`.

## Expected post-fix result

After the fix, the then-branch ident `rt` resolves to the capture payload (`rt_1`, u32), so the
then-branch emits `zT_9 = rt_1;` (u32 = u32). `gcc -c` rc=0 and the binary prints the unwrapped
payload (1).
