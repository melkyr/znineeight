# emission_void_temp_scale_xmod — RED fixture for residual E₂ (void-temp producer: lexer call-argument shape)

Task R (2026-08-20). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Full-graph reproducer of **residual E₂** from the self-compile-residual-closeout
spec: the **lexer call-argument void temp** — the dominant E₂ producer (69 of
137 self-compile errors at HEAD `8d9af49d`). A tagged-union **literal** passed
as a call argument lowers to a temp whose type stays void, so the emission pass
skips its declaration while the emitted instruction stream still references it →
gcc `'zT_<n>' undeclared`.

Self-compile evidence (`lexer_23F0DAD4.c`):
```
zT_7 = zT_12;                       // zT_12 = the `.{ .none = {} }` arg temp — undeclared
zT_14 = zF_369DD718_lexerMakeToken(zT_4, zT_5, zT_6, zT_7);
```
matches the lexer source `lexerMakeToken(self, TokenKind.eof, self.pos, .{ .none = {} })`.

## Fixture (verbatim)
`mod_a.zig` (the token types):
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
`mod_b.zig` (`makeToken` + the lexer's `nextToken` — the call-arg void-temp site):
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
    return makeToken(TokenKind.eof, self.pos, .{ .none = {} });
}
```
`main.zig`:
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var lex = mod_b.Lexer{ .pos = 0 };
    var t = mod_b.nextToken(lex);
    std.io.printInt(@intCast(i32, t.start));
}
```
Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 modules + std.

## RED baseline (measured 2026-08-20, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rE2 main.zig
rc=0
$ cd /tmp/rE2 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc error (class E₂, `'zT_<n>' undeclared`):
```
mod_b_1718E5AA.c:31:12: error: 'zT_8' undeclared (first use in this function); did you mean 'zT_7'?
   31 |     zT_3 = zT_8;
```
Emitting C (the lexer call-arg signature):
```
/* nextToken */
zT_3A355BD2_Token zF_86E7799D_nextToken(zT_138FFB41_Lexer self) {
    zT_EAC3E484_TokenKind zT_1;
    unsigned int zT_2;
    zT_85CBA4DB_TokenValue zT_3;   // the arg temp for `value`
    ...
    zT_3 = zT_8;                   // ← zT_8 = the `.{ .none = {} }` literal temp — NEVER DECLARED
    zT_10 = zF_79B10724_makeToken(zT_1, zT_2, zT_3);
    return zT_10;
}
```
`zT_8` is referenced (as the union-literal source for the `value` arg) but is
absent from `nextToken`'s hoisted-temp declaration block: the type-inference pass
(`emitHoistedDecls`) never assigns the union-literal temp a concrete type, the
void-skip guard omits its declaration, and gcc reports it undeclared.

## Iteration (minimal-trigger search, documented per the task)
1. **Single-module shape** (types + `makeToken` + `nextToken` all in one module):
   RED immediately — `mod_a.c:25:12: error: 'zT_6' undeclared` with the identical
   `zT_3 = zT_6; makeToken(zT_1, zT_2, zT_3)` shape. Trigger = a tagged-union
   literal (`.{ .none = {} }`) passed as a call argument.
2. **Variant check**: replacing the `none: void` variant with `none: u8` still
   RED (`'zT_6' undeclared`) — the trigger is the union-*literal call argument*,
   not specifically the `void` payload. Kept `none: void` to match the lexer
   verbatim.
3. **Cross-module split #1** (`makeToken` in `mod_a`, `nextToken` in `mod_b`,
   cross-module call `mod_a.makeToken(...)`): **GREEN** — the emitted C
   materialized the literal (`zT_10 = 0; zT_8.tag = zT_10; zT_3 = zT_8;`), so the
   void temp did NOT occur. Not usable.
4. **Final 3-module split** (`makeToken` + `nextToken` together in `mod_b`,
   types in `mod_a`, same-module call): RED — the exact lexer shape. The trigger
   requires the union-literal call site and its callee in the same module.

## Root cause pinned
`sf/src/c89_emit.zig` `emitHoistedDecls` (`:2521-3076`): the type-inference pass
(`:2617-2968`) leaves the tagged-union-literal call-arg temp without a concrete
type, and the void-skip guard (`:3061`) omits its declaration while the emitted
`zT_3 = zT_8;` still references it. E₂ of the spec (lexer producer).

## Expected post-fix result
After the E₂ fix (type-inference pass assigns the union-literal call-arg temp its
concrete `TokenValue` type so its declaration is emitted), `zT_8` is declared in
`nextToken`; `gcc -c` rc=0.
