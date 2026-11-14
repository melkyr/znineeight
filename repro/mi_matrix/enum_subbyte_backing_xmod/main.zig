// enum_subbyte_backing_xmod — A2 regression: two sub-byte-backed enums coexist.
//
// DEFECT (seed v90): the enum branch of `populateTypePayload`
// (`sf/src/symbol_registrator.zig`) wrote the payload index onto
// `types_items[types_len-1]`, but resolving an arbitrary-width `enum(uN)`
// backing first appends the `arb_uint_type` (`sf/src/type_registry.zig`), so
// every arb-backed enum kept `payload_idx = 0`, aliased the first enum's
// member table, and `enumReevaluateAll` overwrote the earlier enum's members.
// The backing gate then raised a spurious `error[3000]` at `Small`:
//
//   const Small = enum(u3){A,B,C};
//   const Wide = enum(u5){X=0,Y=31};
//   // error[3000]: enum tag value does not fit the enum backing width; at Small
//
// FIX (A2-F): `populateTypePayload` takes the container `tid` and writes
// `payload_idx` on `types_items[tid]` in every branch.
//
// GREEN contract: dump rc 0 and stdout `enum subbyte backing ok` (RUNRC 0).
// Seed v90 is RED: dump rc 2, 0 `.c`, error[3000] at `Small`.
const std = @import("std");

const Small = enum(u3) { A, B, C };
const Wide = enum(u5) { X = 0, Y = 31 };

pub fn main() void {
    if (@intCast(u32, @enumToInt(Small.C)) == 2 and @intCast(u32, @enumToInt(Wide.Y)) == 31) {
        std.io.write("enum subbyte backing ok\n");
    } else {
        std.io.write("enum subbyte backing FAIL\n");
    }
}
