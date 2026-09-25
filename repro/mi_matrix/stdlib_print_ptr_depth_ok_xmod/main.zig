// stdlib_print_ptr_depth_ok_xmod — Task 8 (z98-print-formatting Amendment 1,
// B2 + B3) positive runtime fixture: pointer/optional chains at the
// validator's accepted depth and a pointer name just inside the emitter's
// 512-byte name budget.
//
// B3 row (`s14`): struct field `p: *A14` where A14 is a 14-wrapper
// `?*?*?*?*?*?*?*i32` chain — the deepest accepted FIELD chain. Before the
// Task-8 fix `emitPointeeDep` truncated its typedef dependency walk at depth 8
// while the validator accepted 14, so emission was rc=0 and gcc failed with
// `unknown type name 'Opt_*'`; the walk now shares the single 16 cap and the
// wrapper typedefs are emitted before use. `s10` is the 10-wrapper control.
//
// B2 row (`ep`): `*E511` whose `error{...}` @typeName is EXACTLY 511 bytes
// (43 x 10-char + 2 x 15-char members: 6 + 460 + 45 + 1 = 511); with the
// trailing `@` that is exactly the 512-byte emitter name buffer, so both the
// validator byte mirror and the emitter accept it. The 512-byte name (one
// byte more) rejects `error[3063]` in `print_ptr_name_cap_reject_xmod`.
//
// Golden contract: rc 0, 3x byte-exact; the three value rows are
// byte-identical to the Zig-0.15.2 twin (std.debug.print; fixed addresses via
// `@ptrFromInt`/`@intToPtr` so ASLR cannot move the golden); Z98 appends its
// own `done` marker line.
const std = @import("std");

const A14 = ?*?*?*?*?*?*?*i32;
const S14 = struct { p: *A14, n: i32 };
const A10 = ?*?*?*?*?*i32;
const S10 = struct { p: *A10, n: i32 };

const E511 = error{
    E00aaaaaaa, E01aaaaaaa, E02aaaaaaa, E03aaaaaaa, E04aaaaaaa,
    E05aaaaaaa, E06aaaaaaa, E07aaaaaaa, E08aaaaaaa, E09aaaaaaa,
    E10aaaaaaa, E11aaaaaaa, E12aaaaaaa, E13aaaaaaa, E14aaaaaaa,
    E15aaaaaaa, E16aaaaaaa, E17aaaaaaa, E18aaaaaaa, E19aaaaaaa,
    E20aaaaaaa, E21aaaaaaa, E22aaaaaaa, E23aaaaaaa, E24aaaaaaa,
    E25aaaaaaa, E26aaaaaaa, E27aaaaaaa, E28aaaaaaa, E29aaaaaaa,
    E30aaaaaaa, E31aaaaaaa, E32aaaaaaa, E33aaaaaaa, E34aaaaaaa,
    E35aaaaaaa, E36aaaaaaa, E37aaaaaaa, E38aaaaaaa, E39aaaaaaa,
    E40aaaaaaa, E41aaaaaaa, E42aaaaaaa,
    F0aaaaaaaaaaaaa, F1aaaaaaaaaaaaa,
};

pub fn main() void {
    var s14 = S14{ .p = @intToPtr(*A14, 0x1400), .n = 14 };
    var s10 = S10{ .p = @intToPtr(*A10, 0x1000), .n = 10 };
    var ep: *E511 = @intToPtr(*E511, 0x520);
    std.io.print("s14={}\n", .{s14});
    std.io.print("s10={}\n", .{s10});
    std.io.print("ep={}\n", .{ep});
    std.io.print("done\n", .{});
}
