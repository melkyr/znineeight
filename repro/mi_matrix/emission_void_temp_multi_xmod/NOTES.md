# emission_void_temp_multi_xmod — RED fixture for residual E₂ (two union-literal args in one call)

Task R-VAR (2026-08-21, AMENDMENT 7 Ruling 4). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Variation of the E₂ base fixture (`emission_void_temp_scale_xmod`): a single call passing **TWO
union-literal args** (`.{ .none = {} }` and `.{ .ident = .{ .name = "x" } }`). Each literal's temp is
voided independently by the FN1 double-resolution clobber, so **two** `'zT_<n>' undeclared` errors
appear (one per arg). Proves the merged-loop fix must resolve each arg independently (not conflate
them onto one typed temp) — the exact AMENDMENT 7 Ruling 1 concern ("resolve each arg exactly once").

## Fixture (verbatim)
`mod_a.zig`:
```zig
pub const TokenKind = enum(u8) { eof, ident, lparen, rparen };

pub const TokenValue = union(enum) {
    none: void,
    ident: struct { name: []const u8 },
};

pub const Token = struct {
    kind: TokenKind,
    start: u32,
    value: TokenValue,
};
```
`mod_b.zig` (caller + callee in the same module — the required E₂ trigger shape):
```zig
const mod_a = @import("mod_a.zig");
const Token = mod_a.Token;
const TokenKind = mod_a.TokenKind;
const TokenValue = mod_a.TokenValue;

fn combine(a: TokenValue, b: TokenValue) Token {
    return .{ .kind = .eof, .start = 0, .value = a };
}

pub const Lexer = struct {
    pos: u32,
};

pub fn nextToken(self: Lexer) Token {
    return combine(.{ .none = {} }, .{ .ident = .{ .name = "x" } });
}
```
`main.zig`:
```zig
const std = @import("std");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var lex = mod_b.Lexer{ .pos = 0 };
    var t = mod_b.nextToken(lex);
    std.io.printInt(@intCast(i32, t.start));
}
```
Import graph: `main → mod_b → mod_a`. 3 modules + std.

## RED baseline (measured 2026-08-21, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rvE3 main.zig
rc=0
$ cd /tmp/rvE3 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class E₂, `'zT_<n>' undeclared`, **two independent temps**):
```
mod_b_E9AEBB89.c:31:12: error: 'zT_3' undeclared (first use in this function); did you mean 'zT_9'?
mod_b_E9AEBB89.c:37:12: error: 'zT_5' undeclared (first use in this function); did you mean 'zT_9'?
```
Emitting C — each union-literal arg is copied into its arg temp from a NEVER-DECLARED literal temp:
```
zT_1 = zT_3;              // ← arg `a` = `.{ .none = {} }` literal temp zT_3 — undeclared
zT_7 = "x";
zT_9 = 1;
zT_8.ptr = zT_7;
zT_8.len = zT_9;
zT_6.name = zT_8;
zT_2 = zT_5;              // ← arg `b` = `.ident = .{ .name = "x" }` literal temp zT_5 — undeclared
zT_10 = zF_3884038A_combine(zT_1, zT_2);
```
Each arg's literal is voided and omitted independently; the arg copy (`zT_1 = zT_3`, `zT_2 = zT_5`)
still references them.

## Root cause pinned
Same E₂ mechanism: FN1 loop 2 (`semantic_analyzer.zig:860-865`) re-resolves every arg untyped; each
union-literal arg's struct-init temp (`lower.zig:3594-3595`) inherits the voided resolved type. Two
args → two independent undeclared temps. This is the shape the merged loop must resolve per-arg.

## Expected post-fix result
After the merged loop, both args resolve once, typed → `zT_3` and `zT_5` are both declared with
`TokenValue`; `gcc -c` rc=0.
