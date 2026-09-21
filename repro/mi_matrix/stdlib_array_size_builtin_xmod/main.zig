// stdlib_array_size_builtin_xmod — Task 11F regression: integer-valued builtins
// fold in array-size positions.
//
// DEFECT (before the fix): `type_resolver.zig`'s array-size evaluator
// `evalConstU32Full` had NO `builtin_call` arm, so EVERY builtin in a size
// position returned the `0xFFFFFFFF` unfoldable sentinel and the `array_type`
// arm emitted `error[3050]: array size is not a constant expression`. The
// general fold evaluator (`comptime_eval.zig`) is a SEPARATE evaluator that
// runs in a later pipeline phase and was never consulted by type resolution.
//
// FIX (Task 11F): `evalConstU32Full` now folds the clear integer-valued
// builtins using the caller's `TypeResolveEnv`:
//   - `@intCast(T, e)` by recursing into the operand (local consts, const
//     chains, and arithmetic operands fold through the existing arms);
//   - `@sizeOf(T)` / `@alignOf(T)` / `@bitSizeOf(T)` for COMPLETE (`state == 2`)
//     primitive/alias types, via `resolveTypeExprFull` + the type registry.
// Non-integer builtins (`@isWindows`, `@intToFloat`, `@floatCast`) and
// aggregate introspection (`@offsetOf`/`@bitOffsetOf`, struct `@sizeOf`) stay
// rejected (ERR_3050) — consistent with `[true]`/`[4.0]`, and struct/aggregate
// introspection in array sizes is deferred to Task 11G/11H.
//
// Fold visibility: this fixture's stdout proves RUNTIME correctness (the folded
// dimensions are the values real Zig folds to). The fold itself is ALSO pinned
// by the emitted-C dimension gate (every `Arr_unsigned_char_N` typedef carries
// the folded `N`; `@bitSizeOf(u32)` = 32 is the truncated-name quirk case).
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   sizeof-prim-ok
//   intcast-prim-ok
//   intcast-arith-ok
//   alignof-prim-ok
//   bitsizeof-prim-ok
//   const-chain-ok
//   alignof-u64-ok
//   bitsizeof-u16-ok
//   field-position-ok
//   field-size-ok
//   local-position-ok
//   local-const-operand-ok
//   done
const std = @import("std");

// Module-scope const chains built from integer-valued builtins.
const CHAIN: usize = @sizeOf(u32);
const ALIGNED: usize = @alignOf(u64);
const BITS: usize = @bitSizeOf(u16);

// Field position: the struct field's array length is a builtin call, resolved
// by `resolveAggregateFieldTypesAll` BEFORE aggregate layout. The `state == 2`
// gate is what makes this safe (a gate-less read gave a silently wrong [1]).
const Field = struct { data: [@sizeOf(u32)]u8 };
const FIELD_SIZE: usize = @sizeOf(Field);

// Module-scope positions.
var g_size: [@sizeOf(u32)]u8 = undefined;
var g_cast: [@intCast(u32, 4)]u8 = undefined;
var g_arith: [@intCast(u32, 2 + 2)]u8 = undefined;
var g_align: [@alignOf(u32)]u8 = undefined;
var g_bits: [@bitSizeOf(u32)]u8 = undefined;
var g_chain: [CHAIN]u8 = undefined;
var g_aligned: [ALIGNED]u8 = undefined;
var g_bits2: [BITS]u8 = undefined;
var g_field: Field = undefined;

pub fn main() void {
    if (g_size.len == 4) { std.io.print("sizeof-prim-ok\n"); } else { std.io.print("sizeof-prim-bad\n"); }
    if (g_cast.len == 4) { std.io.print("intcast-prim-ok\n"); } else { std.io.print("intcast-prim-bad\n"); }
    if (g_arith.len == 4) { std.io.print("intcast-arith-ok\n"); } else { std.io.print("intcast-arith-bad\n"); }
    if (g_align.len == 4) { std.io.print("alignof-prim-ok\n"); } else { std.io.print("alignof-prim-bad\n"); }
    if (g_bits.len == 32) { std.io.print("bitsizeof-prim-ok\n"); } else { std.io.print("bitsizeof-prim-bad\n"); }
    if (g_chain.len == 4) { std.io.print("const-chain-ok\n"); } else { std.io.print("const-chain-bad\n"); }
    if (g_aligned.len == 8) { std.io.print("alignof-u64-ok\n"); } else { std.io.print("alignof-u64-bad\n"); }
    if (g_bits2.len == 16) { std.io.print("bitsizeof-u16-ok\n"); } else { std.io.print("bitsizeof-u16-bad\n"); }

    // Field position: the struct's `data` field must have folded to [4]. Writing
    // index 3 is valid only then; `FIELD_SIZE` is the general-fold cross-check.
    g_field.data[3] = 9;
    if (g_field.data[3] == 9) { std.io.print("field-position-ok\n"); } else { std.io.print("field-position-bad\n"); }
    if (FIELD_SIZE == 4) { std.io.print("field-size-ok\n"); } else { std.io.print("field-size-bad\n"); }

    // Function-local positions, including a function-local const operand.
    var local: [@sizeOf(u32)]u8 = undefined;
    const N = 7;
    var localc: [@intCast(u32, N)]u8 = undefined;
    if (local.len == 4) { std.io.print("local-position-ok\n"); } else { std.io.print("local-position-bad\n"); }
    if (localc.len == 7) { std.io.print("local-const-operand-ok\n"); } else { std.io.print("local-const-operand-bad\n"); }

    std.io.print("done\n");
}
