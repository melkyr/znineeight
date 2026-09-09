// store_dedup_valueblock_xmod — EMISSION-CORE compaction RED fixture (Part 1: value-block /
// if-else-merge store shape).
//
// Bug: a named-local store whose value is the result of a value block (if/else merge into a
// shared local, reassigned from each arm) emits duplicate consecutive C stores: each plain
// arm store is 2x (`name = zT_N; name = zT_N;`) and the decl that hoists the merge target
// repeats its own 3x trio. Every later reader consumes the C variable, so all but one write
// per logical store is a pure dead store. This fixture pins the "proper emission" invariant:
// ONE C store per logical named-local store, including through value-block joins.
//
// GREEN (contract): deterministic stdout below (byte-exact, RUNRC=0). The computation is
// if/else arm arithmetic over locals only, so any correct compiler prints identical output.
// PROPER EMISSION (invariant this fixture guards): the emitted C of this program contains NO
// pair of consecutive identical `name = …;` lines — the duplicate named-local store must be
// collapsed at the lowering source.
const std = @import("std");

fn pick(v: i32, flag: i32) i32 {
    var acc: i32 = 0;
    if (flag > 0) {
        acc = v;
        acc = acc + 2;
    } else {
        acc = v * 3;
        acc = acc - 1;
    }
    return acc;
}

fn merge(v: i32, flag: i32) i32 {
    var acc: i32 = 0;
    if (flag == 0) {
        acc = v;
    } else if (flag == 1) {
        acc = v + 1;
    } else {
        acc = v + 2;
    }
    return acc;
}

pub fn main() void {
    std.io.printInt(pick(5, 1));
    std.io.writeByte('\n');
    std.io.printInt(pick(5, -1));
    std.io.writeByte('\n');
    std.io.printInt(merge(10, 0));
    std.io.writeByte('\n');
    std.io.printInt(merge(10, 1));
    std.io.writeByte('\n');
    std.io.printInt(merge(10, 9));
    std.io.writeByte('\n');
}
