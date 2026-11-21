// d14_sync_tail_ok/sibling_void.zig — void synchronous tail call inside an
// async frame (same `copyTailCall` path, terminal void result).
//
// GREEN contract: stdout `12\n`, rc 0, under `-ffast` and `-fsafe`.
const std = @import("std");

fn syncTailVoid(c: *u32) void {
    c.* = c.* + 9;
}

fn asyncVoid(c: *u32) void {
    @asyncSuspend(null);
    return syncTailVoid(c);
}

const Args = struct { out: *u32, c: *u32 };

fn caller(out: *u32, c: *u32) void {
    asyncVoid(c);
    out.* = c.*;
}

const Ctx = struct { used: u32, capacity: u32, oom: u8 };

fn drive(out: *u32, c: *u32) void {
    var cbuf: [256]u8 = undefined;
    var fbuf: [256]u8 = undefined;
    var a = Args{ .out = out, .c = c };
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
    var c: u32 = 3;
    var out: u32 = 0;
    drive(&out, &c);
    std.io.printInt(@intCast(i32, out));
    std.io.writeByte('\n');
}
