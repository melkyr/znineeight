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
const diag_mod = @import("diagnostics.zig");
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
const BIN_SUB: u8 = @intCast(u8, 1);
const BIN_OR: u8 = @intCast(u8, 6);
const BIN_NE: u8 = @intCast(u8, 11);
const BIN_LE: u8 = @intCast(u8, 13);
const BIN_GT: u8 = @intCast(u8, 14);

// Task 7 — per-task LIFO child-frame Context layout (compiler-core view). The
// caller-provided `ctx` points at this header; the child-frame pool bytes follow
// it. `used` stays at offset 0 (the R1 interim convention) so existing
// `ctx[0..usize] = used` callers keep working; `capacity` and the sticky `oom`
// flag are appended before the pool base.
//   ctx + 0*sizeof(usize) : used      (bump pointer)
//   ctx + 1*sizeof(usize) : capacity  (pool bytes; test-supplied)
//   ctx + 2*sizeof(usize) : oom       (u8, sticky)
//   ctx + 3*sizeof(usize) : pool base (child frames start here)
pub const CTX_USED_OFF: u32 = @intCast(u32, 0);
pub const CTX_CAP_OFF: u32 = @intCast(u32, @sizeOf(usize));
pub const CTX_OOM_OFF: u32 = @intCast(u32, @sizeOf(usize)) * @intCast(u32, 2);
pub const CTX_POOL_OFF: u32 = @intCast(u32, @sizeOf(usize)) * @intCast(u32, 3);

pub const AsyncTransformCtx = struct {
    alloc: *Sand,
    registry: *TypeRegistry,
    interner: *StringInterner,
    lir_stream: *lir_stream.LirStream,
    lir_slots: *lir_mod.LirSlotArrayList,
    suspending_fns: *hash_mod.U64ToU32Map,
    layout: *const AsyncFrameLayout,
    safe_checks: bool,
    frame_sizes: *hash_mod.U64ToU32Map,
    async_layouts: *hash_mod.U64ToU32Map,
    diag: *diag_mod.DiagnosticCollector,
};

fn bumpAlloc(alloc: *Sand, size: usize, align: usize) [*]u8 {
    return @ptrCast([*]u8, alloc_mod.sandAlloc(alloc, size, align) catch unreachable);
}

fn allocPrArray(alloc: *Sand, count: u32) [*]u32 {
    var c = count;
    if (c == @intCast(u32, 0)) c = @intCast(u32, 1);
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, c) * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable;
    return @ptrCast([*]u32, raw);
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

fn instSuspendKind(reg: *TypeRegistry, lf: *LirFunction, inst: LirInst, suspending_fns: *hash_mod.U64ToU32Map) u8 {
    switch (inst) {
        .int_const => |ic| {
            if (ic.value != @intCast(u64, 0)) return @intCast(u8, 0);
            if (typeIsPtrVoid(reg, tempType(lf, ic.result))) return @intCast(u8, 1);
            return @intCast(u8, 0);
        },
        .call_direct => |slot| {
            var cd = lir_mod.lirSideGetCallDirect(lf, slot);
            if (async_analysis.asyncIsSuspending(suspending_fns, cd.module_id, cd.name_id)) return @intCast(u8, 2);
            return @intCast(u8, 0);
        },
        else => return @intCast(u8, 0),
    }
}

const Build = struct {
    step: *LirFunction,
    orig: *LirFunction,
    actx: *AsyncTransformCtx,
    reg: *TypeRegistry,
    base: u32,
    frame_temp: u32,
    opt: u32,
    block_map: [*]u32,
    nblocks: u32,
    state_off: u32,
    state_type: u32,
    child_off: u32,
    child_present: bool,
    pr_off: [*]u32,
    pr_ty: [*]u32,
    pr_count: u32,
    pr_present: bool,
    result_off: u32,
    result_present: bool,
    child_temp: u32,
    ret_val_temp: u32,
    ret_val_present: bool,
    ep_store_id: u32,
    ep_dostore_id: u32,
    ep_ret_id: u32,
};

fn newTemp(b: *Build, type_id: u32) u32 {
    var tid: u32 = @intCast(u32, b.step.hoisted_temps.len);
    lir_mod.tempDeclArrayListAppend(&b.step.hoisted_temps, lir_mod.TempDecl{ .temp_id = tid, .type_id = type_id });
    return tid;
}

fn emit(b: *Build, blk: u32, inst: LirInst) void {
    lir_mod.lirInstArrayListAppend(&b.step.blocks.items[@intCast(usize, blk)].insts, inst);
}

fn fieldPtrBase(b: *Build, blk: u32, base_temp: u32, offset: u32, field_type: u32) u32 {
    var pi = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, blk, LirInst{ .ptr_to_int = .{ .value = base_temp, .result = pi } });
    var off = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, blk, LirInst{ .int_const = .{ .value = @intCast(u64, offset), .result = off } });
    var addr = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, blk, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = pi, .rhs = off, .result = addr } });
    var pt_type = type_mod.typeRegistryGetOrCreatePtr(b.reg, field_type, false);
    var pt = newTemp(b, pt_type);
    emit(b, blk, LirInst{ .int_to_ptr = .{ .value = addr, .target = pt_type, .result = pt } });
    return pt;
}

fn fieldPtr(b: *Build, blk: u32, offset: u32, field_type: u32) u32 {
    return fieldPtrBase(b, blk, b.frame_temp, offset, field_type);
}

fn loadFieldBase(b: *Build, blk: u32, base_temp: u32, offset: u32, field_type: u32) u32 {
    var pt = fieldPtrBase(b, blk, base_temp, offset, field_type);
    var v = newTemp(b, field_type);
    emit(b, blk, LirInst{ .load = .{ .ptr = pt, .result = v } });
    return v;
}

fn loadField(b: *Build, blk: u32, offset: u32, field_type: u32) u32 {
    return loadFieldBase(b, blk, b.frame_temp, offset, field_type);
}

fn storeFieldBase(b: *Build, blk: u32, base_temp: u32, offset: u32, field_type: u32, value: u32) void {
    var pt = fieldPtrBase(b, blk, base_temp, offset, field_type);
    emit(b, blk, LirInst{ .store = .{ .ptr = pt, .value = value } });
}

fn storeField(b: *Build, blk: u32, offset: u32, field_type: u32, value: u32) void {
    storeFieldBase(b, blk, b.frame_temp, offset, field_type, value);
}

fn saveAllFields(b: *Build, blk: u32, lay: *const AsyncFrameLayout) void {
    var f: usize = @intCast(usize, 0);
    while (f < lay.fields.len) : (f += @intCast(usize, 1)) {
        var fld = lay.fields.items[f];
        if (fld.kind == async_frame_layout.ASYNC_FIELD_PARAM or fld.kind == async_frame_layout.ASYNC_FIELD_LIVE) {
            storeField(b, blk, fld.offset, fld.type_id, fld.temp_id + b.base);
        }
    }
    if (b.child_present) {
        storeField(b, blk, b.child_off, ptrVoid(b.reg), b.child_temp);
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
    if (b.child_present) {
        var cv = loadField(b, blk, b.child_off, ptrVoid(b.reg));
        emit(b, blk, LirInst{ .assign = .{ .dst = b.child_temp, .src = cv, .name_id = @intCast(u32, 0) } });
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

// Emit the child drive sequence: load the child's step word (child+0), convert
// it to the generic step fn pointer, and issue `step(child, null)`; branch to
// `yield_blk` when the child is still suspended, else to `after_blk`.
fn emitDriveChild(b: *Build, blk: u32, child_temp: u32, yield_blk: u32, after_blk: u32) void {
    var word = loadFieldBase(b, blk, child_temp, @intCast(u32, 0), type_mod.TYPE_USIZE);
    var gfn = asyncGenericStepFnType(b.reg, b.actx.interner);
    var gpt = type_mod.typeRegistryGetOrCreatePtr(b.reg, gfn, false);
    var pt = newTemp(b, gpt);
    emit(b, blk, LirInst{ .int_to_ptr = .{ .value = word, .target = gpt, .result = pt } });
    var a0 = newTemp(b, ptrVoid(b.reg));
    emit(b, blk, LirInst{ .assign = .{ .dst = a0, .src = child_temp, .name_id = @intCast(u32, 0) } });
    var a1 = newTemp(b, b.opt);
    emit(b, blk, LirInst{ .set_optional_null = .{ .result = a1, .type_id = b.opt } });
    var r = newTemp(b, b.opt);
    emit(b, blk, LirInst{ .call = .{ .callee = pt, .args_start = a0, .args_count = @intCast(u32, 2), .result = r } });
    var hv = newTemp(b, type_mod.TYPE_U8);
    emit(b, blk, LirInst{ .check_optional = .{ .value = r, .result = hv } });
    emit(b, blk, LirInst{ .branch = .{ .cond = hv, .then_bb = yield_blk, .else_bb = after_blk } });
}

// Q1 steps 1-10: rewrite `call_direct g` at the current segment into a
// child-frame init + first child step + conditional yield, with the resume path
// in `loop_done` and the continuation in `after`.
fn emitAwait(b: *Build, blk: u32, cd: lir_mod.CallDirectData, state: u32, alloc_blk: u32, yield_blk: u32, loop_done: u32, after: u32, k: u32, terminal_id: u32) void {
    var reg = b.reg;
    var callee_lay: *const AsyncFrameLayout = b.actx.layout;
    if (async_frame_layout.asyncLayoutLookup(b.actx.async_layouts, cd.module_id, cd.name_id)) |cl| { callee_lay = cl; }
    // Per-await value gate: a void-returning await reserves no kind-7 slot and
    // does not advance `k`. Required P4 per-slot type assertion: the k-th
    // value-returning implicit await's callee return type must equal the k-th
    // reserved kind-7 slot type, else P2/P3 and P4 disagree (silent frame
    // corruption). Fail closed with ERR_9001_ICE instead of a mis-typed store.
    var is_value: bool = cd.return_type != type_mod.TYPE_VOID;
    var slot_ok: bool = b.pr_present;
    if (is_value) {
        if (!b.pr_present or k >= b.pr_count or b.pr_ty[@intCast(usize, k)] != cd.return_type) {
            var ice_msg: []const u8 = "async parent_result slot type mismatch (P2/P3 vs P4 order desync)";
            _ = diag_mod.diagnosticCollectorAdd(b.actx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_9001_ICE)), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), ice_msg);
            slot_ok = false;
        }
    }
    // (1) ctx from the caller frame.
    var ctx_off: u32 = @intCast(u32, 0);
    var f: usize = @intCast(usize, 0);
    while (f < b.actx.layout.fields.len) : (f += @intCast(usize, 1)) {
        var fld = b.actx.layout.fields.items[f];
        if (fld.kind == async_frame_layout.ASYNC_FIELD_CTX) { ctx_off = fld.offset; }
    }
    var ctx = loadField(b, blk, ctx_off, ptrVoid(reg));
    // (2) Task 7 pool accounting. Inline-read the Context header
    // (`used@0`, `capacity@1*usize`, sticky `oom@2*usize`; pool base ctx+3*usize).
    // Exhaustion (`used + size > capacity`) sets `oom` and takes the null/error
    // terminal path; otherwise the child is bump-allocated in `alloc_blk`.
    var used = loadFieldBase(b, blk, ctx, CTX_USED_OFF, type_mod.TYPE_USIZE);
    var capacity = loadFieldBase(b, blk, ctx, CTX_CAP_OFF, type_mod.TYPE_USIZE);
    var oom_old = loadFieldBase(b, blk, ctx, CTX_OOM_OFF, type_mod.TYPE_U8);
    // `frame_sizes[callee]` is authoritative (Task 5 P2 is the sole writer and
    // populates every suspending callee). The absent-entry branch is therefore
    // unreachable: it records the ICE and the `fsz = 0` placeholder below is
    // never reached on a successful compile (M5).
    var fsz: u64 = @intCast(u64, 0);
    if (async_analysis.asyncFrameSizeOf(b.actx.frame_sizes, cd.module_id, cd.name_id)) |fs| {
        fsz = @intCast(u64, fs);
    } else {
        var ice_msg2: []const u8 = "async frame_sizes missing for implicit-await callee";
        _ = diag_mod.diagnosticCollectorAdd(b.actx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_9001_ICE)), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), ice_msg2);
    }
    var fsz_t = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, blk, LirInst{ .int_const = .{ .value = fsz, .result = fsz_t } });
    var need = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, blk, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = used, .rhs = fsz_t, .result = need } });
    var over = newTemp(b, type_mod.TYPE_U8);
    emit(b, blk, LirInst{ .binary = .{ .op = BIN_GT, .lhs = need, .rhs = capacity, .result = over } });
    var oom_new = newTemp(b, type_mod.TYPE_U8);
    emit(b, blk, LirInst{ .binary = .{ .op = BIN_OR, .lhs = oom_old, .rhs = over, .result = oom_new } });
    storeFieldBase(b, blk, ctx, CTX_OOM_OFF, type_mod.TYPE_U8, oom_new);
    emit(b, blk, LirInst{ .branch = .{ .cond = over, .then_bb = terminal_id, .else_bb = alloc_blk } });
    b.step.blocks.items[@intCast(usize, blk)].is_terminated = @intCast(u8, 1);
    // (3) alloc_blk: bump allocation, child = pool + used; store used = need.
    // The pool base is the byte region immediately after the Context header.
    var ctx_int = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, alloc_blk, LirInst{ .ptr_to_int = .{ .value = ctx, .result = ctx_int } });
    var pool_off_t = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, alloc_blk, LirInst{ .int_const = .{ .value = @intCast(u64, CTX_POOL_OFF), .result = pool_off_t } });
    var pool = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, alloc_blk, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = ctx_int, .rhs = pool_off_t, .result = pool } });
    var used_p = fieldPtrBase(b, alloc_blk, ctx, CTX_USED_OFF, type_mod.TYPE_USIZE);
    emit(b, alloc_blk, LirInst{ .store = .{ .ptr = used_p, .value = need } });
    var child_int = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, alloc_blk, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = pool, .rhs = used, .result = child_int } });
    var child = newTemp(b, ptrVoid(reg));
    emit(b, alloc_blk, LirInst{ .int_to_ptr = .{ .value = child_int, .target = ptrVoid(reg), .result = child } });
    // (4) g's step word at child+0.
    var step_name = asyncStepNameId(b.actx.interner, cd.name_id);
    var step_fn = asyncStepFnType(reg, b.actx.interner, step_name, cd.module_id);
    var step_pt = type_mod.typeRegistryGetOrCreatePtr(reg, step_fn, false);
    var fr = newTemp(b, step_pt);
    emit(b, alloc_blk, LirInst{ .func_ref = .{ .name_id = step_name, .module_id = cd.module_id, .result = fr } });
    var fri = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, alloc_blk, LirInst{ .ptr_to_int = .{ .value = fr, .result = fri } });
    storeFieldBase(b, alloc_blk, child, @intCast(u32, 0), type_mod.TYPE_USIZE, fri);
    // (5) child header.
    var c_ctx_off: u32 = @intCast(u32, 0);
    var c_state_off: u32 = @intCast(u32, 0);
    var c_state_type: u32 = type_mod.TYPE_U8;
    var c_result_off: u32 = @intCast(u32, 0);
    var c_result_present: bool = false;
    var f2: usize = @intCast(usize, 0);
    while (f2 < callee_lay.fields.len) : (f2 += @intCast(usize, 1)) {
        var fld2 = callee_lay.fields.items[f2];
        if (fld2.kind == async_frame_layout.ASYNC_FIELD_CTX) { c_ctx_off = fld2.offset; }
        if (fld2.kind == async_frame_layout.ASYNC_FIELD_STATE) { c_state_off = fld2.offset; c_state_type = fld2.type_id; }
        if (fld2.kind == async_frame_layout.ASYNC_FIELD_RESULT) { c_result_off = fld2.offset; c_result_present = true; }
    }
    storeFieldBase(b, alloc_blk, child, c_ctx_off, ptrVoid(reg), ctx);
    var zero_st = newTemp(b, c_state_type);
    emit(b, alloc_blk, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = zero_st } });
    storeFieldBase(b, alloc_blk, child, c_state_off, c_state_type, zero_st);
    // (6) copy call args into g's param offsets (natural layout order).
    var arg_i: u32 = @intCast(u32, 0);
    var f3: usize = @intCast(usize, 0);
    while (f3 < callee_lay.fields.len) : (f3 += @intCast(usize, 1)) {
        var fld3 = callee_lay.fields.items[f3];
        if (fld3.kind == async_frame_layout.ASYNC_FIELD_PARAM) {
            var argt = cd.args_start + arg_i + b.base;
            storeFieldBase(b, alloc_blk, child, fld3.offset, fld3.type_id, argt);
            arg_i += @intCast(u32, 1);
        }
    }
    // D3: point the child's hidden `result` at the caller's k-th hidden parent
    // slot (value-returning target only; null otherwise, per the R8 void gate).
    if (c_result_present) {
        if (is_value and slot_ok) {
            var fi = newTemp(b, type_mod.TYPE_USIZE);
            emit(b, alloc_blk, LirInst{ .ptr_to_int = .{ .value = b.frame_temp, .result = fi } });
            var poff = newTemp(b, type_mod.TYPE_USIZE);
            emit(b, alloc_blk, LirInst{ .int_const = .{ .value = @intCast(u64, b.pr_off[@intCast(usize, k)]), .result = poff } });
            var paddr = newTemp(b, type_mod.TYPE_USIZE);
            emit(b, alloc_blk, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = fi, .rhs = poff, .result = paddr } });
            var pr = newTemp(b, ptrVoid(reg));
            emit(b, alloc_blk, LirInst{ .int_to_ptr = .{ .value = paddr, .target = ptrVoid(reg), .result = pr } });
            storeFieldBase(b, alloc_blk, child, c_result_off, ptrVoid(reg), pr);
        } else {
            var nptr = newTemp(b, ptrVoid(reg));
            emit(b, alloc_blk, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = nptr } });
            storeFieldBase(b, alloc_blk, child, c_result_off, ptrVoid(reg), nptr);
        }
    }
    // (7) persist the child pointer in the caller's hidden child field.
    emit(b, alloc_blk, LirInst{ .assign = .{ .dst = b.child_temp, .src = child, .name_id = @intCast(u32, 0) } });
    storeField(b, alloc_blk, b.child_off, ptrVoid(reg), b.child_temp);
    // (8) first child step + conditional yield.
    emitDriveChild(b, alloc_blk, b.child_temp, yield_blk, after);
    b.step.blocks.items[@intCast(usize, alloc_blk)].is_terminated = @intCast(u8, 1);
    // (9) yield block.
    saveAllFields(b, yield_blk, b.actx.layout);
    var sv = newTemp(b, b.state_type);
    emit(b, yield_blk, LirInst{ .int_const = .{ .value = @intCast(u64, state), .result = sv } });
    storeField(b, yield_blk, b.state_off, b.state_type, sv);
    var yld = newTemp(b, b.opt);
    emit(b, yield_blk, LirInst{ .wrap_optional = .{ .value = @intCast(u32, 0), .result = yld, .type_id = b.opt } });
    emit(b, yield_blk, LirInst{ .ret = yld });
    b.step.blocks.items[@intCast(usize, yield_blk)].is_terminated = @intCast(u8, 1);
    // (10) loop_done (resume target only): reload + re-drive the child.
    reloadAllFields(b, loop_done, b.actx.layout);
    emitDriveChild(b, loop_done, b.child_temp, yield_blk, after);
    b.step.blocks.items[@intCast(usize, loop_done)].is_terminated = @intCast(u8, 1);
    // (11) after: pop the child frame (restore the mark: used -= frame_size),
    // then deliver the awaited value to the call's result temp and continue.
    var actx_after = loadField(b, after, ctx_off, ptrVoid(reg));
    var used_p_after = fieldPtrBase(b, after, actx_after, CTX_USED_OFF, type_mod.TYPE_USIZE);
    var used_after = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, after, LirInst{ .load = .{ .ptr = used_p_after, .result = used_after } });
    var fsz_t2 = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, after, LirInst{ .int_const = .{ .value = fsz, .result = fsz_t2 } });
    var mark = newTemp(b, type_mod.TYPE_USIZE);
    emit(b, after, LirInst{ .binary = .{ .op = BIN_SUB, .lhs = used_after, .rhs = fsz_t2, .result = mark } });
    emit(b, after, LirInst{ .store = .{ .ptr = used_p_after, .value = mark } });
    if (is_value and slot_ok) {
        var pv = loadField(b, after, b.pr_off[@intCast(usize, k)], b.pr_ty[@intCast(usize, k)]);
        emit(b, after, LirInst{ .assign = .{ .dst = cd.result + b.base, .src = pv, .name_id = @intCast(u32, 0) } });
    }
}

// D2: pinned root-`main` driver pool size (residual R7). The root task's
// children are bump-allocated from `ctx+usize`; the pool has no authoritative
// size until Task 7 owns the per-task LIFO pool/Context ABI, so pin the interim
// Task-6 fixed constant (the same 256-byte convention the await fixtures use).
const ASYNC_ROOT_POOL_BYTES: u32 = 256;

fn isRootMain(actx: *AsyncTransformCtx, lf: *LirFunction) bool {
    if (lf.module_id != @intCast(u32, 0)) return false;
    if (lf.is_pub != @intCast(u8, 1)) return false;
    var nm = si_mod.stringInternerGet(actx.interner, lf.name_id);
    if (nm.len != @intCast(usize, 4)) return false;
    return nm[0] == 'm' and nm[1] == 'a' and nm[2] == 'i' and nm[3] == 'n';
}

// D2: synthesize the root-`main` synchronous driver under `main`'s original
// name_id/module_id/`is_pub` and source-level param signature. The driver (a)
// declares a local root buffer of `frame_sizes[main]` bytes and a local pool
// buffer, (b) writes the step word @0, `ctx = &pool` @ctx_off, `state = 0`, and
// copies main's params to the frame param offsets, (c) drives main's step to
// completion (`r = step(root,null); while (has_value(r)) r = step(root,null);`),
// and (d) returns. `emitMainWrapper` wraps it unchanged. Backend-agnostic; 0 new
// `LirInst`.
fn emitMainDriver(actx: *AsyncTransformCtx, lf: *LirFunction) void {
    var reg = actx.registry;
    var ptr_void = ptrVoid(reg);
    var opt = optPtrVoid(reg);

    var driver = LirFunction{
        .name_id = lf.name_id,
        .module_id = lf.module_id,
        .return_type = lf.return_type,
        .params = lir_mod.lirParamArrayListInit(actx.alloc),
        .blocks = lir_mod.basicBlockArrayListInit(actx.alloc),
        .hoisted_temps = lir_mod.tempDeclArrayListInit(actx.alloc),
        .switch_cases = lir_mod.switchCaseArrayListInit(actx.alloc),
        .side_table = lir_mod.lirSideEntryArrayListInit(actx.alloc),
        .temp_variant_sub_field = hash_mod.u32ToU32MapInit(actx.alloc),
        .is_extern = @intCast(u8, 0),
        .is_pub = lf.is_pub,
        .is_variadic = lf.is_variadic,
        .call_conv = lf.call_conv,
        .poison_uninit = lf.poison_uninit,
    };
    var pi: usize = @intCast(usize, 0);
    while (pi < lf.params.len) : (pi += @intCast(usize, 1)) {
        lir_mod.lirParamArrayListAppend(&driver.params, lf.params.items[pi]);
    }
    // Preserve the original temp ids (contiguous) so `newTemp` can append after.
    var hi: usize = @intCast(usize, 0);
    while (hi < lf.hoisted_temps.len) : (hi += @intCast(usize, 1)) {
        lir_mod.tempDeclArrayListAppend(&driver.hoisted_temps, lf.hoisted_temps.items[hi]);
    }
    var blk_i: u32 = @intCast(u32, 0);
    while (blk_i < @intCast(u32, 3)) : (blk_i += @intCast(u32, 1)) {
        lir_mod.basicBlockArrayListAppend(&driver.blocks, lir_mod.BasicBlock{
            .id = blk_i,
            .insts = lir_mod.lirInstArrayListInit(actx.alloc),
            .is_terminated = @intCast(u8, 0),
        });
    }

    var root_sz: u32 = actx.layout.layout_size;
    if (async_analysis.asyncFrameSizeOf(actx.frame_sizes, lf.module_id, lf.name_id)) |fs| root_sz = fs;

    var b = Build{
        .step = &driver,
        .orig = lf,
        .actx = actx,
        .reg = reg,
        .base = @intCast(u32, 0),
        .frame_temp = @intCast(u32, 0),
        .opt = opt,
        .block_map = undefined,
        .nblocks = @intCast(u32, 0),
        .state_off = @intCast(u32, 0),
        .state_type = type_mod.TYPE_U8,
        .child_off = @intCast(u32, 0),
        .child_present = false,
        .pr_off = undefined,
        .pr_ty = undefined,
        .pr_count = @intCast(u32, 0),
        .pr_present = false,
        .result_off = @intCast(u32, 0),
        .result_present = false,
        .child_temp = @intCast(u32, 0),
        .ret_val_temp = @intCast(u32, 0),
        .ret_val_present = false,
        .ep_store_id = @intCast(u32, 0),
        .ep_dostore_id = @intCast(u32, 0),
        .ep_ret_id = @intCast(u32, 0),
    };

    var root_name = si_mod.stringInternerIntern(actx.interner, "__az_root");
    var pool_name = si_mod.stringInternerIntern(actx.interner, "__az_pool");
    var root_arr_t = type_mod.typeRegistryGetOrCreateArray(reg, type_mod.TYPE_U8, root_sz);
    var pool_arr_t = type_mod.typeRegistryGetOrCreateArray(reg, type_mod.TYPE_U8, ASYNC_ROOT_POOL_BYTES);
    var root_arr_pt = type_mod.typeRegistryGetOrCreatePtr(reg, root_arr_t, false);
    var pool_arr_pt = type_mod.typeRegistryGetOrCreatePtr(reg, pool_arr_t, false);

    var root_arr = newTemp(&b, root_arr_t);
    emit(&b, @intCast(u32, 0), LirInst{ .decl_local = .{ .name_id = root_name, .type_id = root_arr_t, .temp = root_arr } });
    var root_ap = newTemp(&b, root_arr_pt);
    emit(&b, @intCast(u32, 0), LirInst{ .addr_of = .{ .operand = root_arr, .result = root_ap } });
    var root = newTemp(&b, ptr_void);
    emit(&b, @intCast(u32, 0), LirInst{ .ptr_cast = .{ .value = root_ap, .target = ptr_void, .result = root } });
    b.frame_temp = root;

    var pool_arr = newTemp(&b, pool_arr_t);
    emit(&b, @intCast(u32, 0), LirInst{ .decl_local = .{ .name_id = pool_name, .type_id = pool_arr_t, .temp = pool_arr } });
    var pool_ap = newTemp(&b, pool_arr_pt);
    emit(&b, @intCast(u32, 0), LirInst{ .addr_of = .{ .operand = pool_arr, .result = pool_ap } });
    var pool = newTemp(&b, ptr_void);
    emit(&b, @intCast(u32, 0), LirInst{ .ptr_cast = .{ .value = pool_ap, .target = ptr_void, .result = pool } });

    // Task 7 Context header at `__az_pool` (ctx == pool handle): `used = 0`,
    // `capacity = usable bytes after the header`, `oom = 0`; pool base is
    // `__az_pool + CTX_POOL_OFF` (derived by the await site).
    var z_usize = newTemp(&b, type_mod.TYPE_USIZE);
    emit(&b, @intCast(u32, 0), LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = z_usize } });
    storeFieldBase(&b, @intCast(u32, 0), pool, CTX_USED_OFF, type_mod.TYPE_USIZE, z_usize);
    var cap_t = newTemp(&b, type_mod.TYPE_USIZE);
    emit(&b, @intCast(u32, 0), LirInst{ .int_const = .{ .value = @intCast(u64, ASYNC_ROOT_POOL_BYTES - CTX_POOL_OFF), .result = cap_t } });
    storeFieldBase(&b, @intCast(u32, 0), pool, CTX_CAP_OFF, type_mod.TYPE_USIZE, cap_t);
    var z_oom = newTemp(&b, type_mod.TYPE_U8);
    emit(&b, @intCast(u32, 0), LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = z_oom } });
    storeFieldBase(&b, @intCast(u32, 0), pool, CTX_OOM_OFF, type_mod.TYPE_U8, z_oom);

    // main's step word @ root+0.
    var step_name = asyncStepNameId(actx.interner, lf.name_id);
    var step_fn = asyncStepFnType(reg, actx.interner, step_name, lf.module_id);
    var step_pt = type_mod.typeRegistryGetOrCreatePtr(reg, step_fn, false);
    var fr = newTemp(&b, step_pt);
    emit(&b, @intCast(u32, 0), LirInst{ .func_ref = .{ .name_id = step_name, .module_id = lf.module_id, .result = fr } });
    var fri = newTemp(&b, type_mod.TYPE_USIZE);
    emit(&b, @intCast(u32, 0), LirInst{ .ptr_to_int = .{ .value = fr, .result = fri } });
    storeFieldBase(&b, @intCast(u32, 0), root, @intCast(u32, 0), type_mod.TYPE_USIZE, fri);

    // Header ctx/state + param copy from the authoritative layout.
    var fi: usize = @intCast(usize, 0);
    while (fi < actx.layout.fields.len) : (fi += @intCast(usize, 1)) {
        var fld = actx.layout.fields.items[fi];
        if (fld.kind == async_frame_layout.ASYNC_FIELD_CTX) {
            storeFieldBase(&b, @intCast(u32, 0), root, fld.offset, ptr_void, pool);
        } else if (fld.kind == async_frame_layout.ASYNC_FIELD_STATE) {
            b.state_type = fld.type_id;
            var z8 = newTemp(&b, fld.type_id);
            emit(&b, @intCast(u32, 0), LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = z8 } });
            storeFieldBase(&b, @intCast(u32, 0), root, fld.offset, fld.type_id, z8);
        } else if (fld.kind == async_frame_layout.ASYNC_FIELD_PARAM) {
            storeFieldBase(&b, @intCast(u32, 0), root, fld.offset, fld.type_id, fld.temp_id);
        }
    }

    // Drive to completion: first step in block 0, re-step loop in block 1, done
    // in block 2. `emitDriveChild` already loads step+0 / calls the generic step.
    emitDriveChild(&b, @intCast(u32, 0), root, @intCast(u32, 1), @intCast(u32, 2));
    driver.blocks.items[@intCast(usize, 0)].is_terminated = @intCast(u8, 1);
    emitDriveChild(&b, @intCast(u32, 1), root, @intCast(u32, 1), @intCast(u32, 2));
    driver.blocks.items[@intCast(usize, 1)].is_terminated = @intCast(u8, 1);
    emit(&b, @intCast(u32, 2), LirInst{ .ret_void = {} });
    driver.blocks.items[@intCast(usize, 2)].is_terminated = @intCast(u8, 1);

    var slot = lir_stream.lirStreamAppend(actx.lir_stream, driver);
    lir_mod.lirSlotArrayListAppend(actx.lir_slots, slot);
}

pub fn asyncTransform(lf: *LirFunction, actx: *AsyncTransformCtx) bool {
    if (!async_analysis.asyncIsSuspending(actx.suspending_fns, lf.module_id, lf.name_id)) return false;

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
    var state_base: [*]u32 = @ptrCast([*]u32, bumpAlloc(actx.alloc, @intCast(usize, m + @intCast(u32, 1)) * @intCast(usize, 4), @intCast(usize, 4)));
    var seg_first: [*]u32 = @ptrCast([*]u32, bumpAlloc(actx.alloc, @intCast(usize, m + @intCast(u32, 1)) * @intCast(usize, 4), @intCast(usize, 4)));
    var block_map: [*]u32 = @ptrCast([*]u32, bumpAlloc(actx.alloc, @intCast(usize, m + @intCast(u32, 1)) * @intCast(usize, 4), @intCast(usize, 4)));
    var bi: u32 = @intCast(u32, 0);
    var total_states: u32 = @intCast(u32, 0);
    var any_ret: bool = false;
    while (bi < m) : (bi += @intCast(u32, 1)) {
        var bb = &lf.blocks.items[@intCast(usize, bi)];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            var inst = bb.insts.items[ii];
            if (instSuspendKind(reg, lf, inst, actx.suspending_fns) != @intCast(u8, 0)) {
                total_states += @intCast(u32, 1);
            }
            switch (inst) {
                .ret => { any_ret = true; },
                else => {},
            }
        }
    }

    var state_resume: [*]u32 = @ptrCast([*]u32, bumpAlloc(actx.alloc, @intCast(usize, total_states + @intCast(u32, 2)) * @intCast(usize, 4), @intCast(usize, 4)));
    var state_yield: [*]u32 = @ptrCast([*]u32, bumpAlloc(actx.alloc, @intCast(usize, total_states + @intCast(u32, 2)) * @intCast(usize, 4), @intCast(usize, 4)));
    var state_after: [*]u32 = @ptrCast([*]u32, bumpAlloc(actx.alloc, @intCast(usize, total_states + @intCast(u32, 2)) * @intCast(usize, 4), @intCast(usize, 4)));
    // Task 7: one extra block per implicit await for the capacity-checked
    // allocation path (the `over` branch targets the shared terminal block).
    var state_alloc: [*]u32 = @ptrCast([*]u32, bumpAlloc(actx.alloc, @intCast(usize, total_states + @intCast(u32, 2)) * @intCast(usize, 4), @intCast(usize, 4)));

    var next_id: u32 = @intCast(u32, 2);
    var state_cursor: u32 = @intCast(u32, 0);
    bi = @intCast(u32, 0);
    while (bi < m) : (bi += @intCast(u32, 1)) {
        state_base[@intCast(usize, bi)] = state_cursor;
        var cur = next_id;
        next_id += @intCast(u32, 1);
        seg_first[@intCast(usize, bi)] = cur;
        block_map[@intCast(usize, bi)] = cur;
        var bb = &lf.blocks.items[@intCast(usize, bi)];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            var kk = instSuspendKind(reg, lf, bb.insts.items[ii], actx.suspending_fns);
            if (kk == @intCast(u8, 0)) continue;
            state_cursor += @intCast(u32, 1);
            var sidx = @intCast(usize, state_cursor - @intCast(u32, 1));
            if (kk == @intCast(u8, 1)) {
                state_resume[sidx] = next_id;
                next_id += @intCast(u32, 1);
                cur = state_resume[sidx];
            } else {
                state_yield[sidx] = next_id;
                next_id += @intCast(u32, 1);
                state_resume[sidx] = next_id;
                next_id += @intCast(u32, 1);
                state_after[sidx] = next_id;
                next_id += @intCast(u32, 1);
                state_alloc[sidx] = next_id;
                next_id += @intCast(u32, 1);
                cur = state_after[sidx];
            }
        }
    }

    var ret_val_present: bool = (lf.return_type != type_mod.TYPE_VOID) and any_ret;
    var ep_store_id: u32 = @intCast(u32, 0);
    var ep_dostore_id: u32 = @intCast(u32, 0);
    var ep_ret_id: u32 = @intCast(u32, 0);
    if (ret_val_present) {
        ep_store_id = next_id; next_id += @intCast(u32, 1);
        ep_dostore_id = next_id; next_id += @intCast(u32, 1);
        ep_ret_id = next_id; next_id += @intCast(u32, 1);
    }
    var total_blocks: u32 = next_id;
    var terminal_id: u32 = @intCast(u32, 1);

    // Layout-derived hidden offsets.
    var state_off: u32 = @intCast(u32, 0);
    var state_type: u32 = type_mod.TYPE_U8;
    var child_off: u32 = @intCast(u32, 0);
    var child_present: bool = false;
    var parent_result_present: bool = false;
    var pr_count: u32 = @intCast(u32, 0);
    var result_off: u32 = @intCast(u32, 0);
    var result_present: bool = false;
    var fi: usize = @intCast(usize, 0);
    while (fi < actx.layout.fields.len) : (fi += @intCast(usize, 1)) {
        var f = actx.layout.fields.items[fi];
        if (f.kind == async_frame_layout.ASYNC_FIELD_STATE) { state_off = f.offset; state_type = f.type_id; }
        if (f.kind == async_frame_layout.ASYNC_FIELD_CHILD) { child_off = f.offset; child_present = true; }
        if (f.kind == async_frame_layout.ASYNC_FIELD_RESULT) { result_off = f.offset; result_present = true; }
        if (f.kind == async_frame_layout.ASYNC_FIELD_PARENT_RESULT) { pr_count += @intCast(u32, 1); }
    }
    parent_result_present = pr_count > @intCast(u32, 0);
    // Ordered kind-7 slots in layout order (== P2's program order). P4 indexes
    // them with a running value-returning-await counter `k`.
    var pr_off = allocPrArray(actx.alloc, pr_count);
    var pr_ty = allocPrArray(actx.alloc, pr_count);
    var pr_i: u32 = @intCast(u32, 0);
    fi = @intCast(usize, 0);
    while (fi < actx.layout.fields.len) : (fi += @intCast(usize, 1)) {
        var f2 = actx.layout.fields.items[fi];
        if (f2.kind == async_frame_layout.ASYNC_FIELD_PARENT_RESULT) {
            pr_off[@intCast(usize, pr_i)] = f2.offset;
            pr_ty[@intCast(usize, pr_i)] = f2.type_id;
            pr_i += @intCast(u32, 1);
        }
    }

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
        .actx = actx,
        .reg = reg,
        .base = base,
        .frame_temp = @intCast(u32, 0),
        .opt = opt,
        .block_map = block_map,
        .nblocks = m,
        .state_off = state_off,
        .state_type = state_type,
        .child_off = child_off,
        .child_present = child_present,
        .pr_off = pr_off,
        .pr_ty = pr_ty,
        .pr_count = pr_count,
        .pr_present = parent_result_present,
        .result_off = result_off,
        .result_present = result_present,
        .child_temp = @intCast(u32, 0),
        .ret_val_temp = @intCast(u32, 0),
        .ret_val_present = ret_val_present,
        .ep_store_id = ep_store_id,
        .ep_dostore_id = ep_dostore_id,
        .ep_ret_id = ep_ret_id,
    };
    if (b.child_present) { b.child_temp = newTemp(&b, ptr_void); }
    if (b.ret_val_present) { b.ret_val_temp = newTemp(&b, lf.return_type); }

    // F2 guard: the layout's state width must hold the actual LIR suspension
    // count. P2's AST count is a conservative upper bound, so a mismatch means
    // P2 undercounted; fail closed with an ICE rather than truncate silently.
    var state_max: u32 = @intCast(u32, 0xFFFFFFFF);
    if (state_type == type_mod.TYPE_U8) { state_max = @intCast(u32, 255); }
    else if (state_type == type_mod.TYPE_U16) { state_max = @intCast(u32, 65535); }
    if (total_states > state_max) {
        var ice_st_msg: []const u8 = "async state width too small for suspension count (P2 count underflow)";
        _ = diag_mod.diagnosticCollectorAdd(actx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_9001_ICE)), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), ice_st_msg);
    }

    var st = loadField(&b, @intCast(u32, 0), state_off, state_type);
    if (actx.safe_checks) {
        var lim = newTemp(&b, state_type);
        emit(&b, @intCast(u32, 0), LirInst{ .int_const = .{ .value = @intCast(u64, total_states), .result = lim } });
        var stok = newTemp(&b, state_type);
        emit(&b, @intCast(u32, 0), LirInst{ .binary = .{ .op = BIN_LE, .lhs = st, .rhs = lim, .result = stok } });
        emit(&b, @intCast(u32, 0), LirInst{ .check_trap = .{ .cond = stok, .kind = @intCast(u8, 4) } });
    }
    var sw_base = step.switch_cases.len;
    var sw_off: u32 = @intCast(u32, total_states + @intCast(u32, 1));
    lir_mod.switchCaseArrayListAppend(&step.switch_cases, lir_mod.SwitchCase{ .value = @intCast(u64, 0), .target_bb = block_map[0] });
    var n2: u32 = @intCast(u32, 1);
    while (n2 <= total_states) : (n2 += @intCast(u32, 1)) {
        lir_mod.switchCaseArrayListAppend(&step.switch_cases, lir_mod.SwitchCase{ .value = @intCast(u64, n2), .target_bb = state_resume[@intCast(usize, n2 - @intCast(u32, 1))] });
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

    var entry_seg = seg_first[0];
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
    if (b.child_present) {
        var cz = newTemp(&b, ptr_void);
        emit(&b, entry_seg, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = cz } });
        emit(&b, entry_seg, LirInst{ .assign = .{ .dst = b.child_temp, .src = cz, .name_id = @intCast(u32, 0) } });
    }

    var pr_k: u32 = @intCast(u32, 0);
    bi = @intCast(u32, 0);
    while (bi < m) : (bi += @intCast(u32, 1)) {
        var bb = &lf.blocks.items[@intCast(usize, bi)];
        var s: u32 = @intCast(u32, 0);
        var cur = seg_first[@intCast(usize, bi)];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            var inst = bb.insts.items[ii];
            var kk = instSuspendKind(reg, lf, inst, actx.suspending_fns);
            if (kk != @intCast(u8, 0)) {
                var state = state_base[@intCast(usize, bi)] + s + @intCast(u32, 1);
                var sidx = @intCast(usize, state - @intCast(u32, 1));
                if (kk == @intCast(u8, 1)) {
                    saveAllFields(&b, cur, actx.layout);
                    var sv = newTemp(&b, state_type);
                    emit(&b, cur, LirInst{ .int_const = .{ .value = @intCast(u64, state), .result = sv } });
                    storeField(&b, cur, state_off, state_type, sv);
                    var yld = newTemp(&b, opt);
                    emit(&b, cur, LirInst{ .wrap_optional = .{ .value = @intCast(u32, 0), .result = yld, .type_id = opt } });
                    emit(&b, cur, LirInst{ .ret = yld });
                    step.blocks.items[@intCast(usize, cur)].is_terminated = @intCast(u8, 1);
                    s += @intCast(u32, 1);
                    cur = state_resume[sidx];
                    reloadAllFields(&b, cur, actx.layout);
                    continue;
                }
                var cd = lir_mod.lirSideGetCallDirect(lf, inst.call_direct);
                emitAwait(&b, cur, cd, state, state_alloc[sidx], state_yield[sidx], state_resume[sidx], state_after[sidx], pr_k, terminal_id);
                if (cd.return_type != type_mod.TYPE_VOID) { pr_k += @intCast(u32, 1); }
                s += @intCast(u32, 1);
                cur = state_after[sidx];
                continue;
            }
            if (b.ret_val_present) {
                var is_ret: bool = false;
                var ret_v: u32 = @intCast(u32, 0);
                switch (inst) {
                    .ret => |rv| { is_ret = true; ret_v = rv; },
                    else => {},
                }
                if (is_ret) {
                    emit(&b, cur, LirInst{ .assign = .{ .dst = b.ret_val_temp, .src = ret_v + base, .name_id = @intCast(u32, 0) } });
                    emit(&b, cur, LirInst{ .jump = b.ep_store_id });
                    step.blocks.items[@intCast(usize, cur)].is_terminated = @intCast(u8, 1);
                    continue;
                }
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

    // D3 terminal result store: shared epilogue, reached from every `.ret value`.
    if (ret_val_present) {
        if (result_present) {
            var rp = loadField(&b, ep_store_id, result_off, ptr_void);
            var rpi = newTemp(&b, type_mod.TYPE_USIZE);
            emit(&b, ep_store_id, LirInst{ .ptr_to_int = .{ .value = rp, .result = rpi } });
            var zero = newTemp(&b, type_mod.TYPE_USIZE);
            emit(&b, ep_store_id, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = zero } });
            var nz = newTemp(&b, type_mod.TYPE_U8);
            emit(&b, ep_store_id, LirInst{ .binary = .{ .op = BIN_NE, .lhs = rpi, .rhs = zero, .result = nz } });
            emit(&b, ep_store_id, LirInst{ .branch = .{ .cond = nz, .then_bb = ep_dostore_id, .else_bb = ep_ret_id } });
            step.blocks.items[@intCast(usize, ep_store_id)].is_terminated = @intCast(u8, 1);
            var pty = type_mod.typeRegistryGetOrCreatePtr(reg, lf.return_type, false);
            var p = newTemp(&b, pty);
            emit(&b, ep_dostore_id, LirInst{ .ptr_cast = .{ .value = rp, .target = pty, .result = p } });
            emit(&b, ep_dostore_id, LirInst{ .store = .{ .ptr = p, .value = b.ret_val_temp } });
            emit(&b, ep_dostore_id, LirInst{ .jump = ep_ret_id });
            step.blocks.items[@intCast(usize, ep_dostore_id)].is_terminated = @intCast(u8, 1);
        } else {
            emit(&b, ep_store_id, LirInst{ .jump = ep_ret_id });
            step.blocks.items[@intCast(usize, ep_store_id)].is_terminated = @intCast(u8, 1);
            emit(&b, ep_dostore_id, LirInst{ .jump = ep_ret_id });
            step.blocks.items[@intCast(usize, ep_dostore_id)].is_terminated = @intCast(u8, 1);
        }
        var o = newTemp(&b, opt);
        emit(&b, ep_ret_id, LirInst{ .set_optional_null = .{ .result = o, .type_id = opt } });
        emit(&b, ep_ret_id, LirInst{ .ret = o });
        step.blocks.items[@intCast(usize, ep_ret_id)].is_terminated = @intCast(u8, 1);
    }

    var slot = lir_stream.lirStreamAppend(actx.lir_stream, step);
    lir_mod.lirSlotArrayListAppend(actx.lir_slots, slot);
    // D2: root `main` also gets a minimal synchronous driver (same name_id /
    // module_id / is_pub / params) that drives this step to completion.
    if (isRootMain(actx, lf)) { emitMainDriver(actx, lf); }
    return true;
}

