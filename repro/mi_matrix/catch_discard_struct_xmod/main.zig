// catch_discard_struct_xmod — compiler-class pin: a discarded fallible
// STRUCT-returning call through `_ = expr catch |e| { ... }` must emit correct
// C89 and run.
//
// Defect (found while authoring std_map, Plan C Task 3): for
//   _ = f(...) catch |e| { ... };
// where `f` returns `!SomeStruct`, the emitted C stores an integer into the
// struct temporary (`zT_x = <int>;`), so gcc rejects it with
// `incompatible types when assigning to type '...' from type 'int'`. The
// non-discarded bound form (`var s = f(...) catch ...`) already emits correctly.
//
// This fixture exercises both the error path (f(0) -> OutOfMemory) and the
// success path (f(7)) of the discarded shape, plus the bound shape as a
// control. RED: dump rc=0 but gcc FAIL. GREEN: dump + gcc + run rc=0 with
// deterministic stdout `catch discard struct ok\n`.
const std = @import("std");

const Pair = struct { a: u32, b: u32 };

fn make(x: u32) !Pair {
    if (x == 0) return error.OutOfMemory;
    return Pair{ .a = x, .b = x + 1 };
}

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    // Discarded call whose error path is taken.
    var oom_seen = false;
    _ = make(0) catch |e| {
        if (e == error.OutOfMemory) oom_seen = true;
    };
    ck(oom_seen, "discarded error path");

    // Discarded call whose success path is taken.
    var success_seen = false;
    _ = make(7) catch {
        @panic("discarded success raised");
    };
    success_seen = true;
    ck(success_seen, "discarded success path");

    // Control: bound struct value still works.
    var p = make(3) catch {
        @panic("bound make failed");
    };
    ck(p.a == 3 and p.b == 4, "bound struct value");

    if (g_fail == 0) {
        std.io.write("catch discard struct ok\n");
    } else {
        std.io.write("catch discard struct FAIL\n");
    }
}
