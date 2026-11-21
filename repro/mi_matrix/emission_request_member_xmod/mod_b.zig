const std = @import("std");
const mod_a = @import("mod_a.zig");
const CallInfo = mod_a.CallInfo;
const Emitter = mod_a.Emitter;

fn resolveTempName(emitter: *Emitter, t: u32) u32 {
    _ = emitter;
    return t;
}

pub fn emitInst(emitter: *Emitter, ret_temp: u32) u32 {
    var acc: u32 = 0;
    var p: u32 = 0;
    while (p < 3) : (p += 1) {
        var ci: usize = 0;
        while (ci < 2) : (ci += 1) {
            acc = acc + @intCast(u32, ci);
        }
    }
    var tci = mod_a.findTailCall(emitter, ret_temp);
    if (tci) |ci| {
        if (ci.is_self == 1 and ci.args_count == emitter.param_count) {
            acc = resolveTempName(emitter, ci.result);
            acc = acc + ci.callee + ci.module_id + ci.args_start + ci.return_type + ci.call_block_idx;
        }
    }
    return acc;
}
