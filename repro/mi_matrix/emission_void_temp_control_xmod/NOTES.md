# emission_void_temp_control_xmod — GREEN control for the E/E₂ void-temp family

Task A-ADD (2026-08-24), R2/R1 self-compile closeout plan (AMENDMENT 1). Compiler under test:
`/tmp/fx_subfolder/zig1` (current; no rebuild since HEAD `5267f5e6`). Build recipe identical to the
other `emission_*_xmod` fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

> **Status: GREEN control (NOT a RED fixture).** Expected-GREEN per A-ANALYZE §5.2 E/E₂ row.

## Purpose

Regression gate for the **E/E₂ void-temp / zT-undeclared** family (fixtures
`emission_void_temp_xmod`, `emission_void_temp_multi_xmod`, `emission_void_temp_payload_xmod`,
`emission_void_temp_scale_xmod`): a **union-literal call arg** in a **while loop** and via a **fn-ptr
(indirect) call** (probes GREEN: `pv4`, `pv2`). Guards the shapes that used to produce
`'zT_<n>' undeclared (first use in this function)` when a union-literal arg's resolved type stayed
VOID and the temp declaration was skipped.

## Fixture (verbatim)

`mod_a.zig` (types + callee — the union-literal arg target, cross-module; E₂ requires a same-module
call, so the CALL site is in mod_b and the callee is imported — cross-module probe `pv1` is GREEN):
```zig
pub const TokenKind = enum(u8) { eof, ident, lparen, rparen };
pub const TokenValue = union(enum) { none: void, ident: struct { name: []const u8 } };
pub const Token = struct { kind: TokenKind, start: u32, value: TokenValue };

pub fn makeToken(kind: TokenKind, start: u32, value: TokenValue) Token {
    return .{ .kind = kind, .start = start, .value = value };
}
```

`mod_b.zig` (THE guarded shapes — union-literal `.none` arg in a while loop and through a fn-ptr):
```zig
const mod_a = @import("mod_a.zig");
const TokenKind = mod_a.TokenKind;
const TokenValue = mod_a.TokenValue;
const Token = mod_a.Token;

pub fn inWhile() u32 {
    var i: u32 = 0;
    var acc: u32 = 0;
    while (i < 2) : (i += 1) {
        var t = mod_a.makeToken(TokenKind.eof, i, .{ .none = {} });
        acc = acc + t.start;
    }
    return acc;
}

pub fn viaFnPtr() u32 {
    var f: fn (TokenKind, u32, TokenValue) Token = mod_a.makeToken;
    var t = f(TokenKind.eof, 0, .{ .none = {} });
    return t.start;
}
```

`main.zig` (graph filler — consumes both fns so they lower):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var r = mod_b.inWhile() + mod_b.viaFnPtr();
    std.io.printInt(@intCast(i32, r));
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 fixture modules + std.

## GREEN evidence (measured 2026-08-24, /tmp/fx_subfolder/zig1)

```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/aadd/diag_emission_void_temp_control_xmod \
    repro/mi_matrix/emission_void_temp_control_xmod/main.zig
zig_rc=0
$ cd <out> && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=0
```

Benign (documented, not a failure): the `var f: fn (…) Token = mod_a.makeToken;` fn-ptr init in
`viaFnPtr` emits the known `warning[3000]: type mismatch … source: function, target: pointer`
(fn-ptr init degrades; gcc still rc=0).

## Root-cause pin / family guarded

E/E₂ void-temp family. The AMENDMENT-7 merged arg loop resolves each call arg once with a typed temp
(no VOID-typed union-literal arg temps → no skipped decl), and typed load_field temps fix the `if (i.a)
|v|` capture path. **GREEN today because the fixes are shape-general** — they cover union-literal args
in any position (direct call, fn-ptr call, in-loop, cross-module).

## Expected post-fix result

Stays GREEN; this control catches a regression in union-literal call-arg temp typing (while-loop and
fn-ptr positions).
