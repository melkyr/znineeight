# emission_orelse_xmod — RED fixture for the 194-closeout `orelse` class (R-ORELSE, 6 errors)

Task R-ORELSE (2026-08-23). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`
(current; R tasks have not rebuilt it). Build recipe identical to the other emission_*_xmod
fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

## Purpose

Full-graph (3-module: main/mod_a/mod_b + std) reproducer of the self-compile
residual `orelse` class (6 errors): a function **with a parameter** whose body is
`var x = optional_ret() orelse return null;` (and a `continue` variant inside a
loop) emits `zT_N = <first-function-param>;` on the orelse-null path instead of
jumping away — the orelse RHS value-flow is hijacked by the first param.

## Self-compile lines reproduced (source of truth: `/tmp/emit_errs_fb3.txt`)

```
import_resolver_58BB752E.c:275:13: error: incompatible types when assigning to type 'zT_8F083A69_Slice_zT_0B42B2F8_u' from type 'zT_072B53A6_ModuleRegistry *'
module_registry_03A5D1FC.c:922:13: error: incompatible types when assigning to type 'zT_8F083A69_Slice_zT_0B42B2F8_u' from type 'zT_4DB1475B_ModuleResolver *'
module_registry_03A5D1FC.c:950:13: error: incompatible types when assigning to type 'zT_8F083A69_Slice_zT_0B42B2F8_u' from type 'zT_4DB1475B_ModuleResolver *'
module_registry_03A5D1FC.c:967:13: error: incompatible types when assigning to type 'zT_8F083A69_Slice_zT_0B42B2F8_u' from type 'zT_4DB1475B_ModuleResolver *'
pal_388A8A1B.c:172:13: error: incompatible types when assigning to type 'void *' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
pal_388A8A1B.c:379:13: error: incompatible types when assigning to type 'void *' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
```

Every site is the orelse null-path assigning the **first function parameter** into
the join temp (`zT_51 = reg;` in `moduleScanDiscover`'s `orelse continue` at
import_resolver.zig:40; `zT_10 = self;`/`zT_24 = self;`/`zT_32 = self;` in
`moduleResolverTryDir`'s three `orelse return null` at module_registry.zig:170/172/173;
`zT_31 = path;`/`zT_30 = path;` in `readFile`/`fileExists`'s `orelse return null`/
`orelse return false` at pal.zig:29/58).

## Fixture (verbatim)

`mod_a.zig` (the optional-returning callee — `maybe(seed)` yields null for
`seed <= 0`):
```zig
pub fn maybe(seed: i32) ?i32 {
    if (seed > 0) return seed;
    return null;
}
```

`mod_b.zig` (THE emission site — one fn per RHS shape, each with a parameter
`prefix: []const u8` whose C type (Slice) clashes with the orelse payload `i32`):
```zig
const mod_a = @import("mod_a.zig");

pub fn useReturn(prefix: []const u8, seed: i32) ?i32 {
    var x = mod_a.maybe(seed) orelse return null;
    return x;
}

pub fn useContinue(prefix: []const u8, seed: i32) i32 {
    var acc: i32 = 0;
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        var x = mod_a.maybe(seed) orelse continue;
        acc += x;
    }
    return acc;
}
```

`main.zig` (graph filler — consumes both fns so they lower):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var r = mod_b.useReturn("pre", 7);
    var c = mod_b.useContinue("pre", 7);
    var t = r orelse 0;
    std.io.printInt(t + c);
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 fixture modules + std.
`zig1` accepts the program with **rc=0 and no diagnostics**.

## Why it triggers the class

Both orelse RHS shapes (`return null` / `continue`) are **statements**, lowered only
by `lowerStmt` (`lower.zig:4847` return_stmt, `:4955` continue_stmt), never by
`lowerExprImpl` (`:1494`). The orelse_expr arm (`lower.zig:3557-3609`) lowers the
RHS with `var null_val = lowerExpr(self, node.child_1)` (`:3574`); `lowerExprImpl`
has no return/continue arm, falls through to the tail `else { return @intCast(u32, 0); }`
(`:4296-4297`). Temp **0 is the first function parameter** — `lowerFn` allocates param
temps first via `nextTemp` (`lower.zig:5730-5732`) and resets `temp_counter` to
`params_count` afterward (`:5757`). So `null_val` is the first param's temp, and
`materializeInto(self, null_val, rt, oe_int)` (`:3589`) returns it unchanged, then
`emitInst(.assign { dst = join_temp, src = null_val })` (`:3590`) emits
`zT_N = <first-param>;`.

The self-compile evidence (`zT_51 = reg;` in import_resolver, `zT_10 = self;` in
module_registry, `zT_31 = path;` in pal) is byte-identical in shape: the orelse
null-path assigns the first function parameter. gcc rejects the type clash.

## RED evidence (measured 2026-08-23, /tmp/fx_subfolder/zig1)

```
$ rm -rf /tmp/orelse_repro && mkdir -p /tmp/orelse_repro
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/orelse_repro \
    repro/mi_matrix/emission_orelse_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd /tmp/orelse_repro && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```

Exact gcc errors:
```
mod_b_D1E39223.c:18:12: error: incompatible types when assigning to type 'int' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
   18 |     zT_6 = prefix;
      |            ^~~~~~
mod_b_D1E39223.c:85:13: error: incompatible types when assigning to type 'int' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
   85 |     zT_14 = prefix;
      |             ^~~~~~
```

Emitted C (null path, `useReturn`):
```
z_bb_1:
zT_6 = prefix;              <- THE BUG: orelse RHS "return null" should jump away
goto z_bb_3;
z_bb_2:
zT_7 = zT_4.value;
zT_6 = zT_7;
goto z_bb_3;
z_bb_3:
x = zT_6;
```

Message class (`incompatible types when assigning to type '<join>' from type
'<first-param>'`) byte-identical to the self-compile lines; only the concrete
types differ (fixture: Slice → `int`; self-compile: ModuleRegistry*/ModuleResolver*
→ Slice, Slice → `void *`) because the fixture's first param is a `[]const u8`
slice and the join is `i32`. The fixture produces exactly the 2 target-class errors
and nothing else (gcc total = 2). Also confirms the RHS control flow is silently
lost: the emitted C contains no `return`/`continue` for the null path at all.

## Probable mechanism (HYPOTHESIS — I may overturn this)

1. **`lowerExpr` cannot lower return/continue** — `return_stmt`/`continue_stmt`
   arms exist only in `lowerStmt` (`lower.zig:4847/:4955`); `lowerExprImpl`
   (`:1494`) has no case and returns `@intCast(u32, 0)` from its tail `else`
   (`:4296-4297`).
2. **Temp 0 == first function parameter.** `lowerFn` allocates param temps with
   `nextTemp` before the body and resets `temp_counter = params_count` after
   (`lower.zig:5730-5757`), so the sentinel `0` collides with param 0's temp.
3. **orelse arm materializes it anyway.** `lower.zig:3574-3580`: `null_val =
   lowerExpr(child_1)` (= temp 0), `materializeInto` (no-op since `src_ty == 0`'s
   type vs expected differ with no optional/error-union layers → returns src_temp),
   then `emitInst(.assign { dst = join_temp, src = null_val })`. The null-path
   block is NOT terminated (return/continue was never lowered), so the join
   assignment and fall-through `goto join_bb` are emitted, and `x = join_temp`
   carries the first param.
4. gcc sees `zT_N = <first-param>;` with mismatched C types →
   `incompatible types when assigning`. The `orelse return null` / `orelse continue`
   control flow is silently lost (the return/continue never appears in the C).

Fix candidates (untested): in the orelse_expr arm, treat a lowered `null_val` from a
terminating RHS (return/break/continue) as "no join assignment" — guard the
`emitInst(.assign join_temp = null_val)` and the fall-through jump on
`self.block_terminated`, and/or have `lowerExpr` recognize return/continue nodes and
delegate to `lowerStmt` returning a sentinel (e.g. `TEMP_NONE`) instead of temp 0.
Same pattern likely afflicts the catch_expr arm (`lower.zig:3530-3556`), whose
`err_val = lowerExprOrBlock` already handles return/continue but may share the
sentinel-0 hazard.

## Expected post-fix result

After the fix, the orelse-null path emits no `zT_N = <param>`; the `return null` /
`continue` control flow is preserved (jump to exit / loop header), and `x = join_temp`
is only reached on the ok path. `gcc -c` rc=0.
