# emission_void_temp_payload_xmod — RED fixture for residual E₂ (non-void-payload union-literal call arg)

Task R-VAR (2026-08-21, AMENDMENT 7 Ruling 4). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Variation of the E₂ base fixture (`emission_void_temp_scale_xmod`): a tagged-union **literal with a
NON-void payload** (`.ident = .{ .name = "x" }`, payload = `struct { name: []const u8 }`) passed as a
call argument. The base fixture only exercises the `void`-payload variant (`.{ .none = {} }`). The
FN1 double-resolution clobber (`semantic_analyzer.zig:836-867` loop 2 re-resolves each arg with
expected type 0) voids the union-literal's resolved type, the struct-init lowering
(`lower.zig:3594-3595`) types its temp straight from that voided resolved type, and the void-skip
guard in `emitHoistedDecls` (`c89_emit.zig:3061`) omits the declaration → gcc `'zT_<n>' undeclared`.
Proves the non-void-payload variant is voided identically to the `void`-payload base case.

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
`mod_b.zig` (the same-module call site — required: caller + callee in one module, per base NOTES iteration 4):
```zig
const mod_a = @import("mod_a.zig");
const Token = mod_a.Token;
const TokenKind = mod_a.TokenKind;
const TokenValue = mod_a.TokenValue;

fn makeToken(kind: TokenKind, start: u32, value: TokenValue) Token {
    return .{ .kind = kind, .start = start, .value = value };
}

pub const Lexer = struct {
    pos: u32,
};

pub fn nextToken(self: Lexer) Token {
    return makeToken(TokenKind.ident, self.pos, .{ .ident = .{ .name = "x" } });
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
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rvE2 main.zig
rc=0
$ cd /tmp/rvE2 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc error (class E₂, `'zT_<n>' undeclared`):
```
mod_b_E8676DA0.c:40:12: error: 'zT_8' undeclared (first use in this function); did you mean 'zT_9'?
   40 |     zT_3 = zT_8;
```
Emitting C — the `.ident = .{ .name = "x" }` literal temp `zT_8` is referenced but never declared
(the string slice `zT_11` and the `name` field-init `zT_9` ARE emitted, the struct temp itself is not):
```
zT_10 = "x";
zT_12 = 1;
zT_11.ptr = zT_10;
zT_11.len = zT_12;
zT_9.name = zT_11;
zT_3 = zT_8;              // ← zT_8 = the `.ident = .{ .name = "x" }` literal temp — NEVER DECLARED
zT_13 = zF_79B10724_makeToken(zT_1, zT_2, zT_3);
```

## Root cause pinned
Same E₂ as the base fixture: the FN1 double-resolution loop (`semantic_analyzer.zig:836-867`)
re-resolves the union-literal arg untyped; `semanticAnalyzerResolveStructInit` with expected type 0
returns VOID (`:1080`), and the struct-init lowering (`lower.zig:3594-3595`) takes its temp type
directly from the (now voided) resolved type → void temp → skipped declaration (`c89_emit.zig:3061`).
The payload shape (`.ident = .{ .name = "x" }` with a non-void struct payload) is voided identically
to the base `.none = {}` shape.

## Expected post-fix result
After the E₂ merged-loop fix (AMENDMENT 7 Ruling 1), the union-literal arg is resolved once, typed,
so `zT_8` is declared with the `TokenValue` type; `gcc -c` rc=0.
