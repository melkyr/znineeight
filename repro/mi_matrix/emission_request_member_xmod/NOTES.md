# emission_request_member_xmod — RED fixture for the 194-closeout `request for member` class (R3, 22 errors)

Task R3 (2026-08-22). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`
(HEAD b5e3b7eb; R1/R2 did not rebuild it). Build recipe identical to R1/R2: emit with
`--dump-c89`, compile emitted C with `gcc -m32 -std=c89`.

## Purpose

Full-graph (3-module) reproducer of the self-compile residual class
**`request for member '<field>' in something not a structure or union`**
(22 errors — lower_1EB7D337.c 19, semantic_analyzer 3), e.g.
`lower_1EB7D337.c:62594:17: error: request for member 'is_self' in something not a
structure or union`, matching `zT_2268 = ci.is_self;`.

## Trigger design (minimal, spec-valid, full-graph)

Same name-keyed-conflation family as R1 (assign) and R2 (zT undeclared): two
same-named locals of different types in disjoint scopes collapse to one C local
typed first-seen. R3 flips the R2 order — a **scalar** local named `ci` comes
FIRST (loop counter `var ci: usize = 0;`, mirroring `lowerStmt` lower.zig:4670),
and a **struct** capture `ci` (a `CallInfo`, mirroring the `if (tci) |ci|` capture
lower.zig:4783) comes LATER. The emitted C declares `unsigned int ci;` (the scalar),
then emits field accesses `ci.is_self`, `ci.args_count`, `ci.result`, ... on that
C local → gcc `request for member`.

The self-compile `lowerStmt` (lower.zig:4277) has exactly this shape:
- `var ci: usize = 0;` loop counter in the switch-case prong enumeration (line 4670)
- `var tci = findTailCall(self, val);` (line 4782) and `if (tci) |ci| { ... ci.is_self ... ci.args_count ... ci.result ... ci.callee ... }` (lines 4783-4824)

The two `ci` names are legal Zig shadowing (disjoint scopes); `zig1` accepts the
program rc=0 with no diagnostics.

## Fixture (verbatim)

`mod_a.zig` (the `CallInfo` struct type + `Emitter` + a `findTailCall`-like helper):
```zig
const std = @import("std");

pub const TypeId = u32;

pub const CallInfo = struct {
    is_self: u8,
    is_indirect: u8,
    is_extern: u8,
    callee: u32,
    module_id: u32,
    args_start: u32,
    args_count: u32,
    result: u32,
    return_type: u32,
    call_block_idx: u32,
    call_inst_idx: u32,
};

pub const Emitter = struct {
    x: u32,
    param_count: u32,
    return_type: u32,
};

pub fn findTailCall(emitter: *Emitter, ret_temp: u32) ?CallInfo {
    _ = emitter;
    if (ret_temp == 1) {
        return CallInfo{ ... };
    }
    return null;
}
```
`mod_b.zig` (the emission site — scalar `ci` first, struct capture `ci` later):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const CallInfo = mod_a.CallInfo;
const Emitter = mod_a.Emitter;

fn resolveTempName(emitter: *Emitter, t: u32) u32 { _ = emitter; return t; }

pub fn emitInst(emitter: *Emitter, ret_temp: u32) u32 {
    var acc: u32 = 0;
    var p: u32 = 0;
    while (p < 3) : (p += 1) {
        var ci: usize = 0;
        while (ci < 2) : (ci += 1) {
            acc = acc + @intCast(u32, ci);
        }
    }
    var tci = mod_a.findTailCall(emitter, ret_temp);
    if (tci) |ci| {
        if (ci.is_self == 1 and ci.args_count == emitter.param_count) {
            acc = resolveTempName(emitter, ci.result);
            acc = acc + ci.callee + ci.module_id + ci.args_start + ci.return_type + ci.call_block_idx;
        }
    }
    return acc;
}
```
`main.zig`:
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var em = mod_a.Emitter{ .x = 0, .param_count = 2, .return_type = 42 };
    var r = mod_b.emitInst(&em, 1);
    std.io.printInt(@intCast(i32, r));
}
```
Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 modules + std.

All field accesses (`ci.is_self`, `ci.args_count`, `ci.result`, `ci.callee`,
`ci.module_id`, `ci.args_start`, `ci.return_type`, `ci.call_block_idx`) are valid
Zig on a `CallInfo` capture; the scalar `ci` is a disjoint-scope loop counter.

## RED evidence (measured 2026-08-22, /tmp/fx_subfolder/zig1 @ b5e3b7eb)

```
$ rm -rf /tmp/r3_194/*; timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 \
    --output-dir /tmp/r3_194 repro/mi_matrix/emission_request_member_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd /tmp/r3_194 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class `request for member '<field>' in something not a structure
or union`, 8 hits in `mod_b_66251B3F.c`):
```
mod_b_66251B3F.c:119:15: error: request for member 'is_self' in something not a structure or union
mod_b_66251B3F.c:126:15: error: request for member 'args_count' in something not a structure or union
mod_b_66251B3F.c:138:15: error: request for member 'result' in something not a structure or union
mod_b_66251B3F.c:143:15: error: request for member 'callee' in something not a structure or union
mod_b_66251B3F.c:145:15: error: request for member 'module_id' in something not a structure or union
mod_b_66251B3F.c:147:15: error: request for member 'args_start' in something not a structure or union
mod_b_66251B3F.c:149:15: error: request for member 'return_type' in something not a structure or union
mod_b_66251B3F.c:151:15: error: request for member 'call_block_idx' in something not a structure or union
```
Byte-for-byte identical to the self-compile text, e.g.
`lower_1EB7D337.c:62594:17: error: request for member 'is_self' in something not a
structure or union` (self) vs `mod_b_66251B3F.c:119:15: error: request for member
'is_self' in something not a structure or union` (fixture) — same message string.

Emitted C (the conflation signature):
```
    unsigned int ci;          // decl — scalar, first-seen (usize loop counter)
    zT_ADEBC620_Opt_27 tci;
...
    z_bb_1:  ci = zT_12;      // scalar loop counter
    ...
    zT_27 = ci.is_self;       // struct-capture field access on scalar-typed ci
    zT_31 = ci.args_count;
    zT_36 = ci.result;
    zT_38 = ci.callee;
    zT_40 = ci.module_id;
    zT_42 = ci.args_start;
    zT_44 = ci.return_type;
    zT_46 = ci.call_block_idx;
```
Marker run (`--markers`): the scalar loop counter registers local name 55 (`ci`)
as usize T30 (`P1:t7T30N55`), then the capture reuses the same name; the
`load_field` insts carry base 26 (`tci.value`) with the capture's `name_id` set,
so emission writes `ci.<field>` via `mangleLocalName` (`sf/src/c89_emit.zig:4565`).
The single C local `ci` keeps the first-seen scalar type.

## Probable mechanism (HYPOTHESIS — I may overturn this)

Same name-keyed-conflation family as R1/R2. The emission pass
(`sf/src/c89_emit.zig:2642-2699`) collects `decl_local` temps by `name_id` into
`local_name_ids[]`; a later `decl_local` with a **duplicate** `name_id` is skipped
(`ldup`, c89_emit.zig:2669-2673) and the C declaration keeps the FIRST-seen type.
Here the first-seen `ci` is the scalar loop counter (`var ci: usize = 0;`), so the
C header declares `unsigned int ci;`. The later optional-capture `ci` (`if (tci) |ci|`,
`CallInfo` struct) never gets its own declaration, but the `load_field` instructions
for `ci.is_self`/`ci.args_count`/... carry the capture's `name_id`; emission writes
`ci.<field>` (c89_emit.zig:4565, mangleLocalName branch) against the scalar-typed
C local → gcc `request for member '<field>' in something not a structure or union`.

Order matters: R2 (zT-undeclared) had the struct capture FIRST and a scalar
shadowing local SECOND → field reads resolved scalar → VOID temp, skipped decl,
referenced-but-undeclared. R3 (request-for-member) has the scalar FIRST and the
struct capture SECOND → field reads stay struct-typed, so the `load_field` is
emitted as-is, but against the stale first-seen scalar declaration.

Fix candidates (untested): disambiguate same-named captures/locals that are actually
different types (scope-correct local identity rather than flat name_id dedup in
`emitHoistedDecls`); or emit the capture's true type declaration alongside; or have
lowering assign capture temps a distinct name when a same-named local already exists.

## Expected post-fix result

After the fix, the `ci` capture in `if (tci) |ci|` gets its own struct-typed C
declaration (or a disambiguated name), so `ci.is_self` etc. compile; `gcc -c` rc=0
and the binary prints the resolveTempName/getTypeInfo-style sum.
