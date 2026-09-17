// async_frame_layout.zig — Stage 2 LIR frame-layout reader (Track 2, Task 5c).
//
// For each suspending function this pass reads the lowered LIR and builds the
// precise frame layout: the hidden `step` word (pointer-sized, offset 0), `ctx`
// (pointer-sized), `state` (the u8/u16/u32 width P2 chose from the
// suspension-point count; read from `state_widths`), every `LirParam` in order,
// then every hoisted temp that is live across at least one suspension point, in
// temp_id (declaration) order.
//
// A suspension point is (a) a direct call to a function in `suspending_fns`
// (implicit await) or (b) the explicit `@asyncSuspend` placeholder (`int_const`
// 0 whose result temp is a `*void`). A value is live across a suspension point
// when it is defined strictly before the point AND read strictly after it; the
// suspension instruction's own operands are excluded and intervening defs do
// not stop the scan (conservative superset, no false exclusion). Reads/writes
// use the same operand scan as `lir_opt_pass`; named local storage temps are
// matched by name through `load_local` so mutable locals are accounted for.
//
// The reader asserts the precise natural-layout size is <= the authoritative
// `frame_sizes[key]` (ICE otherwise: a caller buffer must never under-size the
// frame) and pads the reported layout size up to `frame_sizes[key]`. It is a
// pure reader: it never writes `frame_sizes` and never mutates the LIR.
//
// Backend-agnostic: this module MUST NOT call any `c89_*` / emitter function.
// It only reads the type registry and the LIR, and emits one `LAYOUT:` marker.

const alloc_mod = @import("allocator.zig");
const async_analysis = @import("async_analysis.zig");
const ga_mod = @import("growable_array.zig");
const hash_mod = @import("util/hash.zig");
const itoa_mod = @import("util/itoa.zig");
const lir_mod = @import("lir.zig");
const pal = @import("pal.zig");
const type_mod = @import("type_registry.zig");

const Sand = alloc_mod.Sand;
const LirFunction = lir_mod.LirFunction;
const LirInst = lir_mod.LirInst;
const TypeRegistry = type_mod.TypeRegistry;

const INVALID: u32 = 0xFFFFFFFF;

pub const ASYNC_FIELD_CTX: u8 = 0;
pub const ASYNC_FIELD_STATE: u8 = 1;
pub const ASYNC_FIELD_PARAM: u8 = 2;
pub const ASYNC_FIELD_LIVE: u8 = 3;
pub const ASYNC_FIELD_STEP: u8 = 4;
pub const ASYNC_FIELD_CHILD: u8 = 5;
pub const ASYNC_FIELD_RESULT: u8 = 6;
pub const ASYNC_FIELD_PARENT_RESULT: u8 = 7;

pub const AsyncFrameField = struct {
    kind: u8,
    name_id: u32,
    temp_id: u32,
    type_id: u32,
    offset: u32,
    size: u32,
    alignment: u32,
};

pub const AsyncFrameFieldArrayList = struct {
    items: [*]AsyncFrameField,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub const AsyncFrameLayout = struct {
    fields: AsyncFrameFieldArrayList,
    layout_size: u32,
};

fn fieldArrayListInit(alloc: *Sand, capacity: usize) AsyncFrameFieldArrayList {
    var cap = capacity;
    if (cap == @intCast(usize, 0)) cap = @intCast(usize, 1);
    var raw = alloc_mod.sandAlloc(alloc, cap * @intCast(usize, @sizeOf(AsyncFrameField)), @intCast(usize, 4)) catch unreachable;
    return AsyncFrameFieldArrayList{
        .items = @ptrCast([*]AsyncFrameField, raw),
        .len = @intCast(usize, 0),
        .capacity = cap,
        .allocator = alloc,
    };
}

fn fieldArrayListEnsureCapacity(self: *AsyncFrameFieldArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * @intCast(usize, 2)) new_cap = self.capacity * @intCast(usize, 2);
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    var raw = alloc_mod.sandAlloc(self.allocator, new_cap * @intCast(usize, @sizeOf(AsyncFrameField)), @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]AsyncFrameField, raw);
    var i: usize = @intCast(usize, 0);
    while (i < self.len) : (i += @intCast(usize, 1)) { new_items[i] = self.items[i]; }
    self.items = new_items;
    self.capacity = new_cap;
}

fn fieldArrayListAppend(self: *AsyncFrameFieldArrayList, value: AsyncFrameField) void {
    fieldArrayListEnsureCapacity(self, self.len + @intCast(usize, 1));
    self.items[self.len] = value;
    self.len += @intCast(usize, 1);
}

const Scan = struct {
    lir_fn: *LirFunction,
    reg: *TypeRegistry,
    max_temp: u32,
    ttype: [*]u32,
    // local name_id -> storage temp_id (decl_local + params; later decls win).
    locals: *hash_mod.U32ToU32Map,
    // Task 2b-F (#9): CFG-aware live-across scratch. `visited` (one byte per
    // block) and `work` (a successor worklist, capacity >= total CFG edges) are
    // allocated once by `asyncLayoutFrame` and reused by `hasReadAfter`.
    alloc: *Sand,
    nblocks: u32,
    visited: [*]u8,
    work: [*]u32,
};

fn allocU32With(alloc: *Sand, n: u32, fill: u32) [*]u32 {
    var count = n;
    if (count == @intCast(u32, 0)) count = @intCast(u32, 1);
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, count) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable;
    var a = @ptrCast([*]u32, raw);
    var i: u32 = @intCast(u32, 0);
    while (i < count) : (i += @intCast(u32, 1)) { a[@intCast(usize, i)] = fill; }
    return a;
}

fn allocU8Raw(alloc: *Sand, n: u32) [*]u8 {
    var count = n;
    if (count == @intCast(u32, 0)) count = @intCast(u32, 1);
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, count) * @intCast(usize, @sizeOf(u8)), @intCast(usize, 1)) catch unreachable;
    return @ptrCast([*]u8, raw);
}

fn allocU8With(alloc: *Sand, n: u32, fill: u8) [*]u8 {
    var count = n;
    if (count == @intCast(u32, 0)) count = @intCast(u32, 1);
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, count) * @intCast(usize, @sizeOf(u8)), @intCast(usize, 1)) catch unreachable;
    var a = @ptrCast([*]u8, raw);
    var i: u32 = @intCast(u32, 0);
    while (i < count) : (i += @intCast(u32, 1)) { a[@intCast(usize, i)] = fill; }
    return a;
}

fn maxTempOf(lir_fn: *LirFunction) u32 {
    var m: u32 = @intCast(u32, 0);
    var i: usize = @intCast(usize, 0);
    while (i < lir_fn.hoisted_temps.len) : (i += @intCast(usize, 1)) {
        var td = lir_fn.hoisted_temps.items[i];
        if (td.temp_id >= m) { m = td.temp_id + @intCast(u32, 1); }
    }
    return m;
}

// Def write-target of an inst (mirrors lir_opt_pass.defResultTemp).
fn defResultTemp(c: *Scan, inst: LirInst) u32 {
    switch (inst) {
        .binary => |b| { return b.result; },
        .unary => |u| { return u.result; },
        .int_const => |ic| { return ic.result; },
        .float_const => |fc| { return fc.result; },
        .string_const => |sc| { return sc.result; },
        .null_const => |nc| { return nc.result; },
        .set_optional_null => |sn| { return sn.result; },
        .bool_const => |bc| { return bc.result; },
        .undefined_const => |uc| { return uc.result; },
        .poison_init => |pi| { return pi.result; },
        .enum_const => |ec| { return ec.result; },
        .int_cast => |ic| { return ic.result; },
        .int_cast_checked => |ic| { return ic.result; },
        .width_wrap => |ww| { return ww.result; },
        .float_cast => |fc| { return fc.result; },
        .ptr_cast => |pc| { return pc.result; },
        .int_to_float => |itf| { return itf.result; },
        .int_to_ptr => |itp| { return itp.result; },
        .ptr_to_int => |pti| { return pti.result; },
        .make_slice => |ms| { return ms.result; },
        .addr_of => |a| { return a.result; },
        .addr_of_field => |a| { return a.result; },
        .func_ref => |fr| { return fr.result; },
        .wrap_optional => |w| { return w.result; },
        .wrap_error_ok => |w| { return w.result; },
        .wrap_error_err => |w| { return w.result; },
        .unwrap_optional => |u| { return u.result; },
        .unwrap_optional_checked => |u| { return u.result; },
        .unwrap_optional_abi => |u| { return u.result; },
        .check_optional => |ch| { return ch.result; },
        .unwrap_error_payload => |u| { return u.result; },
        .unwrap_error_code => |u| { return u.result; },
        .check_error => |ch| { return ch.result; },
        .load => |l| { return l.result; },
        .load_field => |lf| { return lf.result; },
        .load_bitfield => |lb| { return lb.result; },
        .load_index => |li| { return li.result; },
        .load_local => |ll| { return ll.result; },
        .load_global => |lg| { return lg.result; },
        .assign => |a| { return a.dst; },
        .assign_field => |a| { return a.base; },
        .assign_index => |a| { return a.base; },
        .call => |cl| { return cl.result; },
        .call_direct => |slot| {
            var cd = lir_mod.lirSideGetCallDirect(c.lir_fn, slot);
            return cd.result;
        },
        .tail_call => |slot| {
            var tc = lir_mod.lirSideGetTailCall(c.lir_fn, slot);
            return tc.result;
        },
        .va_arg => |va| { return va.result; },
        .builtin_get_char => |bgc| { return bgc.result; },
        .add_with_overflow => |o| { return o.result; },
        .sub_with_overflow => |o| { return o.result; },
        .mul_with_overflow => |o| { return o.result; },
        .shl_with_overflow => |o| { return o.result; },
        .neg_with_overflow => |o| { return o.result; },
        .overflow_flag => |o| { return o.result; },
        else => return INVALID,
    }
}

fn localStorage(c: *Scan, name_id: u32) u32 {
    if (name_id == @intCast(u32, 0)) return INVALID;
    if (hash_mod.u32ToU32MapGet(c.locals, name_id)) |t| return t;
    return INVALID;
}

// True when `v` (a storage temp) is written by `inst`.
fn instDefsTemp(c: *Scan, inst: LirInst, v: u32) bool {
    if (defResultTemp(c, inst) == v) return true;
    switch (inst) {
        .store_local => |sl| {
            if (localStorage(c, sl.name_id) == v) return true;
        },
        .store_global => {},
        else => {},
    }
    return false;
}

// True when `v` (a storage temp) is read by `inst`.
fn instReadsTemp(c: *Scan, inst: LirInst, v: u32) bool {
    switch (inst) {
        .assign => |a| { if (a.src == v) return true; },
        .assign_field => |a| {
            if (a.base == v or a.src == v) return true;
        },
        .assign_index => |a| {
            if (a.base == v or a.index == v or a.src == v) return true;
        },
        .branch => |b| { if (b.cond == v) return true; },
        .switch_br => |s| { if (s.cond == v) return true; },
        .ret => |r| { if (r == v) return true; },
        .binary => |b| {
            if (b.lhs == v or b.rhs == v) return true;
        },
        .unary => |u| { if (u.operand == v) return true; },
        .add_with_overflow => |o| { if (o.lhs == v or o.rhs == v) return true; },
        .sub_with_overflow => |o| { if (o.lhs == v or o.rhs == v) return true; },
        .mul_with_overflow => |o| { if (o.lhs == v or o.rhs == v) return true; },
        .shl_with_overflow => |o| { if (o.lhs == v or o.rhs == v) return true; },
        .neg_with_overflow => |o| { if (o.value == v) return true; },
        .overflow_flag => |o| { if (o.lhs == v or o.rhs == v) return true; },
        .call => |cl| {
            if (cl.callee == v) return true;
            if (v >= cl.args_start and v < cl.args_start + cl.args_count) return true;
        },
        .load_field => |lf| { if (lf.base == v) return true; },
        .load_bitfield => |lb| { if (lb.base == v) return true; },
        .store_field => |sf| {
            if (sf.base == v or sf.value == v) return true;
        },
        .store_bitfield => |sb| {
            if (sb.base == v or sb.value == v) return true;
        },
        .load_index => |li| {
            if (li.base == v or li.index == v) return true;
        },
        .load => |l| { if (l.ptr == v) return true; },
        .store => |st| {
            if (st.ptr == v or st.value == v) return true;
        },
        .addr_of => |a| { if (a.operand == v) return true; },
        .addr_of_field => |a| { if (a.base == v) return true; },
        .wrap_optional => |w| { if (w.value == v) return true; },
        .call_direct => |slot| {
            var cd = lir_mod.lirSideGetCallDirect(c.lir_fn, slot);
            if (v >= cd.args_start and v < cd.args_start + cd.args_count) return true;
        },
        .va_start => |vs| {
            if (vs.va_list_temp == v or vs.last_param_temp == v) return true;
        },
        .va_arg => |va| { if (va.va_list_temp == v) return true; },
        .va_end => |ve| { if (ve.va_list_temp == v) return true; },
        .tail_call => |slot| {
            var tc = lir_mod.lirSideGetTailCall(c.lir_fn, slot);
            if (tc.is_indirect != @intCast(u8, 0) and tc.callee == v) return true;
            if (v >= tc.args_start and v < tc.args_start + tc.args_count) return true;
        },
        .unwrap_optional => |u| { if (u.value == v) return true; },
        .unwrap_optional_checked => |u| { if (u.value == v) return true; },
        .unwrap_optional_abi => |u| { if (u.value == v) return true; },
        .check_optional => |ch| { if (ch.value == v) return true; },
        .wrap_error_ok => |w| { if (w.value == v) return true; },
        .wrap_error_err => |w| { if (w.value == v) return true; },
        .unwrap_error_payload => |u| { if (u.value == v) return true; },
        .unwrap_error_code => |u| { if (u.value == v) return true; },
        .check_error => |ch| { if (ch.value == v) return true; },
        .make_slice => |ms| {
            if (ms.ptr == v or ms.len == v) return true;
        },
        .int_cast => |ic| { if (ic.value == v) return true; },
        .int_cast_checked => |ic| { if (ic.value == v) return true; },
        .width_wrap => |ww| { if (ww.value == v) return true; },
        .float_cast => |fc| { if (fc.value == v) return true; },
        .ptr_cast => |pc| { if (pc.value == v) return true; },
        .int_to_float => |itf| { if (itf.value == v) return true; },
        .ptr_to_int => |pti| { if (pti.value == v) return true; },
        .int_to_ptr => |itp| { if (itp.value == v) return true; },
        // A named local read: the value consumed is the local's storage temp.
        .load_local => |ll| {
            if (localStorage(c, ll.name_id) == v) return true;
        },
        .store_local => |sl| { if (sl.value == v) return true; },
        .store_global => |sg| { if (sg.value == v) return true; },
        .print_val => |pv| { if (pv.value == v) return true; },
        .builtin_put_char => |bpc| { if (bpc.value == v) return true; },
        .builtin_stdout_write => |b| {
            if (b.ptr == v or b.len == v) return true;
        },
        .builtin_stderr_write => |b| {
            if (b.ptr == v or b.len == v) return true;
        },
        .builtin_exit => |be| { if (be.value == v) return true; },
        .builtin_sleep_ms => |bsm| { if (bsm.value == v) return true; },
        .builtin_console_gotoxy => |bcg| {
            if (bcg.x == v or bcg.y == v) return true;
        },
        .builtin_console_set_color => |bcc| {
            if (bcc.fg == v or bcc.bg == v) return true;
        },
        .check_trap => |ct| { if (ct.cond == v) return true; },
        else => {},
    }
    return false;
}

// A suspension point on LIR: an implicit await (direct call to a suspending
// callee) or the explicit `@asyncSuspend` placeholder.
fn instIsSuspendPoint(c: *Scan, inst: LirInst, suspending_fns: *hash_mod.U64ToU32Map) bool {
    switch (inst) {
        .call_direct => |slot| {
            var cd = lir_mod.lirSideGetCallDirect(c.lir_fn, slot);
            return async_analysis.asyncIsSuspending(suspending_fns, cd.module_id, cd.name_id);
        },
        .int_const => |ic| {
            if (ic.value != @intCast(u64, 0)) return false;
            if (ic.result >= c.max_temp) return false;
            return async_analysis.typeIsPtrVoid(c.reg, c.ttype[@intCast(usize, ic.result)]);
        },
        else => return false,
    }
}

// True when `v` is written somewhere strictly before (sbb, sii).
fn hasDefBefore(c: *Scan, v: u32, sbb: u32, sii: u32) bool {
    var bi: usize = @intCast(usize, 0);
    while (bi < c.lir_fn.blocks.len) : (bi += @intCast(usize, 1)) {
        if (@intCast(u32, bi) > sbb) break;
        var bb = &c.lir_fn.blocks.items[bi];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            if (@intCast(u32, bi) == sbb and @intCast(u32, ii) >= sii) break;
            if (instDefsTemp(c, bb.insts.items[ii], v)) return true;
        }
    }
    return false;
}

// Task 2b-F (#9): push the CFG successors of block `b` onto the worklist at
// `sp`. Explicit terminator targets (jump/branch/switch_br) plus the implicit
// fallthrough to `b + 1` when the block is not terminated. Duplicates are
// allowed; `hasReadAfter` dedups via `visited`.
fn cfgPushSuccessors(c: *Scan, b: u32, sp: *u32) void {
    var bb = &c.lir_fn.blocks.items[@intCast(usize, b)];
    var terminated: u8 = bb.is_terminated;
    var ii: usize = @intCast(usize, 0);
    while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
        switch (bb.insts.items[ii]) {
            .jump => |jb| {
                c.work[@intCast(usize, sp.*)] = jb;
                sp.* += @intCast(u32, 1);
                terminated = @intCast(u8, 1);
            },
            .branch => |br| {
                c.work[@intCast(usize, sp.*)] = br.then_bb;
                sp.* += @intCast(u32, 1);
                c.work[@intCast(usize, sp.*)] = br.else_bb;
                sp.* += @intCast(u32, 1);
                terminated = @intCast(u8, 1);
            },
            .switch_br => |sw| {
                var si: u32 = sw.cases_start;
                var se: u32 = sw.cases_start + sw.cases_count;
                while (si < se) : (si += @intCast(u32, 1)) {
                    var sc = c.lir_fn.switch_cases.items[@intCast(usize, si)];
                    c.work[@intCast(usize, sp.*)] = sc.target_bb;
                    sp.* += @intCast(u32, 1);
                }
                c.work[@intCast(usize, sp.*)] = sw.else_bb;
                sp.* += @intCast(u32, 1);
                terminated = @intCast(u8, 1);
            },
            .ret, .ret_void, .trap => { terminated = @intCast(u8, 1); },
            else => {},
        }
    }
    if (terminated == @intCast(u8, 0)) {
        var nxt: u32 = b + @intCast(u32, 1);
        if (nxt < c.nblocks) {
            c.work[@intCast(usize, sp.*)] = nxt;
            sp.* += @intCast(u32, 1);
        }
    }
}

// True when `v` is read somewhere strictly after the suspension instruction
// (sbb, sii). The suspension instruction's own operands are excluded (so the
// argument temps of a suspending direct call are not counted as live-across),
// and intervening defs do NOT stop the scan. This yields a CONSERVATIVE
// SUPERSET: any value defined before the suspension and read afterwards is
// included even when redefined in between. Soundness (no false exclusion)
// matters more than minimality; `layout_size <= frame_sizes[key]` is the guard,
// with P2's rule (a) the authoritative bound.
//
// Task 2b-F (#9): the linear block scan (1) is preserved verbatim so the fix is
// strictly ADDITIVE (it can never narrow the previous live set). The CFG walk
// (2) then follows branch/jump/switch targets and loop back-edges, so a local
// read only on the NEXT loop iteration (e.g. a loop-carried accumulator) is
// marked live across the suspension. A block reached via a back-edge is scanned
// in full (from instruction 0); when that block is the suspension block itself,
// its suspension instruction (sii) is skipped to preserve the operand
// exclusion.
fn hasReadAfter(c: *Scan, v: u32, sbb: u32, sii: u32) bool {
    var bi: usize = @intCast(usize, sbb);
    while (bi < c.lir_fn.blocks.len) : (bi += @intCast(usize, 1)) {
        var bb = &c.lir_fn.blocks.items[bi];
        var ii: usize = @intCast(usize, 0);
        if (@intCast(u32, bi) == sbb) ii = @intCast(usize, sii) + @intCast(usize, 1);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            if (instReadsTemp(c, bb.insts.items[ii], v)) return true;
        }
    }
    var z: u32 = @intCast(u32, 0);
    while (z < c.nblocks) : (z += @intCast(u32, 1)) {
        c.visited[@intCast(usize, z)] = @intCast(u8, 0);
    }
    var sp: u32 = @intCast(u32, 0);
    cfgPushSuccessors(c, sbb, &sp);
    while (sp > @intCast(u32, 0)) {
        sp -= @intCast(u32, 1);
        var b = c.work[@intCast(usize, sp)];
        if (b >= c.nblocks) continue;
        if (c.visited[@intCast(usize, b)] != @intCast(u8, 0)) continue;
        c.visited[@intCast(usize, b)] = @intCast(u8, 1);
        var bb2 = &c.lir_fn.blocks.items[@intCast(usize, b)];
        var ii2: usize = @intCast(usize, 0);
        while (ii2 < bb2.insts.len) : (ii2 += @intCast(usize, 1)) {
            if (b == sbb and @intCast(u32, ii2) == sii) {
                // skip the suspension instruction's own operands
            } else {
                if (instReadsTemp(c, bb2.insts.items[ii2], v)) return true;
            }
        }
        cfgPushSuccessors(c, b, &sp);
    }
    return false;
}

// Fix F4 #4: the offset/align accumulation is the shared
// `async_analysis.frameFieldSizeAlign` + `async_analysis.addFrameField` rule
// (P2, P3, and `@asyncInit` lowering share one implementation). P3 additionally
// records the field, so it re-derives size/alignment for the record.
fn addField(fields: *AsyncFrameFieldArrayList, reg: *TypeRegistry, kind: u8,
    name_id: u32, temp_id: u32, type_id: u32, offset: *u32, max_align: *u32) void {
    var size: u32 = @intCast(u32, 0);
    var alignment: u32 = @intCast(u32, 0);
    async_analysis.frameFieldSizeAlign(reg, type_id, &size, &alignment);
    var at = async_analysis.addFrameField(reg, type_id, offset, max_align);
    fieldArrayListAppend(fields, AsyncFrameField{
        .kind = kind,
        .name_id = name_id,
        .temp_id = temp_id,
        .type_id = type_id,
        .offset = at,
        .size = size,
        .alignment = alignment,
    });
}

fn emitLayoutMarker(module_id: u32, name_id: u32, size: u32) void {
    var m1: []const u8 = "LAYOUT:m"; pal.markerWrite(m1);
    var b1: [12]u8 = undefined;
    var l1 = itoa_mod.itoa(module_id, b1[0..]);
    var s1: usize = @intCast(usize, 11) - @intCast(usize, @intCast(usize, l1));
    pal.markerWrite(b1[s1..@intCast(usize, 11)]);
    var m2: []const u8 = ":n"; pal.markerWrite(m2);
    var b2: [12]u8 = undefined;
    var l2 = itoa_mod.itoa(name_id, b2[0..]);
    var s2: usize = @intCast(usize, 11) - @intCast(usize, @intCast(usize, l2));
    pal.markerWrite(b2[s2..@intCast(usize, 11)]);
    var m3: []const u8 = ":s"; pal.markerWrite(m3);
    var b3: [12]u8 = undefined;
    var l3 = itoa_mod.itoa(size, b3[0..]);
    var s3: usize = @intCast(usize, 11) - @intCast(usize, @intCast(usize, l3));
    pal.markerWrite(b3[s3..@intCast(usize, 11)]);
    var m4: []const u8 = "\n"; pal.markerWrite(m4);
}

pub fn asyncLayoutFrame(alloc: *Sand, reg: *TypeRegistry, lir_fn: *LirFunction,
    suspending_fns: *hash_mod.U64ToU32Map, frame_sizes: *hash_mod.U64ToU32Map,
    state_widths: *hash_mod.U64ToU32Map,
    awaited_fns: *hash_mod.U64ToU32Map, async_hidden_fns: *hash_mod.U64ToU32Map,
    driver_targets: *hash_mod.U64ToU32Map,
    parent_result_type_list: *ga_mod.U32ArrayList, parent_result_start: *hash_mod.U64ToU32Map,
    parent_result_count: *hash_mod.U64ToU32Map) AsyncFrameLayout {
    var max_temp = maxTempOf(lir_fn);
    var fields = fieldArrayListInit(alloc, lir_fn.params.len + lir_fn.hoisted_temps.len + @intCast(usize, 2));

    var locals = hash_mod.u32ToU32MapInit(alloc);
    var nblocks: u32 = @intCast(u32, lir_fn.blocks.len);
    var visited = allocU8Raw(alloc, nblocks);
    var work = allocU32With(alloc, nblocks * @intCast(u32, 2) + @intCast(u32, lir_fn.switch_cases.len) + @intCast(u32, 4), @intCast(u32, 0));
    var c = Scan{
        .lir_fn = lir_fn,
        .reg = reg,
        .max_temp = max_temp,
        .ttype = allocU32With(alloc, max_temp, type_mod.TYPE_UNDEFINED),
        .locals = &locals,
        .alloc = alloc,
        .nblocks = nblocks,
        .visited = visited,
        .work = work,
    };
    var hti: usize = @intCast(usize, 0);
    while (hti < lir_fn.hoisted_temps.len) : (hti += @intCast(usize, 1)) {
        var td = lir_fn.hoisted_temps.items[hti];
        if (td.temp_id < max_temp) {
            c.ttype[@intCast(usize, td.temp_id)] = td.type_id;
        }
    }
    var pi: usize = @intCast(usize, 0);
    while (pi < lir_fn.params.len) : (pi += @intCast(usize, 1)) {
        var p = lir_fn.params.items[pi];
        _ = hash_mod.u32ToU32MapPut(&locals, p.name_id, p.temp_id);
    }
    var bi: usize = @intCast(usize, 0);
    while (bi < lir_fn.blocks.len) : (bi += @intCast(usize, 1)) {
        var bb = &lir_fn.blocks.items[bi];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            switch (bb.insts.items[ii]) {
                .decl_local => |dl| {
                    _ = hash_mod.u32ToU32MapPut(&locals, dl.name_id, dl.temp);
                },
                else => {},
            }
        }
    }

    var is_param = allocU8With(alloc, max_temp, @intCast(u8, 0));
    pi = @intCast(usize, 0);
    while (pi < lir_fn.params.len) : (pi += @intCast(usize, 1)) {
        var pt = lir_fn.params.items[pi].temp_id;
        if (pt < max_temp) { is_param[@intCast(usize, pt)] = @intCast(u8, 1); }
    }

    var live = allocU8Raw(alloc, max_temp);
    var t: u32 = @intCast(u32, 0);
    while (t < max_temp) : (t += @intCast(u32, 1)) {
        live[@intCast(usize, t)] = @intCast(u8, 0);
    }
    bi = @intCast(usize, 0);
    while (bi < lir_fn.blocks.len) : (bi += @intCast(usize, 1)) {
        var bb = &lir_fn.blocks.items[bi];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            var inst = bb.insts.items[ii];
            if (instIsSuspendPoint(&c, inst, suspending_fns)) {
                t = @intCast(u32, 0);
                while (t < max_temp) : (t += @intCast(u32, 1)) {
                    var tu = @intCast(usize, t);
                    if (is_param[tu] != @intCast(u8, 0)) continue;
                    if (!hasDefBefore(&c, t, @intCast(u32, bi), @intCast(u32, ii))) continue;
                    if (hasReadAfter(&c, t, @intCast(u32, bi), @intCast(u32, ii))) {
                        live[tu] = @intCast(u8, 1);
                    }
                }
            }
        }
    }

    var offset: u32 = @intCast(u32, 0);
    var max_align: u32 = @intCast(u32, 1);
    var state_type: u32 = type_mod.TYPE_U8;
    if (hash_mod.u64ToU32MapGet(state_widths, async_analysis.asyncKey(lir_fn.module_id, lir_fn.name_id))) |sw| { state_type = sw; }
    addField(&fields, reg, ASYNC_FIELD_STEP, @intCast(u32, 0), @intCast(u32, 0), type_mod.TYPE_USIZE, &offset, &max_align);
    addField(&fields, reg, ASYNC_FIELD_CTX, @intCast(u32, 0), @intCast(u32, 0), type_mod.TYPE_USIZE, &offset, &max_align);
    addField(&fields, reg, ASYNC_FIELD_STATE, @intCast(u32, 0), @intCast(u32, 0), state_type, &offset, &max_align);
    pi = @intCast(usize, 0);
    while (pi < lir_fn.params.len) : (pi += @intCast(usize, 1)) {
        var p = lir_fn.params.items[pi];
        addField(&fields, reg, ASYNC_FIELD_PARAM, p.name_id, p.temp_id, p.type_id, &offset, &max_align);
    }
    t = @intCast(u32, 0);
    while (t < max_temp) : (t += @intCast(u32, 1)) {
        var tu = @intCast(usize, t);
        if (live[tu] != @intCast(u8, 0) and is_param[tu] == @intCast(u8, 0)) {
            addField(&fields, reg, ASYNC_FIELD_LIVE, @intCast(u32, 0), t, c.ttype[tu], &offset, &max_align);
        }
    }
    // Amendment 9/10 hidden tail fields: child (kind 5), result (kind 6),
    // then one parent_result (kind 7) per value-returning implicit await, in
    // program order, mirroring P2's reservation exactly.
    var hid: u32 = @intCast(u32, 0);
    var lay_key = async_analysis.asyncKey(lir_fn.module_id, lir_fn.name_id);
    if (hash_mod.u64ToU32MapGet(async_hidden_fns, lay_key)) |h| { hid = h; }
    var lay_ptr_void = type_mod.typeRegistryGetOrCreatePtr(reg, type_mod.TYPE_VOID, false);
    if ((hid & @intCast(u32, 1)) != @intCast(u32, 0)) {
        addField(&fields, reg, ASYNC_FIELD_CHILD, @intCast(u32, 0), @intCast(u32, 0), lay_ptr_void, &offset, &max_align);
    }
    if (hash_mod.u64ToU32MapGet(awaited_fns, lay_key) != null or hash_mod.u64ToU32MapGet(driver_targets, lay_key) != null) {
        addField(&fields, reg, ASYNC_FIELD_RESULT, @intCast(u32, 0), @intCast(u32, 0), lay_ptr_void, &offset, &max_align);
    }
    if ((hid & @intCast(u32, 2)) != @intCast(u32, 0)) {
        var pstart: u32 = @intCast(u32, 0);
        if (hash_mod.u64ToU32MapGet(parent_result_start, lay_key)) |ps| { pstart = ps; }
        var pcount: u32 = @intCast(u32, 0);
        if (hash_mod.u64ToU32MapGet(parent_result_count, lay_key)) |pc| { pcount = pc; }
        var pk: u32 = @intCast(u32, 0);
        while (pk < pcount) : (pk += @intCast(u32, 1)) {
            var prt = parent_result_type_list.items[@intCast(usize, pstart + pk)];
            addField(&fields, reg, ASYNC_FIELD_PARENT_RESULT, @intCast(u32, 0), @intCast(u32, 0), prt, &offset, &max_align);
        }
    }
    var precise = async_analysis.alignUpU32(offset, max_align);
    if (precise == @intCast(u32, 0)) precise = @intCast(u32, 1);
    // Rule A (cross-track ABI): mirror P2's 8-byte frame padding so the
    // `precise <= frame_sizes[key]` guard and the reported layout size stay
    // consistent with the authoritative, now-8-aligned frame size.
    precise = async_analysis.alignUpU32(precise, @intCast(u32, 8));

    var frame_size = async_analysis.asyncFrameSizeOf(frame_sizes, lir_fn.module_id, lir_fn.name_id);
    var padded = precise;
    if (frame_size) |fs| {
        if (precise > fs) {
            @panic("async frame layout exceeds authoritative frame size");
        }
        padded = fs;
    } else {
        @panic("async frame layout: missing authoritative frame size");
    }
    emitLayoutMarker(lir_fn.module_id, lir_fn.name_id, padded);
    return AsyncFrameLayout{ .fields = fields, .layout_size = padded };
}

// Per-`asyncKey` `AsyncFrameLayout` side table (Amendment 9 phase A). Layouts
// are published for every suspending function before any `asyncTransform`, so a
// caller declared before its callee can still read the callee's offsets. The
// layout value is copied into persistent storage and addressed by integer.
pub fn asyncLayoutPublish(alloc: *Sand, map: *hash_mod.U64ToU32Map, module_id: u32, name_id: u32, layout: AsyncFrameLayout) void {
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, @sizeOf(AsyncFrameLayout)), @intCast(usize, 4)) catch unreachable;
    var p = @ptrCast(*AsyncFrameLayout, raw);
    p.* = layout;
    _ = hash_mod.u64ToU32MapPut(map, async_analysis.asyncKey(module_id, name_id), @intCast(u32, @ptrToInt(p)));
}

pub fn asyncLayoutLookup(map: *hash_mod.U64ToU32Map, module_id: u32, name_id: u32) ?*const AsyncFrameLayout {
    if (hash_mod.u64ToU32MapGet(map, async_analysis.asyncKey(module_id, name_id))) |v| {
        return @intToPtr(*const AsyncFrameLayout, @intCast(usize, v));
    }
    return null;
}
