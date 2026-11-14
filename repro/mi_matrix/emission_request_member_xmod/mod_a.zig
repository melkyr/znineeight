const std = @import("std");

pub const TypeId = u32;

pub const CallInfo = struct {
    is_self: u8,
    is_indirect: u8,
    is_extern: u8,
    callee: u32,
    module_id: u32,
    args_start: u32,
    args_count: u32,
    result: u32,
    return_type: u32,
    call_block_idx: u32,
    call_inst_idx: u32,
};

pub const Emitter = struct {
    x: u32,
    param_count: u32,
    return_type: u32,
};

pub fn findTailCall(emitter: *Emitter, ret_temp: u32) ?CallInfo {
    _ = emitter;
    if (ret_temp == 1) {
        return CallInfo{
            .is_self = 1,
            .is_indirect = 0,
            .is_extern = 0,
            .callee = 7,
            .module_id = 0,
            .args_start = 3,
            .args_count = 2,
            .result = 99,
            .return_type = 42,
            .call_block_idx = 5,
            .call_inst_idx = 8,
        };
    }
    return null;
}
