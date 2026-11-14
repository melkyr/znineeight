# emission_void_temp_enum_xmod — E₂ enum-literal-arg investigation (GREEN: clobber absorbed, NOT RED)

Task R-VAR (2026-08-21, AMENDMENT 7 Ruling 4). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

> **Status: NOT a RED fixture — reported BLOCKED in `task-R-VAR-residual-report.md`.**
> The enum-literal-arg clobber (AMENDMENT 7 Ruling 4 / design spec claim) does NOT produce
> `'zT_<n>' undeclared` in the direct-call shape. Retained here as the record of the investigation
> (what was tried, what was found, what the clobber actually does).

## Purpose
Attempted variation of the E₂ base fixture: a direct call passing a **plain enum-literal arg** (NO
union literal), isolating the enum-literal clobber claimed by AMENDMENT 7 Ruling 4 / the residual
design spec ("`semanticAnalyzerResolveEnumLiteral` with `topExpectedType==0` returns VOID
(`:1068-1070`) in loop 2 → also voided"). Expected RED: `'zT_<n>' undeclared` on the enum-literal
temp. **Result: GREEN** — the clobber IS real (the resolved type is voided) but the enum-literal
lowering (`lower.zig:1501` `literalTempType`) falls back to `INT_LIT` for voided literals, so the
temp is declared as `int` and compiles.

## Fixture (verbatim) — the closest direct-call enum-literal-arg shape
`mod_a.zig`:
```zig
pub const TokenKind = enum(u8) { eof, ident, lparen, rparen };
```
`mod_b.zig`:
```zig
const mod_a = @import("mod_a.zig");
const TokenKind = mod_a.TokenKind;

fn kindNum(kind: TokenKind) i32 {
    return switch (kind) {
        .eof => 0,
        .ident => 1,
        .lparen => 2,
        .rparen => 3,
    };
}

pub const Lexer = struct {
    pos: u32,
};

pub fn nextToken(self: Lexer) i32 {
    return kindNum(.eof) + @intCast(i32, self.pos);
}
```
`main.zig`:
```zig
const std = @import("std");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var lex = mod_b.Lexer{ .pos = 0 };
    std.io.printInt(mod_b.nextToken(lex));
}
```
Import graph: `main → mod_b → mod_a`. 3 modules + std.

## Result (measured 2026-08-21, /tmp/fx_subfolder/zig1) — GREEN
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rvE1 main.zig
rc=0
$ cd /tmp/rvE1 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=0
```
Emitted C — the `.eof` literal temp degrades to a plain `int` (NOT undeclared); the arg temp is
typed `TokenKind` from `call_arg_types` (loop 1), so the copy is int→enum (C-compatible):
```
int zF_86E7799D_nextToken(zT_138FFB41_Lexer self) {
    zT_EAC3E484_TokenKind zT_1;
    int zT_2;              // ← enum-literal temp: resolved type VOID → INT_LIT fallback
    ...
    zT_2 = 17;             // ← .eof value
    zT_1 = zT_2;
    zT_3 = zF_836E9911_kindNum(zT_1);
```

## Investigation log (what was tried)
1. `setKind(TokenKind.eof)` — **qualified** member-access arg: GREEN. `TokenKind.eof` is a
   `field_access` (not an `enum_literal` AST node); it materializes the enum global constant
   `zT_EAC3E484_TokenKind_eof`, never voided.
2. `setKind(.eof)` — **bare** enum-literal arg: GREEN. The bare literal IS the `enum_literal` node;
   loop 2 voids its resolved type, but `literalTempType` (`lower.zig:1301`) converts VOID →
   `TYPE_INT_LIT`, so the temp is declared `int` and compiles.
3. `var k: Kind = .eof;` — var-decl init: GREEN (emits sema warning `warning[3000]: type mismatch ...
   source: void` — direct evidence the enum literal WAS voided), still compiles.
4. Bare `.eof` inside the exact lexer shape (`makeToken(.eof, self.pos, .{ .none = {} })`): RED —
   but on the **union-literal** temp (`zT_6`/`zT_8` undeclared), NOT the enum temp (which is the
   declared `int zT_4`). The RED is the base fixture's union-literal clobber, only renumbered.
5. `@enumToInt(.eof)` through a same-module call: GREEN, same int-degradation.

## Conclusion / why this cannot be RED
The `undeclared` symptom requires a temp whose type is VOID at emission. Union-literal (struct_init)
temps are typed straight from the voided resolved type (`lower.zig:3594-3595`) → VOID → skipped.
Enum-literal temps go through `literalTempType` (`lower.zig:1301`) which substitutes `INT_LIT` for
VOID/UNDEFINED → declared `int` → never undeclared. So the enum-literal-arg clobber manifests only
as silent **type degradation** (TokenKind → int) plus the `source: void` sema warning — NOT as a
compile error. The merged-loop fix still matters for enum-literal args (it restores the enum-typed
temp and suppresses the degradation), but no direct-call enum-literal-arg fixture can be RED.
Per the task rule ("do NOT force a wrong-class fixture"), this variation is reported BLOCKED.

## Control (documented, not a fixture)
Indirect call `mod_a.makeToken(...)` (FN4 path) is known GREEN — the base E₂ fixture NOTES
(iteration step 3) document this.
