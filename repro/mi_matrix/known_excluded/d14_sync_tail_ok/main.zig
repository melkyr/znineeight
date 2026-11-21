// d14_sync_tail_ok — Phase 3.5 Task 7 `copyTailCall` name-id probe.
//
// A suspending wrapper (`asyncWrapper`) tail-returns a *synchronous* callee
// (`syncTail`) of the same error-union type. TCO suppression only applies to
// suspending callees, so this genuine tail call reaches the async transform and
// exercises `copyTailCall`. Pre-fix that function added the temp base to the
// callee's interned name id, so the emitted step called an unrelated symbol.
//
// GREEN contract: stdout `42 0\n0 1\n`, rc 0, under `-ffast` and `-fsafe`.
const std = @import("std");

const E = error{Boom};

fn syncTail(c: *u32, id: u32) E!u32 {
    if (c.* != 0) return E.Boom;
    return id + 1;
}

fn asyncWrapper(c: *u32, id: u32) E!u32 {
    @asyncSuspend(null);
    return syncTail(c, id);
}

const Args = struct { out: *u32, c: *u32, failed: *u32, id: u32 };

fn caller(out: *u32, c: *u32, failed: *u32, id: u32) void {
    var r: u32 = asyncWrapper(c, id) catch {
        failed.* = 1;
        return;
    };
    out.* = r;
}

const Ctx = struct { used: u32, capacity: u32, oom: u8 };

fn drive(out: *u32, c: *u32, failed: *u32, id: u32) void {
    var cbuf: [256]u8 = undefined;
    var fbuf: [256]u8 = undefined;
    var a = Args{ .out = out, .c = c, .failed = failed, .id = id };
    var ctxp: *void = @ptrCast(*void, &cbuf);
    var ctxv: *Ctx = @ptrCast(*Ctx, &cbuf);
    ctxv.capacity = 256;
    var args: *const void = @ptrCast(*const void, &a);
    var frame: *void = @asyncInit(ctxp, &fbuf, caller, args);
    var more: ?*void = @asyncResume(frame, null);
    while (more != null) {
        more = @asyncResume(frame, null);
    }
}

pub fn main() void {
    var id: u32 = 41;
    var c: u32 = 0;
    var out: u32 = 0;
    var failed: u32 = 0;

    drive(&out, &c, &failed, id);
    std.io.printInt(@intCast(i32, out));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, failed));
    std.io.writeByte('\n');

    c = 1;
    out = 0;
    failed = 0;
    drive(&out, &c, &failed, id);
    std.io.printInt(@intCast(i32, out));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, failed));
    std.io.writeByte('\n');
}
