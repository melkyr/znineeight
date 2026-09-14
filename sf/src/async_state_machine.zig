// async_state_machine.zig — Stage 3 LIR-to-LIR async state-machine transform
// (Track 2, Task 6; Amendment 7).
//
// For every suspending function this pass emits a synthesized step function
// `__Z98Step_<f>` alongside the original (unchanged) synchronous function. The
// original function stays the synchronous entry (so the C `int main` wrapper and
// all direct calls keep working); the step is the ruled heterogeneous
// self-dispatch target reached from `@asyncInit`/`@asyncResume`.
//
//   ?*void __Z98Step_<f>(void *frame, ?*void arg)
//
// The step reads its `state` field (offset from the Stage-2 layout), switches on
// it, and runs the body from the numbered suspension point. An explicit
// `@asyncSuspend` placeholder (`int_const 0` producing a `*void`) becomes:
// store every frame field, store state = N, return a non-null pointer. The
// matching resume segment reloads every frame field and continues.
//
// Backend-agnostic: no `c89_*` / emitter call. The frame is addressed as raw
// bytes (Amendment 7 fallback) through `ptr_to_int`/`binary`/`int_to_ptr`/
// `load`/`store`, so 0 new `LirInst` variants and no synthetic struct type.
//
// Deviations recorded for Task 6 (see report):
//   * The synchronous original body is retained (O4 "dual-emit" style) because
//     the emitter's `int main` wrapper calls the original `main` symbol with its
//     original signature and because the direct-call frame regression fixtures
//     call suspending functions synchronously.
//   * An implicit await (a direct call to a suspending callee) is realized by
//     calling the callee's synchronous entry; child-frame pool accounting is
//     Task 7.

const alloc_mod = @import("allocator.zig");
const async_analysis = @import("async_analysis.zig");
const async_frame_layout = @import("async_frame_layout.zig");
const hash_mod = @import("util/hash.zig");
const lir_mod = @import("lir.zig");
const lir_stream = @import("lir_stream.zig");
const si_mod = @import("string_interner.zig");
const type_mod = @import("type_registry.zig");

const Sand = alloc_mod.Sand;
const LirFunction = lir_mod.LirFunction;
const LirInst = lir_mod.LirInst;
const TypeRegistry = type_mod.TypeRegistry;
const StringInterner = si_mod.StringInterner;
const AsyncFrameLayout = async_frame_layout.AsyncFrameLayout;

const BIN_ADD: u8 = @intCast(u8, 0);
const BIN_LE: u8 = @intCast(u8, 13);

pub const AsyncTransformCtx = struct {
    alloc: *Sand,
    registry: *TypeRegistry,
    interner: *StringInterner,
    lir_stream: *lir_stream.LirStream,
    lir_slots: *lir_mod.LirSlotArrayList,
    suspending_fns: *hash_mod.U64ToU32Map,
    layout: *const AsyncFrameLayout,
    safe_checks: bool,
};

fn bumpAlloc(alloc: *Sand, size: usize, align: usize) [*]u8 {
    return @ptrCast([*]u8, alloc_mod.sandAlloc(alloc, size, align) catch unreachable);
}

pub fn asyncStepNameId(interner: *StringInterner, fn_name_id: u32) u32 {
    var name = si_mod.stringInternerGet(interner, fn_name_id);
    var buf: [256]u8 = undefined;
    var prefix: []const u8 = "__Z98Step_";
    var n: usize = @intCast(usize, 0);
    while (n < prefix.len and n < @intCast(usize, 200)) : (n += @intCast(usize, 1)) {
        buf[n] = prefix[n];
    }
    var k: usize = @intCast(usize, 0);
    while (k < name.len and n < @intCast(usize, 250)) : (k += @intCast(usize, 1)) {
        buf[n] = name[k];
        n += @intCast(usize, 1);
    }
    return si_mod.stringInternerIntern(interner, buf[0..n]);
}

pub fn asyncStepFnType(reg: *TypeRegistry, interner: *StringInterner, step_name_id: u32, module_id: u32) u32 {
    var ptr_void = type_mod.typeRegistryGetOrCreatePtr(reg, type_mod.TYPE_VOID, false);
    var opt = type_mod.typeRegistryGetOrCreateOptional(reg, ptr_void);
    var i: usize = @intCast(usize, 0);
    while (i < reg.types_len) : (i += @intCast(usize, 1)) {
        var it = reg.types_items[i];
        if (it.kind == type_mod.TypeKind.fn_type and it.name_id == step_name_id) {
            var fp = reg.fn_items[@intCast(usize, it.payload_idx)];
            if (fp.module_id == module_id) {
                type_mod.typeRegistryMarkFnPtrUsed(reg, @intCast(u32, i));
                return @intCast(u32, i);
            }
        }
    }
    var pstart: u32 = @intCast(u32, reg.xt_len);
    type_mod.xtAppend(reg, ptr_void);
    type_mod.xtAppend(reg, opt);
    var tid = type_mod.typeRegistryGetOrCreateFn(reg, step_name_id, module_id, @intCast(u8, 0), @intCast(u8, 0), pstart, @intCast(u16, 2), opt, @intCast(u8, 0));
    type_mod.typeRegistryMarkFnPtrUsed(reg, tid);
    return tid;
}

pub fn asyncGenericStepFnType(reg: *TypeRegistry, interner: *StringInterner) u32 {
    var gname: []const u8 = "__Z98StepFn";
    var gid = si_mod.stringInternerIntern(interner, gname);
    return asyncStepFnType(reg, interner, gid, @intCast(u32, 0));
}

fn ptrVoid(reg: *TypeRegistry) u32 {
    return type_mod.typeRegistryGetOrCreatePtr(reg, type_mod.TYPE_VOID, false);
}

fn optPtrVoid(reg: *TypeRegistry) u32 {
    return type_mod.typeRegistryGetOrCreateOptional(reg, ptrVoid(reg));
}

fn typeIsPtrVoid(reg: *TypeRegistry, tid: u32) bool {
    if (@intCast(usize, tid) >= reg.types_len) return false;
    var t = reg.types_items[@intCast(usize, tid)];
    if (t.kind != type_mod.TypeKind.ptr_type) return false;
    var base = reg.ptr_items[@intCast(usize, t.payload_idx)].base;
    return base == type_mod.TYPE_VOID;
}

fn tempType(lf: *LirFunction, tid: u32) u32 {
    var i: usize = @intCast(usize, 0);
    while (i < lf.hoisted_temps.len) : (i += @intCast(usize, 1)) {
        var td = lf.hoisted_temps.items[i];
        if (td.temp_id == tid) return td.type_id;
    }
    return type_mod.TYPE_UNDEFINED;
}

fn isExplicitSuspend(reg: *TypeRegistry, lf: *LirFunction, inst: LirInst) bool {
    switch (inst) {
        .int_const => |ic| {
            if (ic.value != @intCast(u64, 0)) return false;
            return typeIsPtrVoid(reg, tempType(lf, ic.result));
        },
        else => return false,
    }
}

const Build = struct {
    step: *LirFunction,
    orig: *LirFunction,
    reg: *TypeRegistry,
    base: u32,
    frame_temp: u32,
    opt: u32,
    seg_base: [*]u32,
    resume_target: [*]u32,
    block_map: [*]u32,
    nblocks: u32,
};

fn newTemp(b: *Build, type_id: u32) u32 {
    var tid: u32 = @intCast(u32, b.step.hoisted_temps.len);
    lir_mod.tempDeclArrayListAppend(&b.step.hoisted_temps, lir_mod.TempDecl{ .temp_id = tid, .type_id = type_id });
    return tid;
}

fn emit(b: *Build, blk: u32, inst: LirInst) void {
    lir_mod.lirInstArrayListAppend(&b.step.blocks.items[@intCast(usize, blk)].insts, inst);
}

fn fieldPtr(b: *Build, blk: u32, offset: u32, field_type: u32) u32 {
    var pi = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, blk, LirInst{ .ptr_to_int = .{ .value = b.frame_temp, .result = pi } });
    var off = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, blk, LirInst{ .int_const = .{ .value = @intCast(u64, offset), .result = off } });
    var addr = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, blk, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = pi, .rhs = off, .result = addr } });
    var pt_type = type_mod.typeRegistryGetOrCreatePtr(b.reg, field_type, false);
    var pt = newTemp(b, pt_type);
    emit(b, blk, LirInst{ .int_to_ptr = .{ .value = addr, .target = pt_type, .result = pt } });
    return pt;
}

fn loadField(b: *Build, blk: u32, offset: u32, field_type: u32) u32 {
    var pt = fieldPtr(b, blk, offset, field_type);
    var v = newTemp(b, field_type);
    emit(b, blk, LirInst{ .load = .{ .ptr = pt, .result = v } });
    return v;
}

fn storeField(b: *Build, blk: u32, offset: u32, field_type: u32, value: u32) void {
    var pt = fieldPtr(b, blk, offset, field_type);
    emit(b, blk, LirInst{ .store = .{ .ptr = pt, .value = value } });
}

fn saveAllFields(b: *Build, blk: u32, lay: *const AsyncFrameLayout) void {
    var f: usize = @intCast(usize, 0);
    while (f < lay.fields.len) : (f += @intCast(usize, 1)) {
        var fld = lay.fields.items[f];
        if (fld.kind == async_frame_layout.ASYNC_FIELD_PARAM or fld.kind == async_frame_layout.ASYNC_FIELD_LIVE) {
            storeField(b, blk, fld.offset, fld.type_id, fld.temp_id + b.base);
        }
    }
}

fn reloadAllFields(b: *Build, blk: u32, lay: *const AsyncFrameLayout) void {
    var f: usize = @intCast(usize, 0);
    while (f < lay.fields.len) : (f += @intCast(usize, 1)) {
        var fld = lay.fields.items[f];
        if (fld.kind == async_frame_layout.ASYNC_FIELD_PARAM or fld.kind == async_frame_layout.ASYNC_FIELD_LIVE) {
            var v = loadField(b, blk, fld.offset, fld.type_id);
            emit(b, blk, LirInst{ .assign = .{ .dst = fld.temp_id + b.base, .src = v, .name_id = @intCast(u32, 0) } });
        }
    }
}

fn remapBb(b: *Build, orig: u32) u32 {
    if (orig < b.nblocks) return b.block_map[@intCast(usize, orig)];
    return orig;
}

fn copyCallDirect(b: *Build, slot: u32) u32 {
    var cd = b.orig.side_table.items[@intCast(usize, slot)].call_direct;
    cd.args_start = cd.args_start + b.base;
    cd.result = cd.result + b.base;
    var ns: u32 = @intCast(u32, b.step.side_table.len);
    lir_mod.lirSideEntryArrayListAppend(&b.step.side_table, lir_mod.LirSideEntry{ .call_direct = cd });
    return ns;
}

fn copyTailCall(b: *Build, slot: u32) u32 {
    var tc = b.orig.side_table.items[@intCast(usize, slot)].tail_call;
    tc.callee = tc.callee + b.base;
    tc.args_start = tc.args_start + b.base;
    tc.result = tc.result + b.base;
    var ns: u32 = @intCast(u32, b.step.side_table.len);
    lir_mod.lirSideEntryArrayListAppend(&b.step.side_table, lir_mod.LirSideEntry{ .tail_call = tc });
    return ns;
}

fn remapInst(b: *Build, inst: LirInst, sw_off: u32) LirInst {
    switch (inst) {
        .decl_temp => |x| return LirInst{ .decl_temp = .{ .temp = x.temp + b.base, .type_id = x.type_id } },
        .decl_local => |x| return LirInst{ .decl_local = .{ .name_id = x.name_id, .type_id = x.type_id, .temp = x.temp + b.base } },
        .assign => |x| return LirInst{ .assign = .{ .dst = x.dst + b.base, .src = x.src + b.base, .name_id = x.name_id } },
        .assign_field => |x| return LirInst{ .assign_field = .{ .base = x.base + b.base, .field_id = x.field_id, .src = x.src + b.base, .name_id = x.name_id } },
        .assign_index => |x| return LirInst{ .assign_index = .{ .base = x.base + b.base, .index = x.index + b.base, .src = x.src + b.base, .name_id = x.name_id } },
        .jump => |x| return LirInst{ .jump = remapBb(b, x) },
        .branch => |x| return LirInst{ .branch = .{ .cond = x.cond + b.base, .then_bb = remapBb(b, x.then_bb), .else_bb = remapBb(b, x.else_bb) } },
        .switch_br => |x| return LirInst{ .switch_br = .{ .cond = x.cond + b.base, .cases_start = x.cases_start + sw_off, .cases_count = x.cases_count, .else_bb = remapBb(b, x.else_bb) } },
        .loop_header => |x| return LirInst{ .loop_header = remapBb(b, x) },
        .ret => return LirInst{ .ret_void = {} },
        .ret_void => return inst,
        .label => return inst,
        .binary => |x| return LirInst{ .binary = .{ .op = x.op, .lhs = x.lhs + b.base, .rhs = x.rhs + b.base, .result = x.result + b.base } },
        .unary => |x| return LirInst{ .unary = .{ .op = x.op, .operand = x.operand + b.base, .result = x.result + b.base } },
        .call => |x| return LirInst{ .call = .{ .callee = x.callee + b.base, .args_start = x.args_start + b.base, .args_count = x.args_count, .result = x.result + b.base } },
        .load_field => |x| return LirInst{ .load_field = .{ .base = x.base + b.base, .field_id = x.field_id, .result = x.result + b.base, .name_id = x.name_id } },
        .store_field => |x| return LirInst{ .store_field = .{ .base = x.base + b.base, .field_id = x.field_id, .value = x.value + b.base, .name_id = x.name_id } },
        .load_index => |x| return LirInst{ .load_index = .{ .base = x.base + b.base, .index = x.index + b.base, .result = x.result + b.base, .name_id = x.name_id } },
        .load => |x| return LirInst{ .load = .{ .ptr = x.ptr + b.base, .result = x.result + b.base } },
        .store => |x| return LirInst{ .store = .{ .ptr = x.ptr + b.base, .value = x.value + b.base } },
        .addr_of => |x| return LirInst{ .addr_of = .{ .operand = x.operand + b.base, .result = x.result + b.base } },
        .addr_of_field => |x| return LirInst{ .addr_of_field = .{ .base = x.base + b.base, .field_id = x.field_id, .result = x.result + b.base } },
        .wrap_optional => |x| return LirInst{ .wrap_optional = .{ .value = x.value + b.base, .result = x.result + b.base, .type_id = x.type_id } },
        .call_direct => |slot| return LirInst{ .call_direct = copyCallDirect(b, slot) },
        .va_start => |x| return LirInst{ .va_start = .{ .va_list_temp = x.va_list_temp + b.base, .last_param_temp = x.last_param_temp + b.base } },
        .va_arg => |x| return LirInst{ .va_arg = .{ .va_list_temp = x.va_list_temp + b.base, .type_id = x.type_id, .result = x.result + b.base } },
        .va_end => |x| return LirInst{ .va_end = .{ .va_list_temp = x.va_list_temp + b.base } },
        .tail_call => |slot| return LirInst{ .tail_call = copyTailCall(b, slot) },
        .func_ref => |x| return LirInst{ .func_ref = .{ .name_id = x.name_id, .module_id = x.module_id, .result = x.result + b.base } },
        .unwrap_optional => |x| return LirInst{ .unwrap_optional = .{ .value = x.value + b.base, .result = x.result + b.base } },
        .unwrap_optional_abi => |x| return LirInst{ .unwrap_optional_abi = .{ .value = x.value + b.base, .result = x.result + b.base } },
        .check_optional => |x| return LirInst{ .check_optional = .{ .value = x.value + b.base, .result = x.result + b.base } },
        .wrap_error_ok => |x| return LirInst{ .wrap_error_ok = .{ .value = x.value + b.base, .result = x.result + b.base, .type_id = x.type_id } },
        .wrap_error_err => |x| return LirInst{ .wrap_error_err = .{ .value = x.value + b.base, .result = x.result + b.base, .type_id = x.type_id } },
        .unwrap_error_payload => |x| return LirInst{ .unwrap_error_payload = .{ .value = x.value + b.base, .result = x.result + b.base } },
        .unwrap_error_code => |x| return LirInst{ .unwrap_error_code = .{ .value = x.value + b.base, .result = x.result + b.base } },
        .check_error => |x| return LirInst{ .check_error = .{ .value = x.value + b.base, .result = x.result + b.base } },
        .make_slice => |x| return LirInst{ .make_slice = .{ .ptr = x.ptr + b.base, .len = x.len + b.base, .result = x.result + b.base, .type_id = x.type_id } },
        .int_cast => |x| return LirInst{ .int_cast = .{ .value = x.value + b.base, .target = x.target, .result = x.result + b.base } },
        .float_cast => |x| return LirInst{ .float_cast = .{ .value = x.value + b.base, .target = x.target, .result = x.result + b.base } },
        .ptr_cast => |x| return LirInst{ .ptr_cast = .{ .value = x.value + b.base, .target = x.target, .result = x.result + b.base } },
        .int_to_float => |x| return LirInst{ .int_to_float = .{ .value = x.value + b.base, .target = x.target, .result = x.result + b.base } },
        .ptr_to_int => |x| return LirInst{ .ptr_to_int = .{ .value = x.value + b.base, .result = x.result + b.base } },
        .int_to_ptr => |x| return LirInst{ .int_to_ptr = .{ .value = x.value + b.base, .target = x.target, .result = x.result + b.base } },
        .int_const => |x| return LirInst{ .int_const = .{ .value = x.value, .result = x.result + b.base } },
        .float_const => |x| return LirInst{ .float_const = .{ .value = x.value, .result = x.result + b.base } },
        .string_const => |x| return LirInst{ .string_const = .{ .string_id = x.string_id, .result = x.result + b.base } },
        .null_const => |x| return LirInst{ .null_const = .{ .result = x.result + b.base } },
        .set_optional_null => |x| return LirInst{ .set_optional_null = .{ .result = x.result + b.base, .type_id = x.type_id } },
        .bool_const => |x| return LirInst{ .bool_const = .{ .value = x.value, .result = x.result + b.base } },
        .undefined_const => |x| return LirInst{ .undefined_const = .{ .result = x.result + b.base, .type_id = x.type_id } },
        .enum_const => |x| return LirInst{ .enum_const = .{ .value = x.value, .result = x.result + b.base, .type_id = x.type_id, .member_name_id = x.member_name_id } },
        .load_local => |x| return LirInst{ .load_local = .{ .name_id = x.name_id, .result = x.result + b.base } },
        .store_local => |x| return LirInst{ .store_local = .{ .name_id = x.name_id, .value = x.value + b.base } },
        .load_global => |x| return LirInst{ .load_global = .{ .name_id = x.name_id, .module_id = x.module_id, .result = x.result + b.base } },
        .store_global => |x| return LirInst{ .store_global = .{ .name_id = x.name_id, .module_id = x.module_id, .value = x.value + b.base } },
        .print_str => return inst,
        .print_val => |x| return LirInst{ .print_val = .{ .value = x.value + b.base, .type_id = x.type_id, .fmt = x.fmt } },
        .builtin_put_char => |x| return LirInst{ .builtin_put_char = .{ .value = x.value + b.base } },
        .builtin_stdout_write => |x| return LirInst{ .builtin_stdout_write = .{ .ptr = x.ptr + b.base, .len = x.len + b.base } },
        .builtin_stderr_write => |x| return LirInst{ .builtin_stderr_write = .{ .ptr = x.ptr + b.base, .len = x.len + b.base } },
        .builtin_get_char => |x| return LirInst{ .builtin_get_char = .{ .result = x.result + b.base } },
        .builtin_exit => |x| return LirInst{ .builtin_exit = .{ .value = x.value + b.base } },
        .builtin_sleep_ms => |x| return LirInst{ .builtin_sleep_ms = .{ .value = x.value + b.base } },
        .builtin_console_clear => return inst,
        .builtin_console_gotoxy => |x| return LirInst{ .builtin_console_gotoxy = .{ .x = x.x + b.base, .y = x.y + b.base } },
        .builtin_console_set_color => |x| return LirInst{ .builtin_console_set_color = .{ .fg = x.fg + b.base, .bg = x.bg + b.base } },
        .nop => return inst,
        .load_bitfield => |x| return LirInst{ .load_bitfield = .{ .base = x.base + b.base, .result = x.result + b.base, .name_id = x.name_id, .bit_offset = x.bit_offset, .bit_width = x.bit_width } },
        .store_bitfield => |x| return LirInst{ .store_bitfield = .{ .base = x.base + b.base, .value = x.value + b.base, .bit_offset = x.bit_offset, .bit_width = x.bit_width } },
        .trap => return inst,
        .check_trap => |x| return LirInst{ .check_trap = .{ .cond = x.cond + b.base, .kind = x.kind } },
        .add_with_overflow => |x| return LirInst{ .add_with_overflow = .{ .lhs = x.lhs + b.base, .rhs = x.rhs + b.base, .result = x.result + b.base, .result_type = x.result_type, .width = x.width, .is_signed = x.is_signed } },
        .sub_with_overflow => |x| return LirInst{ .sub_with_overflow = .{ .lhs = x.lhs + b.base, .rhs = x.rhs + b.base, .result = x.result + b.base, .result_type = x.result_type, .width = x.width, .is_signed = x.is_signed } },
        .mul_with_overflow => |x| return LirInst{ .mul_with_overflow = .{ .lhs = x.lhs + b.base, .rhs = x.rhs + b.base, .result = x.result + b.base, .result_type = x.result_type, .width = x.width, .is_signed = x.is_signed } },
        .shl_with_overflow => |x| return LirInst{ .shl_with_overflow = .{ .lhs = x.lhs + b.base, .rhs = x.rhs + b.base, .result = x.result + b.base, .result_type = x.result_type, .width = x.width, .is_signed = x.is_signed } },
        .neg_with_overflow => |x| return LirInst{ .neg_with_overflow = .{ .value = x.value + b.base, .result = x.result + b.base, .result_type = x.result_type, .width = x.width, .is_signed = x.is_signed } },
        .overflow_flag => |x| return LirInst{ .overflow_flag = .{ .lhs = x.lhs + b.base, .rhs = x.rhs + b.base, .result = x.result + b.base, .result_type = x.result_type, .op = x.op, .width = x.width, .is_signed = x.is_signed } },
        .unwrap_optional_checked => |x| return LirInst{ .unwrap_optional_checked = .{ .value = x.value + b.base, .result = x.result + b.base } },
        .poison_init => |x| return LirInst{ .poison_init = .{ .result = x.result + b.base } },
        .int_cast_checked => |x| return LirInst{ .int_cast_checked = .{ .value = x.value + b.base, .target = x.target, .result = x.result + b.base, .src_signed = x.src_signed, .src_width = x.src_width, .dst_signed = x.dst_signed, .dst_width = x.dst_width } },
        .width_wrap => |x| return LirInst{ .width_wrap = .{ .value = x.value + b.base, .result = x.result + b.base, .result_type = x.result_type, .width = x.width, .is_signed = x.is_signed } },
    }
}


pub fn asyncTransform(lf: *LirFunction, actx: *AsyncTransformCtx) void {
    if (!async_analysis.asyncIsSuspending(actx.suspending_fns, lf.module_id, lf.name_id)) return;

    var reg = actx.registry;
    var base: u32 = @intCast(u32, 2);

    var step = LirFunction{
        .name_id = asyncStepNameId(actx.interner, lf.name_id),
        .module_id = lf.module_id,
        .return_type = optPtrVoid(reg),
        .params = lir_mod.lirParamArrayListInit(actx.alloc),
        .blocks = lir_mod.basicBlockArrayListInit(actx.alloc),
        .hoisted_temps = lir_mod.tempDeclArrayListInit(actx.alloc),
        .switch_cases = lir_mod.switchCaseArrayListInit(actx.alloc),
        .side_table = lir_mod.lirSideEntryArrayListInit(actx.alloc),
        .temp_variant_sub_field = hash_mod.u32ToU32MapInit(actx.alloc),
        .is_extern = @intCast(u8, 0),
        .is_pub = @intCast(u8, 0),
        .is_variadic = @intCast(u8, 0),
        .call_conv = @intCast(u8, 0),
        .poison_uninit = lf.poison_uninit,
    };

    var ptr_void = ptrVoid(reg);
    var opt = step.return_type;

    lir_mod.tempDeclArrayListAppend(&step.hoisted_temps, lir_mod.TempDecl{ .temp_id = @intCast(u32, 0), .type_id = ptr_void });
    lir_mod.tempDeclArrayListAppend(&step.hoisted_temps, lir_mod.TempDecl{ .temp_id = @intCast(u32, 1), .type_id = opt });
    var ti: usize = @intCast(usize, 0);
    while (ti < lf.hoisted_temps.len) : (ti += @intCast(usize, 1)) {
        var td = lf.hoisted_temps.items[ti];
        lir_mod.tempDeclArrayListAppend(&step.hoisted_temps, lir_mod.TempDecl{ .temp_id = td.temp_id + base, .type_id = td.type_id });
    }

    var frame_nm: []const u8 = "__az_frame";
    var arg_nm: []const u8 = "__az_arg";
    var frame_name = si_mod.stringInternerIntern(actx.interner, frame_nm);
    var arg_name = si_mod.stringInternerIntern(actx.interner, arg_nm);
    lir_mod.lirParamArrayListAppend(&step.params, lir_mod.LirParam{ .name_id = frame_name, .type_id = ptr_void, .temp_id = @intCast(u32, 0) });
    lir_mod.lirParamArrayListAppend(&step.params, lir_mod.LirParam{ .name_id = arg_name, .type_id = opt, .temp_id = @intCast(u32, 1) });

    var m: u32 = @intCast(u32, lf.blocks.len);
    var count_per_block: [*]u32 = @ptrCast([*]u32, bumpAlloc(actx.alloc, @intCast(usize, m + @intCast(u32, 1)) * @intCast(usize, 4), @intCast(usize, 4)));
    var bi: u32 = @intCast(u32, 0);
    while (bi < m) : (bi += @intCast(u32, 1)) {
        count_per_block[@intCast(usize, bi)] = @intCast(u32, 0);
        var bb = &lf.blocks.items[@intCast(usize, bi)];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            if (isExplicitSuspend(reg, lf, bb.insts.items[ii])) {
                count_per_block[@intCast(usize, bi)] += @intCast(u32, 1);
            }
        }
    }

    var total_states: u32 = @intCast(u32, 0);
    bi = @intCast(u32, 0);
    while (bi < m) : (bi += @intCast(u32, 1)) { total_states += count_per_block[@intCast(usize, bi)]; }

    var seg_base: [*]u32 = @ptrCast([*]u32, bumpAlloc(actx.alloc, @intCast(usize, m + @intCast(u32, 1)) * @intCast(usize, 4), @intCast(usize, 4)));
    var block_map: [*]u32 = @ptrCast([*]u32, bumpAlloc(actx.alloc, @intCast(usize, m + @intCast(u32, 1)) * @intCast(usize, 4), @intCast(usize, 4)));
    var resume_target: [*]u32 = @ptrCast([*]u32, bumpAlloc(actx.alloc, @intCast(usize, total_states + @intCast(u32, 2)) * @intCast(usize, 4), @intCast(usize, 4)));
    var next_id: u32 = @intCast(u32, 2);
    var state_cursor: u32 = @intCast(u32, 0);
    bi = @intCast(u32, 0);
    while (bi < m) : (bi += @intCast(u32, 1)) {
        seg_base[@intCast(usize, bi)] = next_id;
        block_map[@intCast(usize, bi)] = next_id;
        var c = count_per_block[@intCast(usize, bi)];
        var k: u32 = @intCast(u32, 0);
        while (k < c) : (k += @intCast(u32, 1)) {
            state_cursor += @intCast(u32, 1);
            resume_target[@intCast(usize, state_cursor - @intCast(u32, 1))] = next_id + k + @intCast(u32, 1);
        }
        next_id += c + @intCast(u32, 1);
    }
    var total_blocks: u32 = next_id;
    var terminal_id: u32 = @intCast(u32, 1);

    bi = @intCast(u32, 0);
    while (bi < total_blocks) : (bi += @intCast(u32, 1)) {
        lir_mod.basicBlockArrayListAppend(&step.blocks, lir_mod.BasicBlock{
            .id = bi,
            .insts = lir_mod.lirInstArrayListInit(actx.alloc),
            .is_terminated = @intCast(u8, 0),
        });
    }

    var b = Build{
        .step = &step,
        .orig = lf,
        .reg = reg,
        .base = base,
        .frame_temp = @intCast(u32, 0),
        .opt = opt,
        .seg_base = seg_base,
        .resume_target = resume_target,
        .block_map = block_map,
        .nblocks = m,
    };

    var state_off: u32 = @intCast(u32, 0);
    var fi: usize = @intCast(usize, 0);
    while (fi < actx.layout.fields.len) : (fi += @intCast(usize, 1)) {
        var f = actx.layout.fields.items[fi];
        if (f.kind == async_frame_layout.ASYNC_FIELD_STATE) { state_off = f.offset; }
    }

    var st = loadField(&b, @intCast(u32, 0), state_off, type_mod.TYPE_U8);
    if (actx.safe_checks) {
        var lim = newTemp(&b, type_mod.TYPE_U8);
        emit(&b, @intCast(u32, 0), LirInst{ .int_const = .{ .value = @intCast(u64, total_states), .result = lim } });
        var stok = newTemp(&b, type_mod.TYPE_U8);
        emit(&b, @intCast(u32, 0), LirInst{ .binary = .{ .op = BIN_LE, .lhs = st, .rhs = lim, .result = stok } });
        emit(&b, @intCast(u32, 0), LirInst{ .check_trap = .{ .cond = stok, .kind = @intCast(u8, 4) } });
    }
    var sw_base = step.switch_cases.len;
    var sw_off: u32 = @intCast(u32, total_states + @intCast(u32, 1));
    lir_mod.switchCaseArrayListAppend(&step.switch_cases, lir_mod.SwitchCase{ .value = @intCast(u64, 0), .target_bb = block_map[0] });
    var n2: u32 = @intCast(u32, 1);
    while (n2 <= total_states) : (n2 += @intCast(u32, 1)) {
        lir_mod.switchCaseArrayListAppend(&step.switch_cases, lir_mod.SwitchCase{ .value = @intCast(u64, n2), .target_bb = resume_target[@intCast(usize, n2 - @intCast(u32, 1))] });
    }
    emit(&b, @intCast(u32, 0), LirInst{ .switch_br = .{
        .cond = st,
        .cases_start = @intCast(u32, sw_base),
        .cases_count = total_states + @intCast(u32, 1),
        .else_bb = terminal_id,
    } });
    _ = sw_off;

    emit(&b, terminal_id, LirInst{ .ret_void = {} });
    step.blocks.items[@intCast(usize, terminal_id)].is_terminated = @intCast(u8, 1);

    var sci: usize = @intCast(usize, 0);
    while (sci < lf.switch_cases.len) : (sci += @intCast(usize, 1)) {
        var sc = lf.switch_cases.items[sci];
        lir_mod.switchCaseArrayListAppend(&step.switch_cases, lir_mod.SwitchCase{ .value = sc.value, .target_bb = remapBb(&b, sc.target_bb) });
    }

    var entry_seg = seg_base[0];
    var pi: usize = @intCast(usize, 0);
    while (pi < lf.params.len) : (pi += @intCast(usize, 1)) {
        var p = lf.params.items[pi];
        emit(&b, entry_seg, LirInst{ .decl_local = .{ .name_id = p.name_id, .type_id = p.type_id, .temp = p.temp_id + base } });
    }

    var pf: usize = @intCast(usize, 0);
    while (pf < actx.layout.fields.len) : (pf += @intCast(usize, 1)) {
        var fld = actx.layout.fields.items[pf];
        if (fld.kind == async_frame_layout.ASYNC_FIELD_PARAM) {
            var v = loadField(&b, entry_seg, fld.offset, fld.type_id);
            emit(&b, entry_seg, LirInst{ .assign = .{ .dst = fld.temp_id + base, .src = v, .name_id = @intCast(u32, 0) } });
        }
    }

    bi = @intCast(u32, 0);
    while (bi < m) : (bi += @intCast(u32, 1)) {
        var bb = &lf.blocks.items[@intCast(usize, bi)];
        var s: u32 = @intCast(u32, 0);
        var cur = seg_base[@intCast(usize, bi)];
        var pre: u32 = @intCast(u32, 0);
        var pb: u32 = @intCast(u32, 0);
        while (pb < bi) : (pb += @intCast(u32, 1)) { pre += count_per_block[@intCast(usize, pb)]; }
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            var inst = bb.insts.items[ii];
            if (isExplicitSuspend(reg, lf, inst)) {
                var state = pre + s + @intCast(u32, 1);
                saveAllFields(&b, cur, actx.layout);
                var sv = newTemp(&b, type_mod.TYPE_U8);
                emit(&b, cur, LirInst{ .int_const = .{ .value = @intCast(u64, state), .result = sv } });
                storeField(&b, cur, state_off, type_mod.TYPE_U8, sv);
                var yld = newTemp(&b, opt);
                emit(&b, cur, LirInst{ .wrap_optional = .{ .value = @intCast(u32, 0), .result = yld, .type_id = opt } });
                emit(&b, cur, LirInst{ .ret = yld });
                step.blocks.items[@intCast(usize, cur)].is_terminated = @intCast(u8, 1);
                s += @intCast(u32, 1);
                cur = seg_base[@intCast(usize, bi)] + s;
                reloadAllFields(&b, cur, actx.layout);
                continue;
            }
            var remapped = remapInst(&b, inst, sw_off);
            emit(&b, cur, remapped);
            switch (inst) {
                .jump => { step.blocks.items[@intCast(usize, cur)].is_terminated = @intCast(u8, 1); },
                .branch => { step.blocks.items[@intCast(usize, cur)].is_terminated = @intCast(u8, 1); },
                .switch_br => { step.blocks.items[@intCast(usize, cur)].is_terminated = @intCast(u8, 1); },
                .ret => { step.blocks.items[@intCast(usize, cur)].is_terminated = @intCast(u8, 1); },
                .ret_void => { step.blocks.items[@intCast(usize, cur)].is_terminated = @intCast(u8, 1); },
                .trap => { step.blocks.items[@intCast(usize, cur)].is_terminated = @intCast(u8, 1); },
                else => {},
            }
        }
    }

    var slot = lir_stream.lirStreamAppend(actx.lir_stream, step);
    lir_mod.lirSlotArrayListAppend(actx.lir_slots, slot);
}
