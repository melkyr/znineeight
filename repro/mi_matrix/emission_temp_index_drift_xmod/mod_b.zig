const std = @import("std");
const mod_a = @import("mod_a.zig");
const Inst = mod_a.Inst;

pub const Emitter = struct {
    buf: [128]u8,
    pos: usize,
};

fn emitCase(emitter: *Emitter, c: mod_a.SwitchCase) void {
    var val_buf: [20]u8 = undefined;
    var val_len: usize = 3;
    var val_start = @intCast(usize, @intCast(u32, val_buf.len) - @intCast(u32, 1) - val_len);
    var val_end = @intCast(usize, @intCast(u32, val_buf.len) - @intCast(u32, 1));
    var i: usize = val_start;
    while (i < val_end) : (i += 1) {
        if (emitter.pos < 128) {
            emitter.buf[emitter.pos] = val_buf[i];
            emitter.pos += 1;
        }
    }
    var bb_buf: [10]u8 = undefined;
    var bb_len: usize = 2;
    var bb_start = @intCast(usize, @intCast(u32, bb_buf.len) - @intCast(u32, 1) - bb_len);
    var bb_end = @intCast(usize, @intCast(u32, bb_buf.len) - @intCast(u32, 1));
    var j: usize = bb_start;
    while (j < bb_end) : (j += 1) {
        if (emitter.pos < 128) {
            emitter.buf[emitter.pos] = bb_buf[j];
            emitter.pos += 1;
        }
    }
}

pub fn emitInst(emitter: *Emitter, inst: Inst, cases: []mod_a.SwitchCase) void {
    switch (inst) {
        .switch_br => |s| {
            var i: u32 = s.cases_start;
            var end = s.cases_start + s.cases_count;
            while (i < end) : (i += 1) {
                emitCase(emitter, cases[@intCast(usize, i)]);
            }
            var def_buf: [10]u8 = undefined;
            var def_len: usize = 2;
            var def_start = @intCast(usize, @intCast(u32, def_buf.len) - @intCast(u32, 1) - def_len);
            var def_end = @intCast(usize, @intCast(u32, def_buf.len) - @intCast(u32, 1));
            var k: usize = def_start;
            while (k < def_end) : (k += 1) {
                if (emitter.pos < 128) {
                    emitter.buf[emitter.pos] = def_buf[k];
                    emitter.pos += 1;
                }
            }
        },
        else => {},
    }
}
