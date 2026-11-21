// D14 sibling probe: a suspending wrapper returning `E!void` (the form the
// http2 out-parameter workaround uses).
const std = @import("std");

const E = error{Boom};

fn wait(c: *u32) E!void {
    @asyncSuspend(null);
    if (c.* != 0) return E.Boom;
}

fn wrapperVoid(c: *u32) E!void {
    try wait(c);
}

const Args = struct { out: *u32, c: *u32, failed: *u32 };

fn caller(out: *u32, c: *u32, failed: *u32) void {
    wrapperVoid(c) catch {
        failed.* = 1;
        return;
    };
    out.* = 1;
}

const Ctx = struct { used: u32, capacity: u32, oom: u8 };

fn drive(out: *u32, c: *u32, failed: *u32) void {
    var cbuf: [256]u8 = undefined;
    var fbuf: [256]u8 = undefined;
    var a = Args{ .out = out, .c = c, .failed = failed };
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
    var c: u32 = 0;
    var out: u32 = 0;
    var failed: u32 = 0;

    drive(&out, &c, &failed);
    std.io.printInt(@intCast(i32, out));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, failed));
    std.io.writeByte('\n');

    c = 1;
    out = 0;
    failed = 0;
    drive(&out, &c, &failed);
    std.io.printInt(@intCast(i32, out));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, failed));
    std.io.writeByte('\n');
}
