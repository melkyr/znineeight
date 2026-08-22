const std = @import("std");
const mod_a = @import("mod_a.zig");
const Inst = mod_a.Inst;

fn resolveTempName(emitter: *Emitter, t: u32) u32 {
    _ = emitter;
    return t;
}

fn getTypeInfo(emitter: *Emitter, temp_id: u32, fb1: u32, fb2: u32, out_type: *u32, out_signed: *u8) void {
    _ = emitter;
    out_type.* = temp_id + fb1 + fb2;
    out_signed.* = 0;
}

pub const Emitter = struct {
    x: u32,
};

pub fn emitInst(emitter: *Emitter, inst: Inst) u32 {
    var acc: u32 = 0;
    switch (inst) {
        .jump => |t| {
            var wty: u32 = 0;
            var wsg: u8 = 0;
            getTypeInfo(emitter, t.result, t.target, 0, &wty, &wsg);
            acc = wty;
        },
        else => {},
    }
    return acc;
}
