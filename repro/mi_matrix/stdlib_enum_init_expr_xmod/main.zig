// stdlib_enum_init_expr_xmod — Task 11J regression: enum member initializers
// fold as comptime-known integer expressions.
//
// DEFECT (before the fix): `type_resolver.zig`'s enum evaluator
// `evalConstI64Full` had arms only for `int_literal`, `negate`, and
// `ident_expr` const chains bottoming out in a literal. Every other explicit
// initializer returned `null`, and `symbol_registrator.zig` treated `null` as
// "no explicit value" and silently kept the auto-increment ordinal. So
// `enum(u8){ A = 1 + 2 }` emitted `A = 0`, `{ A = @sizeOf(S) }` emitted `A = 0`,
// and the auto-increment followers were derived from the wrong value. The
// compile was clean (rc=0, 0 diagnostics) and the miscompile only surfaced as a
// runtime trap. The evaluator was also not cycle-safe (`const X = X` hung,
// rc=124).
//
// FIX (Task 11J, Option B): a post-layout re-evaluation pass at the end of
// `phase_TypeResolution` (after `typeResolverResolve`, before
// `phase_FrontResolution`) re-walks every module enum with a fresh `auto_val`
// cascade through the ONE shared member walk, overwriting the stored member
// values in place. `evalConstI64Full` gained a depth cap (16) plus the integer
// binary/bitwise/shift/paren/char arms, `@intCast`/`@as`, and
// `@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf`/`@bitOffsetOf` (primitive/alias
// and named aggregates, complete post-layout). An explicit initializer that
// still cannot fold, a duplicate tag value, `~`, an enum-member reference, a
// function call, or a bool/float builtin is a clean ERR_3055 (never a silent
// auto-increment). The sema enum gate stays a fit-check only.
//
// This fixture guards EVERY member at runtime with `@enumToInt(E.X) != expected
// -> @panic(...)` — the silent-miscompile guard the compile-only classifier
// cannot see. The folded values are ALSO pinned by the emitted-C `#define`
// gate in the Task 11J report.
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   arith-ok
//   bits-ok
//   paren-ok
//   char-ok
//   builtin-ok
//   chain-ok
//   as-ok
//   mix-ok
//   offset-ok
//   done
const std = @import("std");

// Named aggregate for the post-layout `@sizeOf`/`@offsetOf` cases.
const S = struct { a: u32, b: u64 };

// Module-scope const chains built from arithmetic / builtins.
const NCHAIN = 2 + 2;
const NSIZE = @sizeOf(u32);

// arithmetic: + - * / %
const EArith = enum(u8) { A = 1 + 2, B = 10 - 3, C = 2 * 3, D = 8 / 2, E = 7 % 3 };
// bitwise / shift
const EBits = enum(u8) { A = 6 & 3, B = 6 | 3, C = 6 ^ 3, D = 1 << 4, E = 16 >> 2 };
// parentheses + auto-increment follower
const EParen = enum(u8) { A = (1 + 2), B };
// character literal + auto-increment follower
const EChar = enum(u8) { A = 'A', B };
// integer-valued builtins (primitive and named aggregate)
const EBuiltin = enum(u8) { A = @sizeOf(u32), B = @alignOf(u64), C = @bitSizeOf(u32), D = @intCast(u8, 3), E = @sizeOf(S) };
// module-const chains whose initializer is a binop / a builtin
const EChain = enum(u8) { A = NCHAIN, B = NSIZE + 2, C = NCHAIN + 1 };
// `@as`
const EAs = enum(u8) { A = @as(u8, 3), B };
// auto-increment cascade after an explicit override
const EMix = enum(u8) { A = 5, B, C = 10, D };
// aggregate field introspection (post-layout)
const EOffset = enum(u8) { A = @offsetOf(S, "b"), B = @bitOffsetOf(S, "b") };

pub fn main() void {
    if (@enumToInt(EArith.A) != 3) @panic("arith A");
    if (@enumToInt(EArith.B) != 7) @panic("arith B");
    if (@enumToInt(EArith.C) != 6) @panic("arith C");
    if (@enumToInt(EArith.D) != 4) @panic("arith D");
    if (@enumToInt(EArith.E) != 1) @panic("arith E");
    std.io.print("arith-ok\n");

    if (@enumToInt(EBits.A) != 2) @panic("bits A");
    if (@enumToInt(EBits.B) != 7) @panic("bits B");
    if (@enumToInt(EBits.C) != 5) @panic("bits C");
    if (@enumToInt(EBits.D) != 16) @panic("bits D");
    if (@enumToInt(EBits.E) != 4) @panic("bits E");
    std.io.print("bits-ok\n");

    if (@enumToInt(EParen.A) != 3) @panic("paren A");
    if (@enumToInt(EParen.B) != 4) @panic("paren B");
    std.io.print("paren-ok\n");

    if (@enumToInt(EChar.A) != 65) @panic("char A");
    if (@enumToInt(EChar.B) != 66) @panic("char B");
    std.io.print("char-ok\n");

    if (@enumToInt(EBuiltin.A) != 4) @panic("builtin A");
    if (@enumToInt(EBuiltin.B) != 8) @panic("builtin B");
    if (@enumToInt(EBuiltin.C) != 32) @panic("builtin C");
    if (@enumToInt(EBuiltin.D) != 3) @panic("builtin D");
    if (@enumToInt(EBuiltin.E) != 16) @panic("builtin E");
    std.io.print("builtin-ok\n");

    if (@enumToInt(EChain.A) != 4) @panic("chain A");
    if (@enumToInt(EChain.B) != 6) @panic("chain B");
    if (@enumToInt(EChain.C) != 5) @panic("chain C");
    std.io.print("chain-ok\n");

    if (@enumToInt(EAs.A) != 3) @panic("as A");
    if (@enumToInt(EAs.B) != 4) @panic("as B");
    std.io.print("as-ok\n");

    if (@enumToInt(EMix.A) != 5) @panic("mix A");
    if (@enumToInt(EMix.B) != 6) @panic("mix B");
    if (@enumToInt(EMix.C) != 10) @panic("mix C");
    if (@enumToInt(EMix.D) != 11) @panic("mix D");
    std.io.print("mix-ok\n");

    if (@enumToInt(EOffset.A) != 8) @panic("offset A");
    if (@enumToInt(EOffset.B) != 64) @panic("offset B");
    std.io.print("offset-ok\n");

    std.io.print("done\n");
}
