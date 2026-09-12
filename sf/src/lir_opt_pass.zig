// LIR optimization pass — copy propagation + local constant folding.
//
// Runs per function in the emission phase, immediately after spill reload
// (faultIn) and before the emitter walks the function (c89_emit.zig
// emitModule / emitModuleFile drivers). It rewrites the in-memory LirFunction
// in place, deterministically. Dead-temp deletion is NOT re-implemented here:
// the existing emission-side DCE (c89_emit.zig emitHoistedDecls) already
// removes unused temps — this module only makes copies and constant ops
// disappear so the DCE has less to keep.
//
// Pass set (Task 3 scope; expression nesting is Task 4):
//   1. Copy propagation  — an `assign` copy (`dst = src;`, name_id == 0, plain
//      zT temps, identical scalar types) whose dst is read exactly once at an
//      explicit operand slot in the same basic block after the copy, whose src
//      is single-use and defined by a PURE op, and neither temp is
//      address-taken / param / decl_local-bound / load_global-aliased, is
//      replaced by renaming the consumer's dst -> src and tombstoning the copy
//      with `.nop`. Call/`call_direct`/`tail_call` ARGUMENT runs and
//      side-table operands cannot be rewritten per-slot in this IR (the arg
//      ids are a contiguous temp-id run owned by the call), so arg-temp
//      consumers are excluded — this includes an indirect tail_call's callee
//      temp, which is read once from the side table at emission like an
//      arg-slot consumer (direct tail_call/call_direct callees are name_ids,
//      not temps).
//      The args-run exclusion is the whole reason the call-argument fill
//      copies survive into the emitted C (EMITCOMPACT Part-2 census). Those
//      fills are coalesced by re-targeting the arg's PURE single-use producer
//      to WRITE the slot id directly (rename producer result -> slot) and
//      tombstoning the fill — no args-run rewrite is needed. `coalesceArgCopies`
//      applies the same gate as copy-prop (identical TypeId, both single-use,
//      pure / not-addr-taken producer, scalar/pointer trivial move) plus a
//      same-block producer < copy < call-reader window; anything failing stays
//      materialized (type boundary).
//      JOIN/merge results (EMITCOMPACT Part 2, case 2) survive copy-prop for the
//      mirror reason: an if-expr/switch/orelse/catch join temp is filled once per
//      surviving ARM (wc >= 2 across arms, or wc == 1 when a sibling arm
//      terminates early) and read POST-merge in a block different from the fill,
//      which copy-prop's same-block-read rule refuses. `coalesceJoinCopies`
//      collapses each arm the same way per arm — re-target the arm's PURE
//      single-use producer result -> the join temp id and tombstone that arm's
//      fill (the join temp stays; the per-arm intermediate disappears) — under
//      the identical gate plus a same-block producer < fill window and a
//      "clean merge arm" shape test (fill is the only def of the join temp in
//      its block and the temp's single read is in a different block).
//      EMITCOMPACT Part-2 close (Task 5): case 1 + case 2 jointly exhaust the
//      §4.1-coalescible straight-copy inventory on the current tree. The union
//      scope of case 2 (not restricted to genuine wc[dst] >= 2 multi-arm joins)
//      is accepted and documented: it soundly pre-absorbed the census's
//      storecons/exprcons/single-def-branchret residue (branchret-class removed
//      1,191 == the census's eligible proxy exactly; other-class removed 376).
//      Measured on the post-case-2 tree: every surviving `zT = zT` copy fails a
//      real gate test (args-run rar; name/ex-bound dst; src multi-writer
//      merge-snapshot chains — nested joins snapshotted into a shared temp;
//      unresolved `integer_literal_type` join carriers refused by
//      copyScalarKindOk — e.g. `x = if (cond) 1 else 0` under a coercion whose
//      if-expr result never resolved to a concrete integer type; impure or
//      multi-read), and ZERO copies pass the full gate yet remain uncoalesced
//      (instrumented refusal census: zero gate-passed-but-stranded copies; the
//      TRF/TRB/TPB/TDD/TTM tags were instrumentation-only and are not defined
//      in-tree). Loop/iterator back-edge copies,
//      tail-call self-param re-entry copies and decl-init copies remain KEEP by
//      construction (multi-read dst rc > 1 / name_id != 0).
//   2. Local constant folding — PURE binary/unary ops whose value operands are
//      all int_const (same concrete integer type as the result) fold to one
//      int_const at the result type's width with two's-complement semantics;
//      comparisons fold to 0/1. Lossless only: division/mod restricted to
//      unsigned, shifts to unsigned with in-range counts, signed overflow
//      follows the same low-width bits the emitted C produces under the
//      two's-complement carrier semantics the emitter already relies on.
//      Checked int_cast folds are skipped; `int_cast` folds only when the
//      value is exactly representable at the target.
//
// Determinism: every phase is a fixed-order traversal over the block/inst
// arrays; no pointer hashing, no unordered iteration, no environment
// dependence; per-function scratch is allocated from the caller's sand (reset
// per function by the emission driver). Identical input LIR -> identical
// output LIR.

const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const TypeKind = @import("type_registry.zig").TypeKind;
const type_mod = @import("type_registry.zig");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const lir_mod = @import("lir.zig");
const LirInst = @import("lir.zig").LirInst;
const LirFunction = @import("lir.zig").LirFunction;

const INVALID: u32 = 0xFFFFFFFF;

pub const kCopyPropMaxIter = @intCast(u32, 128);

// C90 expression-nesting cap. The PASS never enforces it (backend-agnostic
// boundary): depth is recorded unboundedly. The EMITTER (T4b+) enforces it when
// it decides which candidate temps to inline. Named here per the Task-2 design
// so both sides share one constant.
pub const kEmitNestDepthCap: u32 = 32;

// ----- T4b: active-function nest metadata publication -----
//
// lirOptRun allocates its per-temp arrays from the caller's per-function sand,
// which stays live from pass-end until the emission driver's next sandReset
// (start of the next function). T4b makes the metadata of the function being
// emitted queryable by the emitter during that window: lirOptRun records the
// final arrays in these module-level rows, and the exported lirOptNest*()
// accessors read them. Invalidation: lirOptRun clears g_nest_active at its
// entry (before any early return), so a function that never runs the pass (or
// is skipped) can never observe a previous function's rows. Emission is
// single-threaded and serialized per function, so a single active row is safe.

var g_nest_active: u8 = 0;
var g_nest_max: u32 = 0;
var g_nest_cand: [*]u8 = undefined;
var g_nest_depth: [*]u8 = undefined;
var g_nest_dfbb: [*]u32 = undefined;
var g_nest_dfii: [*]u32 = undefined;
var g_nest_rdbb: [*]u32 = undefined;
var g_nest_rdii: [*]u32 = undefined;

pub fn lirOptNestActive() u8 {
    return g_nest_active;
}

fn nestInRange(t: u32) u8 {
    if (g_nest_active == @intCast(u8, 0)) return @intCast(u8, 0);
    if (t >= g_nest_max) return @intCast(u8, 0);
    return @intCast(u8, 1);
}

pub fn lirOptNestCandidate(t: u32) u8 {
    if (nestInRange(t) == @intCast(u8, 0)) return @intCast(u8, 0);
    return g_nest_cand[@intCast(usize, t)];
}

pub fn lirOptNestDepthOf(t: u32) u8 {
    if (nestInRange(t) == @intCast(u8, 0)) return @intCast(u8, 0);
    return g_nest_depth[@intCast(usize, t)];
}

// Def inst location of temp t (df locators, valid for candidates). Non-valid
// temps get INVALID/INVALID (safe default - never stale rows).
pub fn lirOptNestDefLoc(t: u32, out_bb: *u32, out_ii: *u32) void {
    if (nestInRange(t) == @intCast(u8, 0)) {
        out_bb.* = INVALID;
        out_ii.* = INVALID;
        return;
    }
    out_bb.* = g_nest_dfbb[@intCast(usize, t)];
    out_ii.* = g_nest_dfii[@intCast(usize, t)];
}

// Single-read location of temp t (first-read locators). Non-valid temps get
// INVALID/INVALID.
pub fn lirOptNestConsLoc(t: u32, out_bb: *u32, out_ii: *u32) void {
    if (nestInRange(t) == @intCast(u8, 0)) {
        out_bb.* = INVALID;
        out_ii.* = INVALID;
        return;
    }
    out_bb.* = g_nest_rdbb[@intCast(usize, t)];
    out_ii.* = g_nest_rdii[@intCast(usize, t)];
}

const Ctx = struct {
    alloc: *Sand,
    reg: *TypeRegistry,
    lir_fn: *LirFunction,
    max_temp: u32,
    t2p: [*]u32,
    ttype: [*]u32,
    rc: [*]u32,
    wc: [*]u32,
    at: [*]u8,
    ex: [*]u8,
    dp: [*]u8,
    rd_bb: [*]u32,
    rd_ii: [*]u32,
    rar: [*]u8,
    cf: [*]u8,
    cv: [*]u64,
    ren: [*]u32,
    cand: [*]u8,
    depth: [*]u8,
    ga: [*]u8,
    gam: [*]u8,
    df_bb: [*]u32,
    df_ii: [*]u32,
};

fn lowMask(w: u32) u64 {
    if (w >= @intCast(u32, 64)) return @intCast(u64, 0) - @intCast(u64, 1);
    return (@intCast(u64, 1) << @intCast(u64, w)) - @intCast(u64, 1);
}

fn sigBit(w: u32) u64 {
    return @intCast(u64, 1) << @intCast(u64, w - @intCast(u32, 1));
}

// Integer kind classification for the scalar-int folds. Returns the width in
// bits for concrete i/u/N types (0 = not a foldable integer kind).
fn intKindWidth(kind: TypeKind) u32 {
    if (kind == TypeKind.i8_type or kind == TypeKind.u8_type) return @intCast(u32, 8);
    if (kind == TypeKind.i16_type or kind == TypeKind.u16_type) return @intCast(u32, 16);
    if (kind == TypeKind.i32_type or kind == TypeKind.u32_type or kind == TypeKind.isize_type or kind == TypeKind.usize_type) return @intCast(u32, 32);
    if (kind == TypeKind.i64_type or kind == TypeKind.u64_type) return @intCast(u32, 64);
    return @intCast(u32, 0);
}

fn intKindSigned(kind: TypeKind) u8 {
    if (kind == TypeKind.i8_type or kind == TypeKind.i16_type or kind == TypeKind.i32_type or kind == TypeKind.i64_type or kind == TypeKind.isize_type) return @intCast(u8, 1);
    return @intCast(u8, 0);
}

// Copy-prop scalar type test: both operands must share one declared C type
// that is a scalar/pointer C value (a plain `dst = src;` assignment, no array
// element loop, no injected (T*) cast, no aggregate/slice/optional/array).
fn copyScalarKindOk(kind: TypeKind) u8 {
    if (kind == TypeKind.i8_type) return 1;
    if (kind == TypeKind.i16_type) return 1;
    if (kind == TypeKind.i32_type) return 1;
    if (kind == TypeKind.i64_type) return 1;
    if (kind == TypeKind.u8_type) return 1;
    if (kind == TypeKind.u16_type) return 1;
    if (kind == TypeKind.u32_type) return 1;
    if (kind == TypeKind.u64_type) return 1;
    if (kind == TypeKind.isize_type) return 1;
    if (kind == TypeKind.usize_type) return 1;
    if (kind == TypeKind.c_char_type) return 1;
    if (kind == TypeKind.bool_type) return 1;
    if (kind == TypeKind.f32_type) return 1;
    if (kind == TypeKind.f64_type) return 1;
    if (kind == TypeKind.ptr_type) return 1;
    if (kind == TypeKind.many_ptr_type) return 1;
    if (kind == TypeKind.enum_type) return 1;
    if (kind == TypeKind.error_set_type) return 1;
    if (kind == TypeKind.fn_type) return 1;
    if (kind == TypeKind.arb_uint_type) return 1;
    if (kind == TypeKind.arb_int_type) return 1;
    if (kind == TypeKind.null_type) return 1;
    return 0;
}

fn allocU32(c: *Ctx, n: u32) [*]u32 {
    var raw = alloc_mod.sandAlloc(c.alloc, @intCast(usize, n) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable;
    return @ptrCast([*]u32, raw);
}

fn allocU64(c: *Ctx, n: u32) [*]u64 {
    var raw = alloc_mod.sandAlloc(c.alloc, @intCast(usize, n) * @intCast(usize, @sizeOf(u64)), @intCast(usize, 4)) catch unreachable;
    return @ptrCast([*]u64, raw);
}

fn allocU8(c: *Ctx, n: u32) [*]u8 {
    var raw = alloc_mod.sandAlloc(c.alloc, @intCast(usize, n) * @intCast(usize, @sizeOf(u8)), @intCast(usize, 1)) catch unreachable;
    return @ptrCast([*]u8, raw);
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

// Reset per-temp counters (rc/wc/at/ex/dp/rd_bb/rd_ii/rar/cf) and the rename map.
fn resetScratch(c: *Ctx) void {
    var t: u32 = @intCast(u32, 0);
    while (t < c.max_temp) : (t += @intCast(u32, 1)) {
        c.rc[@intCast(usize, t)] = @intCast(u32, 0);
        c.wc[@intCast(usize, t)] = @intCast(u32, 0);
        c.at[@intCast(usize, t)] = @intCast(u8, 0);
        c.ex[@intCast(usize, t)] = @intCast(u8, 0);
        c.dp[@intCast(usize, t)] = @intCast(u8, 0);
        c.rd_bb[@intCast(usize, t)] = @intCast(u32, 0);
        c.rd_ii[@intCast(usize, t)] = @intCast(u32, 0);
        c.rar[@intCast(usize, t)] = @intCast(u8, 0);
        c.cf[@intCast(usize, t)] = @intCast(u8, 0);
        c.cv[@intCast(usize, t)] = @intCast(u64, 0);
        c.ren[@intCast(usize, t)] = INVALID;
        c.cand[@intCast(usize, t)] = @intCast(u8, 0);
        c.depth[@intCast(usize, t)] = @intCast(u8, 0);
        c.ga[@intCast(usize, t)] = @intCast(u8, 0);
        c.gam[@intCast(usize, t)] = @intCast(u8, 0);
        c.df_bb[@intCast(usize, t)] = INVALID;
        c.df_ii[@intCast(usize, t)] = INVALID;
    }
}

fn markRead(c: *Ctx, t: u32, bb_idx: u32, ii: u32) void {
    if (t >= c.max_temp) return;
    var p = c.t2p[@intCast(usize, t)];
    if (p == INVALID) return;
    var pos: usize = @intCast(usize, p);
    if (c.rc[pos] == @intCast(u32, 0)) {
        c.rd_bb[pos] = bb_idx;
        c.rd_ii[pos] = ii;
    }
    c.rc[pos] += @intCast(u32, 1);
}

fn markArgRead(c: *Ctx, t: u32, bb_idx: u32, ii: u32) void {
    if (t >= c.max_temp) return;
    var p = c.t2p[@intCast(usize, t)];
    if (p == INVALID) return;
    var pos: usize = @intCast(usize, p);
    c.rar[pos] = @intCast(u8, 1);
    if (c.rc[pos] == @intCast(u32, 0)) {
        c.rd_bb[pos] = bb_idx;
        c.rd_ii[pos] = ii;
    }
    c.rc[pos] += @intCast(u32, 1);
}

fn markAddrTaken(c: *Ctx, t: u32) void {
    if (t >= c.max_temp) return;
    var p = c.t2p[@intCast(usize, t)];
    if (p == INVALID) return;
    c.at[@intCast(usize, p)] = @intCast(u8, 1);
}

fn markExcluded(c: *Ctx, t: u32) void {
    if (t >= c.max_temp) return;
    var p = c.t2p[@intCast(usize, t)];
    if (p == INVALID) return;
    c.ex[@intCast(usize, p)] = @intCast(u8, 1);
}

// [T4d-FIX, AMENDMENT 3] Records a load_global-ALIAS operand source: a temp
// whose defining inst kind is `load_global`. Such a temp is aliased by the
// emitter to the LIVE global symbol (no snapshot statement), so a register/
// const-only PURE def that reads it and is inlined re-renders the global read
// at the consumer slot - see `tempReachesGlobalAlias`/pass 1b.
fn markGaSource(c: *Ctx, t: u32) void {
    if (t >= c.max_temp) return;
    var p = c.t2p[@intCast(usize, t)];
    if (p == INVALID) return;
    c.ga[@intCast(usize, p)] = @intCast(u8, 1);
}

fn recordConst(c: *Ctx, t: u32, v: u64) void {
    if (t >= c.max_temp) return;
    var p = c.t2p[@intCast(usize, t)];
    if (p == INVALID) return;
    c.cf[@intCast(usize, p)] = @intCast(u8, 1);
    c.cv[@intCast(usize, p)] = v;
}

fn markDef(c: *Ctx, t: u32, is_pure: u8) void {
    if (t >= c.max_temp) return;
    var p = c.t2p[@intCast(usize, t)];
    if (p == INVALID) return;
    c.wc[@intCast(usize, p)] += @intCast(u32, 1);
    if (is_pure != @intCast(u8, 0)) {
        c.dp[@intCast(usize, p)] = @intCast(u8, 1);
    }
}

// Pure-result tag table (spec §3.2 AMENDMENT-1 verbatim list + the 5 gap
// resolutions). Only the *class* is tested here (used for copy-prop source
// stability); the C-shape (h) exclusions govern Task-4 nesting, not renames.
fn defInfoPure(inst: LirInst) u8 {
    switch (inst) {
        .binary => return @intCast(u8, 1),
        .unary => return @intCast(u8, 1),
        .int_const => return @intCast(u8, 1),
        .float_const => return @intCast(u8, 1),
        .bool_const => return @intCast(u8, 1),
        .null_const => return @intCast(u8, 1),
        .string_const => return @intCast(u8, 1),
        .undefined_const => return @intCast(u8, 1),
        .enum_const => return @intCast(u8, 1),
        .set_optional_null => return @intCast(u8, 1),
        .int_cast => return @intCast(u8, 1),
        .float_cast => return @intCast(u8, 1),
        .ptr_cast => return @intCast(u8, 1),
        .int_to_float => return @intCast(u8, 1),
        .int_to_ptr => return @intCast(u8, 1),
        .ptr_to_int => return @intCast(u8, 1),
        .make_slice => return @intCast(u8, 1),
        .addr_of => return @intCast(u8, 1),
        .addr_of_field => return @intCast(u8, 1),
        .func_ref => return @intCast(u8, 1),
        .wrap_optional => return @intCast(u8, 1),
        .wrap_error_ok => return @intCast(u8, 1),
        .wrap_error_err => return @intCast(u8, 1),
        .unwrap_optional => return @intCast(u8, 1),
        .unwrap_optional_checked => return @intCast(u8, 1),
        .unwrap_optional_abi => return @intCast(u8, 1),
        .check_optional => return @intCast(u8, 1),
        .unwrap_error_payload => return @intCast(u8, 1),
        .unwrap_error_code => return @intCast(u8, 1),
        .check_error => return @intCast(u8, 1),
        .load => return @intCast(u8, 1),
        .load_field => return @intCast(u8, 1),
        .load_bitfield => return @intCast(u8, 1),
        .load_index => return @intCast(u8, 1),
        .load_local => return @intCast(u8, 1),
        .load_global => return @intCast(u8, 1),
        .add_with_overflow => return @intCast(u8, 1),
        .sub_with_overflow => return @intCast(u8, 1),
        .mul_with_overflow => return @intCast(u8, 1),
        .shl_with_overflow => return @intCast(u8, 1),
        .neg_with_overflow => return @intCast(u8, 1),
        .overflow_flag => return @intCast(u8, 1),
        else => return @intCast(u8, 0),
    }
}

// Def write-target of an inst (mirrors the emitter's dceResultPos write set).
fn defResultTemp(inst: LirInst, lir_fn: *LirFunction) u32 {
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
            var cd = lir_mod.lirSideGetCallDirect(lir_fn, slot);
            return cd.result;
        },
        .tail_call => |slot| {
            var tc = lir_mod.lirSideGetTailCall(lir_fn, slot);
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

// Analysis scan: operand reads (+ first-read loc / arg-run-exclusive flags),
// def writes + purity, addr-taken / exclusion / const-value records, and def
// locators (df_bb/df_ii = last write position, used by the arg-slot
// coalescer). computeNestMetadata recomputes the locators identically on the
// final LIR; recording them here just makes them available to every phase.
fn scanInst(c: *Ctx, inst: LirInst, bb_idx: u32, ii: u32) void {
    var rp = defResultTemp(inst, c.lir_fn);
    if (rp != INVALID) {
        if (rp < c.max_temp) {
            c.df_bb[@intCast(usize, rp)] = bb_idx;
            c.df_ii[@intCast(usize, rp)] = ii;
        }
        markDef(c, rp, defInfoPure(inst));
    }
    switch (inst) {
        .assign => |a| {
            markRead(c, a.src, bb_idx, ii);
            if (a.name_id != @intCast(u32, 0)) { markExcluded(c, a.dst); }
        },
        .assign_field => |a| {
            markRead(c, a.base, bb_idx, ii);
            markRead(c, a.src, bb_idx, ii);
        },
        .assign_index => |a| {
            markRead(c, a.base, bb_idx, ii);
            markRead(c, a.index, bb_idx, ii);
            markRead(c, a.src, bb_idx, ii);
        },
        .branch => |b| { markRead(c, b.cond, bb_idx, ii); },
        .switch_br => |s| { markRead(c, s.cond, bb_idx, ii); },
        .ret => |v| { markRead(c, v, bb_idx, ii); },
        .binary => |b| {
            markRead(c, b.lhs, bb_idx, ii);
            markRead(c, b.rhs, bb_idx, ii);
        },
        .unary => |u| { markRead(c, u.operand, bb_idx, ii); },
        .add_with_overflow => |o| { markRead(c, o.lhs, bb_idx, ii); markRead(c, o.rhs, bb_idx, ii); },
        .sub_with_overflow => |o| { markRead(c, o.lhs, bb_idx, ii); markRead(c, o.rhs, bb_idx, ii); },
        .mul_with_overflow => |o| { markRead(c, o.lhs, bb_idx, ii); markRead(c, o.rhs, bb_idx, ii); },
        .shl_with_overflow => |o| { markRead(c, o.lhs, bb_idx, ii); markRead(c, o.rhs, bb_idx, ii); },
        .neg_with_overflow => |o| { markRead(c, o.value, bb_idx, ii); },
        .overflow_flag => |o| { markRead(c, o.lhs, bb_idx, ii); markRead(c, o.rhs, bb_idx, ii); },
        .call => |cl| {
            markRead(c, cl.callee, bb_idx, ii);
            var ai: u32 = @intCast(u32, 0);
            while (ai < cl.args_count) : (ai += @intCast(u32, 1)) {
                markArgRead(c, cl.args_start + ai, bb_idx, ii);
            }
        },
        .load_field => |lf| { markRead(c, lf.base, bb_idx, ii); },
        .load_bitfield => |lb| { markRead(c, lb.base, bb_idx, ii); },
        .store_field => |sf| {
            markRead(c, sf.base, bb_idx, ii);
            markRead(c, sf.value, bb_idx, ii);
        },
        .store_bitfield => |sb| {
            markRead(c, sb.base, bb_idx, ii);
            markRead(c, sb.value, bb_idx, ii);
        },
        .load_index => |li| {
            markRead(c, li.base, bb_idx, ii);
            markRead(c, li.index, bb_idx, ii);
        },
        .load => |l| { markRead(c, l.ptr, bb_idx, ii); },
        .store => |st| {
            markRead(c, st.ptr, bb_idx, ii);
            markRead(c, st.value, bb_idx, ii);
        },
        .addr_of => |a| {
            markRead(c, a.operand, bb_idx, ii);
            markAddrTaken(c, a.operand);
        },
        .addr_of_field => |a| {
            markRead(c, a.base, bb_idx, ii);
            markAddrTaken(c, a.base);
        },
        .wrap_optional => |w| { markRead(c, w.value, bb_idx, ii); },
        .call_direct => |slot| {
            var cd = lir_mod.lirSideGetCallDirect(c.lir_fn, slot);
            var ai: u32 = @intCast(u32, 0);
            while (ai < cd.args_count) : (ai += @intCast(u32, 1)) {
                markArgRead(c, cd.args_start + ai, bb_idx, ii);
            }
        },
        .va_start => |vs| {
            markRead(c, vs.va_list_temp, bb_idx, ii);
            markRead(c, vs.last_param_temp, bb_idx, ii);
        },
        .va_arg => |va| { markRead(c, va.va_list_temp, bb_idx, ii); },
        .va_end => |ve| { markRead(c, ve.va_list_temp, bb_idx, ii); },
        .tail_call => |slot| {
            var tc = lir_mod.lirSideGetTailCall(c.lir_fn, slot);
            // Indirect callee temp is a side-table operand (lives in
            // TailCallData, read once at emission like an arg-slot consumer)
            // and cannot be rewritten per-slot by rewriteInstOperands, so it
            // is arg-run-excluded from copy-prop eligibility (same contract as
            // the call/call_direct/tail_call ARG runs below). Direct callee is
            // a name_id, not a temp - no read to count.
            if (tc.is_indirect != @intCast(u8, 0)) { markArgRead(c, tc.callee, bb_idx, ii); }
            var ai: u32 = @intCast(u32, 0);
            while (ai < tc.args_count) : (ai += @intCast(u32, 1)) {
                markArgRead(c, tc.args_start + ai, bb_idx, ii);
            }
        },
        .unwrap_optional => |u| { markRead(c, u.value, bb_idx, ii); },
        .unwrap_optional_checked => |u| { markRead(c, u.value, bb_idx, ii); },
        .unwrap_optional_abi => |u| { markRead(c, u.value, bb_idx, ii); },
        .check_optional => |ch| { markRead(c, ch.value, bb_idx, ii); },
        .wrap_error_ok => |w| { markRead(c, w.value, bb_idx, ii); },
        .wrap_error_err => |w| { markRead(c, w.value, bb_idx, ii); },
        .unwrap_error_payload => |u| { markRead(c, u.value, bb_idx, ii); },
        .unwrap_error_code => |u| { markRead(c, u.value, bb_idx, ii); },
        .check_error => |ch| { markRead(c, ch.value, bb_idx, ii); },
        .make_slice => |ms| {
            markRead(c, ms.ptr, bb_idx, ii);
            markRead(c, ms.len, bb_idx, ii);
        },
        .int_cast => |ic| { markRead(c, ic.value, bb_idx, ii); },
        .float_cast => |fc| { markRead(c, fc.value, bb_idx, ii); },
        .ptr_cast => |pc| { markRead(c, pc.value, bb_idx, ii); },
        .int_to_float => |itf| { markRead(c, itf.value, bb_idx, ii); },
        .ptr_to_int => |pti| { markRead(c, pti.value, bb_idx, ii); },
        .int_to_ptr => |itp| { markRead(c, itp.value, bb_idx, ii); },
        .store_local => |sl| { markRead(c, sl.value, bb_idx, ii); },
        .store_global => |sg| { markRead(c, sg.value, bb_idx, ii); },
        .print_val => |pv| { markRead(c, pv.value, bb_idx, ii); },
        .builtin_put_char => |bpc| { markRead(c, bpc.value, bb_idx, ii); },
        .builtin_stdout_write => |b| {
            markRead(c, b.ptr, bb_idx, ii);
            markRead(c, b.len, bb_idx, ii);
        },
        .builtin_stderr_write => |b| {
            markRead(c, b.ptr, bb_idx, ii);
            markRead(c, b.len, bb_idx, ii);
        },
        .builtin_exit => |be| { markRead(c, be.value, bb_idx, ii); },
        .builtin_sleep_ms => |bsm| { markRead(c, bsm.value, bb_idx, ii); },
        .builtin_console_gotoxy => |bcg| {
            markRead(c, bcg.x, bb_idx, ii);
            markRead(c, bcg.y, bb_idx, ii);
        },
        .builtin_console_set_color => |bcc| {
            markRead(c, bcc.fg, bb_idx, ii);
            markRead(c, bcc.bg, bb_idx, ii);
        },
        .load_global => |lg| {
            markExcluded(c, lg.result);
            markGaSource(c, lg.result);
        },
        .decl_local => |dl| {
            markExcluded(c, dl.temp);
        },
        .int_const => |ic| {
            recordConst(c, ic.result, ic.value);
        },
        .bool_const => |bc| {
            recordConst(c, bc.result, @intCast(u64, bc.value));
        },
        .check_trap => |ct| {
            markRead(c, ct.cond, bb_idx, ii);
            if (ct.kind != @intCast(u8, 6) and ct.kind != @intCast(u8, 2)) { markRead(c, ct.aux, bb_idx, ii); }
        },
        else => {},
    }
}

fn scanAll(c: *Ctx) void {
    resetScratch(c);
    var bi: usize = @intCast(usize, 0);
    while (bi < c.lir_fn.blocks.len) : (bi += @intCast(usize, 1)) {
        var bb = &c.lir_fn.blocks.items[bi];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            scanInst(c, bb.insts.items[ii], @intCast(u32, bi), @intCast(u32, ii));
        }
    }
    var pi: usize = @intCast(usize, 0);
    while (pi < c.lir_fn.params.len) : (pi += @intCast(usize, 1)) {
        markExcluded(c, c.lir_fn.params.items[pi].temp_id);
    }
}

// ----- T4a: nest-candidate + expression-depth metadata (backend-agnostic) -----
//
// Records, per temp id, into per-function arrays (sized like the other
// per-temp arrays by maxTempOf; index = temp id):
//   * `cand` (u8) - inline candidate iff the temp's SINGLE defining inst is
//     PURE (spec §3.2 verbatim list + the 5 gap resolutions) AND the temp has
//     exactly one value use AND it is not address-taken AND it is not excluded
//     (the `ex` set: param / decl_local-bound / load_global-alias) AND rule (d)
//     [T4b-FIX, operator ruling 2026-09-08, option B]: rule (d) applies ONLY to
//     a MEMORY-READING PURE def (the load family, see `defReadsMemory`) - its
//     single consumer (first-read locator) must be in the SAME block as the def
//     with no ORDERED (side-effecting) inst strictly between the def and that
//     consumer. Register/const-only PURE defs are SSA-safe across ORDERED
//     windows and keep the T4b pre-fix nesting (no rule-d window). Requires
//     exactly one write (wc == 1) and exactly one read (rc == 1).
//   * `depth` (u8) - generic expression-tree nesting depth of the defining
//     inst: 1 + max over the inst's operand temps that are themselves
//     candidates (a non-candidate operand renders as a materialized-name leaf
//     and adds 0). Computed by recursion + memo over the single-assignment
//     def-use graph (defs dominate uses, so the recursion is acyclic) -
//     deterministic, independent of block array order.
//
// The C90 depth cap and the C-shape (h) / consumer-slot (i) predicates are the
// EMITTER's concern (T4b+); nothing here reasons about C89 emission shape, and
// in T4a nothing reads these arrays (zero emission delta by construction).

fn depthOfTemp(c: *Ctx, t: u32) u8 {
    if (t >= c.max_temp) return @intCast(u8, 0);
    var pos = c.t2p[@intCast(usize, t)];
    if (pos == INVALID) return @intCast(u8, 0);
    if (c.cand[@intCast(usize, t)] == @intCast(u8, 0)) return @intCast(u8, 0);
    var d = c.depth[@intCast(usize, t)];
    // 0xFF is the in-progress marker (== saturation value: a real chain >= 255
    // levels is beyond any C90 cap anyway). A cycle is impossible in the
    // single-assignment def-use graph, so an in-progress revisit would only
    // arise from a depth >= 255 recursion and is clamped the same way.
    if (d == @intCast(u8, 0xFF)) return @intCast(u8, 0xFF);
    if (d != @intCast(u8, 0)) return d;
    c.depth[@intCast(usize, t)] = @intCast(u8, 0xFF);
    var bi = c.df_bb[@intCast(usize, t)];
    if (bi == INVALID) {
        c.depth[@intCast(usize, t)] = @intCast(u8, 1);
        return @intCast(u8, 1);
    }
    var bb = &c.lir_fn.blocks.items[@intCast(usize, bi)];
    var inst = bb.insts.items[@intCast(usize, c.df_ii[@intCast(usize, t)])];
    var mx = maxOperandDepth(c, inst);
    var r: u32 = @intCast(u32, mx) + @intCast(u32, 1);
    if (r > @intCast(u32, 0xFF)) r = @intCast(u32, 0xFF);
    c.depth[@intCast(usize, t)] = @intCast(u8, r);
    return c.depth[@intCast(usize, t)];
}

// Max candidate-depth over the operand temps of a PURE def inst (only PURE
// defs can be candidates, so only their operand slots are enumerated).
fn maxOperandDepth(c: *Ctx, inst: LirInst) u8 {
    var mx: u8 = @intCast(u8, 0);
    switch (inst) {
        .binary => |b| {
            mx = depthOfTemp(c, b.lhs);
            var r = depthOfTemp(c, b.rhs);
            if (r > mx) mx = r;
        },
        .unary => |u| { mx = depthOfTemp(c, u.operand); },
        .add_with_overflow => |o| {
            mx = depthOfTemp(c, o.lhs);
            var r = depthOfTemp(c, o.rhs);
            if (r > mx) mx = r;
        },
        .sub_with_overflow => |o| {
            mx = depthOfTemp(c, o.lhs);
            var r = depthOfTemp(c, o.rhs);
            if (r > mx) mx = r;
        },
        .mul_with_overflow => |o| {
            mx = depthOfTemp(c, o.lhs);
            var r = depthOfTemp(c, o.rhs);
            if (r > mx) mx = r;
        },
        .shl_with_overflow => |o| {
            mx = depthOfTemp(c, o.lhs);
            var r = depthOfTemp(c, o.rhs);
            if (r > mx) mx = r;
        },
        .neg_with_overflow => |o| { mx = depthOfTemp(c, o.value); },
        .overflow_flag => |o| {
            mx = depthOfTemp(c, o.lhs);
            var r = depthOfTemp(c, o.rhs);
            if (r > mx) mx = r;
        },
        .int_cast => |ic| { mx = depthOfTemp(c, ic.value); },
        .float_cast => |fc| { mx = depthOfTemp(c, fc.value); },
        .ptr_cast => |pc| { mx = depthOfTemp(c, pc.value); },
        .int_to_float => |itf| { mx = depthOfTemp(c, itf.value); },
        .ptr_to_int => |pti| { mx = depthOfTemp(c, pti.value); },
        .int_to_ptr => |itp| { mx = depthOfTemp(c, itp.value); },
        .make_slice => |ms| {
            mx = depthOfTemp(c, ms.ptr);
            var r = depthOfTemp(c, ms.len);
            if (r > mx) mx = r;
        },
        .addr_of => |a| { mx = depthOfTemp(c, a.operand); },
        .addr_of_field => |a| { mx = depthOfTemp(c, a.base); },
        .wrap_optional => |w| { mx = depthOfTemp(c, w.value); },
        .wrap_error_ok => |w| { mx = depthOfTemp(c, w.value); },
        .wrap_error_err => |w| { mx = depthOfTemp(c, w.value); },
        .unwrap_optional => |u| { mx = depthOfTemp(c, u.value); },
        .unwrap_optional_checked => |u| { mx = depthOfTemp(c, u.value); },
        .unwrap_optional_abi => |u| { mx = depthOfTemp(c, u.value); },
        .check_optional => |ch| { mx = depthOfTemp(c, ch.value); },
        .unwrap_error_payload => |u| { mx = depthOfTemp(c, u.value); },
        .unwrap_error_code => |u| { mx = depthOfTemp(c, u.value); },
        .check_error => |ch| { mx = depthOfTemp(c, ch.value); },
        .load => |l| { mx = depthOfTemp(c, l.ptr); },
        .load_field => |lf| { mx = depthOfTemp(c, lf.base); },
        .load_bitfield => |lb| { mx = depthOfTemp(c, lb.base); },
        .load_index => |li| {
            mx = depthOfTemp(c, li.base);
            var r = depthOfTemp(c, li.index);
            if (r > mx) mx = r;
        },
        else => {},
    }
    return mx;
}

// Memory-read test for rule (d) [T4b-FIX, operator ruling 2026-09-08,
// option B]: a PURE def that needs the write-free window is one whose emitted
// rvalue READS MEMORY - the load family (load / load_field / load_bitfield /
// load_index / load_local / load_global). Inlined at a consumer past an ORDERED
// write such a def could re-read a base and observe the aliased write twice/
// stale. Register/const-only PURE defs (binary / unary / casts / consts /
// value-field picks over SSA temps / addr_of / func_ref / ...) never read a
// base, so they keep the T4b pre-fix nesting across ORDERED windows. Ambiguous
// kinds are treated conservatively as memory-reading (rule (d) applies) -
// never unsafe. (load_global results are `ex`-excluded anyway; load_local reads
// a named local that may be memory-backed.)
fn defReadsMemory(inst: LirInst) u8 {
    switch (inst) {
        .load => return @intCast(u8, 1),
        .load_field => return @intCast(u8, 1),
        .load_bitfield => return @intCast(u8, 1),
        .load_index => return @intCast(u8, 1),
        .load_local => return @intCast(u8, 1),
        .load_global => return @intCast(u8, 1),
        else => return @intCast(u8, 0),
    }
}

// ORDERED (side-effecting) inst test for rule (d). An inst is ORDERED iff it is
// NOT in the pass's PURE table (spec §3.2 authority as implemented by
// `defInfoPure`, the exact purity source already used for the per-temp `dp`
// bit). This class covers stores / store_bitfield (ORDERED-RMW) / assign &
// assign_* / call / call_direct / tail_call / print_* / builtin_* / va_* /
// ret & ret_void / control flow / decl_* housekeeping / nop - every LirInst
// kind the pass does not classify PURE. Rule (d) uses it to bound the window a
// memory-reading def (see `defReadsMemory`) may be nested across.
fn instOrdered(inst: LirInst) u8 {
    if (defInfoPure(inst) != @intCast(u8, 0)) return @intCast(u8, 0);
    return @intCast(u8, 1);
}

// [T4d-FIX, AMENDMENT 3] Memoized test: does temp `t` transitively reach a
// load_global-ALIAS temp (a temp whose defining inst kind is `load_global`,
// recorded in `ga`)? Such an alias temp renders as the LIVE global symbol (no
// snapshot statement), so any CANDIDATE def that references it and is inlined
// re-renders the global read at the consumer slot. Transitivity follows
// candidate defs ONLY (a non-candidate def materializes at its own LIR
// position, so its read is pinned there and its result is a real snapshot).
// Memo values: 0 unknown, 1 reaches, 2 does not reach, 0xFF in-progress
// (revisited - treated as reaching, conservative; the single-assignment
// def-use graph is acyclic so this only guards pathological depth).
fn tempReachesGlobalAlias(c: *Ctx, t: u32) u8 {
    if (t >= c.max_temp) return @intCast(u8, 0);
    var pos = c.t2p[@intCast(usize, t)];
    if (pos == INVALID) return @intCast(u8, 0);
    var m = c.gam[@intCast(usize, pos)];
    if (m == @intCast(u8, 1)) return @intCast(u8, 1);
    if (m == @intCast(u8, 2)) return @intCast(u8, 0);
    if (m == @intCast(u8, 0xFF)) return @intCast(u8, 1);
    if (c.ga[@intCast(usize, pos)] == @intCast(u8, 1)) {
        c.gam[@intCast(usize, pos)] = @intCast(u8, 1);
        return @intCast(u8, 1);
    }
    if (c.cand[@intCast(usize, pos)] == @intCast(u8, 0)) {
        c.gam[@intCast(usize, pos)] = @intCast(u8, 2);
        return @intCast(u8, 0);
    }
    var bb = c.df_bb[@intCast(usize, t)];
    var ii = c.df_ii[@intCast(usize, t)];
    if (bb == INVALID or ii == INVALID) {
        c.gam[@intCast(usize, pos)] = @intCast(u8, 2);
        return @intCast(u8, 0);
    }
    c.gam[@intCast(usize, pos)] = @intCast(u8, 0xFF);
    var inst = c.lir_fn.blocks.items[@intCast(usize, bb)].insts.items[@intCast(usize, ii)];
    var r = instOperandsReachGlobalAlias(c, inst);
    if (r != @intCast(u8, 0)) {
        c.gam[@intCast(usize, pos)] = @intCast(u8, 1);
    } else {
        c.gam[@intCast(usize, pos)] = @intCast(u8, 2);
    }
    return r;
}

fn instOperandsReachGlobalAlias(c: *Ctx, inst: LirInst) u8 {
    switch (inst) {
        .binary => |b| {
            if (tempReachesGlobalAlias(c, b.lhs) != @intCast(u8, 0)) return @intCast(u8, 1);
            return tempReachesGlobalAlias(c, b.rhs);
        },
        .unary => |u| { return tempReachesGlobalAlias(c, u.operand); },
        .add_with_overflow => |o| {
            if (tempReachesGlobalAlias(c, o.lhs) != @intCast(u8, 0)) return @intCast(u8, 1);
            return tempReachesGlobalAlias(c, o.rhs);
        },
        .sub_with_overflow => |o| {
            if (tempReachesGlobalAlias(c, o.lhs) != @intCast(u8, 0)) return @intCast(u8, 1);
            return tempReachesGlobalAlias(c, o.rhs);
        },
        .mul_with_overflow => |o| {
            if (tempReachesGlobalAlias(c, o.lhs) != @intCast(u8, 0)) return @intCast(u8, 1);
            return tempReachesGlobalAlias(c, o.rhs);
        },
        .shl_with_overflow => |o| {
            if (tempReachesGlobalAlias(c, o.lhs) != @intCast(u8, 0)) return @intCast(u8, 1);
            return tempReachesGlobalAlias(c, o.rhs);
        },
        .neg_with_overflow => |o| { return tempReachesGlobalAlias(c, o.value); },
        .overflow_flag => |o| {
            if (tempReachesGlobalAlias(c, o.lhs) != @intCast(u8, 0)) return @intCast(u8, 1);
            return tempReachesGlobalAlias(c, o.rhs);
        },
        .int_cast => |ic| { return tempReachesGlobalAlias(c, ic.value); },
        .float_cast => |fc| { return tempReachesGlobalAlias(c, fc.value); },
        .ptr_cast => |pc| { return tempReachesGlobalAlias(c, pc.value); },
        .int_to_float => |itf| { return tempReachesGlobalAlias(c, itf.value); },
        .ptr_to_int => |pti| { return tempReachesGlobalAlias(c, pti.value); },
        .int_to_ptr => |itp| { return tempReachesGlobalAlias(c, itp.value); },
        .make_slice => |ms| {
            if (tempReachesGlobalAlias(c, ms.ptr) != @intCast(u8, 0)) return @intCast(u8, 1);
            return tempReachesGlobalAlias(c, ms.len);
        },
        .addr_of => |a| { return tempReachesGlobalAlias(c, a.operand); },
        .addr_of_field => |a| { return tempReachesGlobalAlias(c, a.base); },
        .wrap_optional => |w| { return tempReachesGlobalAlias(c, w.value); },
        .wrap_error_ok => |w| { return tempReachesGlobalAlias(c, w.value); },
        .wrap_error_err => |w| { return tempReachesGlobalAlias(c, w.value); },
        .unwrap_optional => |u| { return tempReachesGlobalAlias(c, u.value); },
        .unwrap_optional_checked => |u| { return tempReachesGlobalAlias(c, u.value); },
        .unwrap_optional_abi => |u| { return tempReachesGlobalAlias(c, u.value); },
        .check_optional => |ch| { return tempReachesGlobalAlias(c, ch.value); },
        .unwrap_error_payload => |u| { return tempReachesGlobalAlias(c, u.value); },
        .unwrap_error_code => |u| { return tempReachesGlobalAlias(c, u.value); },
        .check_error => |ch| { return tempReachesGlobalAlias(c, ch.value); },
        .load => |l| { return tempReachesGlobalAlias(c, l.ptr); },
        .load_field => |lf| { return tempReachesGlobalAlias(c, lf.base); },
        .load_bitfield => |lb| { return tempReachesGlobalAlias(c, lb.base); },
        .load_index => |li| {
            if (tempReachesGlobalAlias(c, li.base) != @intCast(u8, 0)) return @intCast(u8, 1);
            return tempReachesGlobalAlias(c, li.index);
        },
        else => {},
    }
    return @intCast(u8, 0);
}

fn computeNestMetadata(c: *Ctx) void {
    // Pass 1: def locators (df_bb/df_ii) + candidate bits for every def result.
    // Candidate rule (d) [Task-2 design; T4b-FIX, operator ruling 2026-09-08,
    // option B]: rule (d) applies ONLY to a MEMORY-READING PURE def (the load
    // family, see `defReadsMemory`). For such a def the SINGLE consumer
    // (scanAll's first-read locator rd_bb/rd_ii is the unique read once
    // rc == 1) must be in the SAME block as the def AND no ORDERED
    // (side-effecting) inst may sit strictly between the def and that consumer
    // in the block - inlined at a consumer across an ORDERED window such a def
    // would re-read its base at the consumer and observe an aliased write
    // twice/stale. Register/const-only PURE defs read no memory: their values
    // are pure functions of already-materialized SSA register temps (a
    // memory-reading OPERAND renders by NAME at its original position, never
    // re-inlined), so a call/assign cannot change them and they are safe to
    // nest across ORDERED windows exactly as T4b did (byte-identical emission).
    var bi: usize = @intCast(usize, 0);
    while (bi < c.lir_fn.blocks.len) : (bi += @intCast(usize, 1)) {
        var bb = &c.lir_fn.blocks.items[bi];
        // Per-block forward sweep: ord_pref[k] = number of ORDERED insts with
        // inst index < k (k in 0..n). Each candidate def's (def, consumer)
        // window then tests in O(1): no ORDERED strictly between iff
        // ord_pref[con] == ord_pref[def+1]. Deterministic fixed-order walk.
        var n = bb.insts.len;
        var ord_pref = allocU32Raw(c.alloc, @intCast(u32, n + @intCast(usize, 1)));
        ord_pref[@intCast(usize, 0)] = @intCast(u32, 0);
        var k: usize = @intCast(usize, 0);
        while (k < n) : (k += @intCast(usize, 1)) {
            var ord = @intCast(u32, 0);
            if (instOrdered(bb.insts.items[k]) != @intCast(u8, 0)) ord = @intCast(u32, 1);
            ord_pref[@intCast(usize, k + @intCast(usize, 1))] = ord_pref[@intCast(usize, k)] + ord;
        }
        var ii: usize = @intCast(usize, 0);
        while (ii < n) : (ii += @intCast(usize, 1)) {
            var inst = bb.insts.items[ii];
            var rp = defResultTemp(inst, c.lir_fn);
            if (rp == INVALID) continue;
            if (rp >= c.max_temp) continue;
            var pos = c.t2p[@intCast(usize, rp)];
            if (pos == INVALID) continue;
            c.df_bb[@intCast(usize, rp)] = @intCast(u32, bi);
            c.df_ii[@intCast(usize, rp)] = @intCast(u32, ii);
            if (c.wc[@intCast(usize, pos)] == @intCast(u32, 1) and
                c.rc[@intCast(usize, pos)] == @intCast(u32, 1) and
                c.at[@intCast(usize, pos)] == @intCast(u8, 0) and
                c.ex[@intCast(usize, pos)] == @intCast(u8, 0) and
                c.dp[@intCast(usize, pos)] == @intCast(u8, 1))
            {
                // Candidate rule (d) [T4b-FIX, operator ruling 2026-09-08,
                // option B]: the write-free window applies ONLY to a
                // memory-reading PURE def (the load family: load / load_field /
                // load_index / load_bitfield / load_local / load_global). A
                // memory-reading def needs its unique consumer (first-read
                // locator) in the SAME block strictly AFTER the def with no
                // ORDERED inst between (ord_pref test) - otherwise a re-read at
                // the consumer could observe an aliased write. Register/const-
                // only PURE defs read no memory: register values are SSA-fixed,
                // and any memory-reading OPERAND of such a def renders by NAME
                // at its original position (never re-inlined), so they are safe
                // to inline across an ORDERED window and keep the T4b pre-fix
                // marking (cand set with no window test) - byte-identical.
                if (defReadsMemory(inst) != @intCast(u8, 0)) {
                    var cb = c.rd_bb[@intCast(usize, pos)];
                    var ci = c.rd_ii[@intCast(usize, pos)];
                    if (cb == @intCast(u32, bi) and
                        ci > @intCast(u32, ii) and
                        ord_pref[@intCast(usize, ci)] == ord_pref[@intCast(usize, ii + @intCast(usize, 1))])
                    {
                        c.cand[@intCast(usize, rp)] = @intCast(u8, 1);
                    }
                } else {
                    c.cand[@intCast(usize, rp)] = @intCast(u8, 1);
                }
            }
        }
    }
    // Pass 1b [T4d-FIX, AMENDMENT 3]: rule-(d) window revision for register/
    // const-only PURE defs whose operand chain transitively reaches a
    // load_global-ALIAS temp. A load_global result has no snapshot statement
    // (the emitter aliases the temp to the LIVE global symbol), so when such a
    // def is inlined at a consumer the alias re-renders as the global NAME at
    // the consumer slot; an ORDERED write to that global strictly between def
    // and consumer would therefore be observed twice/stale - exactly the
    // memory-read hazard rule (d) exists for. Such defs are re-classified
    // memory-reading (same-block, no-ORDERED-between window). cand is only ever
    // CLEARED here (monotone, single forward sweep suffices; operands are
    // decided before their consumers in block/inst order). Pass 1 left these
    // cand==1 unconditionally (option-B register-only rule); a def in the
    // defReadsMemory set already went through Pass 1's window test.
    var bi3: usize = @intCast(usize, 0);
    while (bi3 < c.lir_fn.blocks.len) : (bi3 += @intCast(usize, 1)) {
        var bb3 = &c.lir_fn.blocks.items[bi3];
        var n3 = bb3.insts.len;
        var ord3 = allocU32Raw(c.alloc, @intCast(u32, n3 + @intCast(usize, 1)));
        ord3[@intCast(usize, 0)] = @intCast(u32, 0);
        var k3: usize = @intCast(usize, 0);
        while (k3 < n3) : (k3 += @intCast(usize, 1)) {
            var o3 = @intCast(u32, 0);
            if (instOrdered(bb3.insts.items[k3]) != @intCast(u8, 0)) o3 = @intCast(u32, 1);
            ord3[@intCast(usize, k3 + @intCast(usize, 1))] = ord3[@intCast(usize, k3)] + o3;
        }
        var ii3: usize = @intCast(usize, 0);
        while (ii3 < n3) : (ii3 += @intCast(usize, 1)) {
            var inst3 = bb3.insts.items[ii3];
            var rp3 = defResultTemp(inst3, c.lir_fn);
            if (rp3 == INVALID) continue;
            if (rp3 >= c.max_temp) continue;
            var pos3 = c.t2p[@intCast(usize, rp3)];
            if (pos3 == INVALID) continue;
            if (c.cand[@intCast(usize, pos3)] == @intCast(u8, 0)) continue;
            if (defReadsMemory(inst3) != @intCast(u8, 0)) continue;
            if (instOperandsReachGlobalAlias(c, inst3) == @intCast(u8, 0)) continue;
            var cb3 = c.rd_bb[@intCast(usize, pos3)];
            var ci3 = c.rd_ii[@intCast(usize, pos3)];
            if (cb3 == @intCast(u32, bi3) and
                ci3 > @intCast(u32, ii3) and
                ord3[@intCast(usize, ci3)] == ord3[@intCast(usize, ii3 + @intCast(usize, 1))])
            {
                continue;
            }
            c.cand[@intCast(usize, rp3)] = @intCast(u8, 0);
            c.gam[@intCast(usize, pos3)] = @intCast(u8, 0);
        }
    }
    // Pass 2: expression depths (recursion + memo; operand defs are visited on
    // demand regardless of block order).
    var bi2: usize = @intCast(usize, 0);
    while (bi2 < c.lir_fn.blocks.len) : (bi2 += @intCast(usize, 1)) {
        var bb = &c.lir_fn.blocks.items[bi2];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            var rp = defResultTemp(bb.insts.items[ii], c.lir_fn);
            if (rp == INVALID) continue;
            if (rp >= c.max_temp) continue;
            if (c.cand[@intCast(usize, rp)] == @intCast(u8, 0)) continue;
            if (c.depth[@intCast(usize, rp)] != @intCast(u8, 0)) continue;
            _ = depthOfTemp(c, rp);
        }
    }
}

fn maybeR(c: *Ctx, t: u32) u32 {
    if (t >= c.max_temp) return t;
    var r = c.ren[@intCast(usize, t)];
    if (r == INVALID) return t;
    return r;
}

fn rewriteInstOperands(c: *Ctx, inst: LirInst) LirInst {
    switch (inst) {
        .assign => |a| {
            var na = a;
            na.src = maybeR(c, na.src);
            return LirInst{ .assign = na };
        },
        .assign_field => |a| {
            var na = a;
            na.base = maybeR(c, na.base);
            na.src = maybeR(c, na.src);
            return LirInst{ .assign_field = na };
        },
        .assign_index => |a| {
            var na = a;
            na.base = maybeR(c, na.base);
            na.index = maybeR(c, na.index);
            na.src = maybeR(c, na.src);
            return LirInst{ .assign_index = na };
        },
        .branch => |b| {
            var nb = b;
            nb.cond = maybeR(c, nb.cond);
            return LirInst{ .branch = nb };
        },
        .switch_br => |s| {
            var ns = s;
            ns.cond = maybeR(c, ns.cond);
            return LirInst{ .switch_br = ns };
        },
        .ret => |v| {
            return LirInst{ .ret = maybeR(c, v) };
        },
        .binary => |b| {
            var nb = b;
            nb.lhs = maybeR(c, nb.lhs);
            nb.rhs = maybeR(c, nb.rhs);
            return LirInst{ .binary = nb };
        },
        .unary => |u| {
            var nu = u;
            nu.operand = maybeR(c, nu.operand);
            return LirInst{ .unary = nu };
        },
        .call => |cl| {
            var nc = cl;
            nc.callee = maybeR(c, nc.callee);
            return LirInst{ .call = nc };
        },
        .load_field => |lf| {
            var nl = lf;
            nl.base = maybeR(c, nl.base);
            return LirInst{ .load_field = nl };
        },
        .load_bitfield => |lb| {
            var nl = lb;
            nl.base = maybeR(c, nl.base);
            return LirInst{ .load_bitfield = nl };
        },
        .store_field => |sf| {
            var ns = sf;
            ns.base = maybeR(c, ns.base);
            ns.value = maybeR(c, ns.value);
            return LirInst{ .store_field = ns };
        },
        .store_bitfield => |sb| {
            var ns = sb;
            ns.base = maybeR(c, ns.base);
            ns.value = maybeR(c, ns.value);
            return LirInst{ .store_bitfield = ns };
        },
        .load_index => |li| {
            var nl = li;
            nl.base = maybeR(c, nl.base);
            nl.index = maybeR(c, nl.index);
            return LirInst{ .load_index = nl };
        },
        .load => |l| {
            var nl = l;
            nl.ptr = maybeR(c, nl.ptr);
            return LirInst{ .load = nl };
        },
        .store => |st| {
            var ns = st;
            ns.ptr = maybeR(c, ns.ptr);
            ns.value = maybeR(c, ns.value);
            return LirInst{ .store = ns };
        },
        .addr_of => |a| {
            var na = a;
            na.operand = maybeR(c, na.operand);
            return LirInst{ .addr_of = na };
        },
        .addr_of_field => |a| {
            var na = a;
            na.base = maybeR(c, na.base);
            return LirInst{ .addr_of_field = na };
        },
        .wrap_optional => |w| {
            var nw = w;
            nw.value = maybeR(c, nw.value);
            return LirInst{ .wrap_optional = nw };
        },
        .va_start => |vs| {
            var nv = vs;
            nv.va_list_temp = maybeR(c, nv.va_list_temp);
            nv.last_param_temp = maybeR(c, nv.last_param_temp);
            return LirInst{ .va_start = nv };
        },
        .va_arg => |va| {
            var nv = va;
            nv.va_list_temp = maybeR(c, nv.va_list_temp);
            return LirInst{ .va_arg = nv };
        },
        .va_end => |ve| {
            var nv = ve;
            nv.va_list_temp = maybeR(c, nv.va_list_temp);
            return LirInst{ .va_end = nv };
        },
        .unwrap_optional => |u| {
            var nu = u;
            nu.value = maybeR(c, nu.value);
            return LirInst{ .unwrap_optional = nu };
        },
        .unwrap_optional_checked => |u| {
            var nu = u;
            nu.value = maybeR(c, nu.value);
            return LirInst{ .unwrap_optional_checked = nu };
        },
        .unwrap_optional_abi => |u| {
            var nu = u;
            nu.value = maybeR(c, nu.value);
            return LirInst{ .unwrap_optional_abi = nu };
        },
        .check_optional => |ch| {
            var nc = ch;
            nc.value = maybeR(c, nc.value);
            return LirInst{ .check_optional = nc };
        },
        .wrap_error_ok => |w| {
            var nw = w;
            nw.value = maybeR(c, nw.value);
            return LirInst{ .wrap_error_ok = nw };
        },
        .wrap_error_err => |w| {
            var nw = w;
            nw.value = maybeR(c, nw.value);
            return LirInst{ .wrap_error_err = nw };
        },
        .unwrap_error_payload => |u| {
            var nu = u;
            nu.value = maybeR(c, nu.value);
            return LirInst{ .unwrap_error_payload = nu };
        },
        .unwrap_error_code => |u| {
            var nu = u;
            nu.value = maybeR(c, nu.value);
            return LirInst{ .unwrap_error_code = nu };
        },
        .check_error => |ch| {
            var nc = ch;
            nc.value = maybeR(c, nc.value);
            return LirInst{ .check_error = nc };
        },
        .add_with_overflow => |o| {
            var no = o;
            no.lhs = maybeR(c, no.lhs);
            no.rhs = maybeR(c, no.rhs);
            return LirInst{ .add_with_overflow = no };
        },
        .sub_with_overflow => |o| {
            var no = o;
            no.lhs = maybeR(c, no.lhs);
            no.rhs = maybeR(c, no.rhs);
            return LirInst{ .sub_with_overflow = no };
        },
        .mul_with_overflow => |o| {
            var no = o;
            no.lhs = maybeR(c, no.lhs);
            no.rhs = maybeR(c, no.rhs);
            return LirInst{ .mul_with_overflow = no };
        },
        .shl_with_overflow => |o| {
            var no = o;
            no.lhs = maybeR(c, no.lhs);
            no.rhs = maybeR(c, no.rhs);
            return LirInst{ .shl_with_overflow = no };
        },
        .neg_with_overflow => |o| {
            var no = o;
            no.value = maybeR(c, no.value);
            return LirInst{ .neg_with_overflow = no };
        },
        .overflow_flag => |o| {
            var no = o;
            no.lhs = maybeR(c, no.lhs);
            no.rhs = maybeR(c, no.rhs);
            return LirInst{ .overflow_flag = no };
        },
        .make_slice => |ms| {
            var nm = ms;
            nm.ptr = maybeR(c, nm.ptr);
            nm.len = maybeR(c, nm.len);
            return LirInst{ .make_slice = nm };
        },
        .int_cast => |ic| {
            var ni = ic;
            ni.value = maybeR(c, ni.value);
            return LirInst{ .int_cast = ni };
        },
        .float_cast => |fc| {
            var nf = fc;
            nf.value = maybeR(c, nf.value);
            return LirInst{ .float_cast = nf };
        },
        .ptr_cast => |pc| {
            var np = pc;
            np.value = maybeR(c, np.value);
            return LirInst{ .ptr_cast = np };
        },
        .int_to_float => |itf| {
            var nt = itf;
            nt.value = maybeR(c, nt.value);
            return LirInst{ .int_to_float = nt };
        },
        .ptr_to_int => |pti| {
            var nt = pti;
            nt.value = maybeR(c, nt.value);
            return LirInst{ .ptr_to_int = nt };
        },
        .int_to_ptr => |itp| {
            var nt = itp;
            nt.value = maybeR(c, nt.value);
            return LirInst{ .int_to_ptr = nt };
        },
        .store_local => |sl| {
            var ns = sl;
            ns.value = maybeR(c, ns.value);
            return LirInst{ .store_local = ns };
        },
        .store_global => |sg| {
            var ns = sg;
            ns.value = maybeR(c, ns.value);
            return LirInst{ .store_global = ns };
        },
        .print_val => |pv| {
            var np = pv;
            np.value = maybeR(c, np.value);
            return LirInst{ .print_val = np };
        },
        .builtin_put_char => |bpc| {
            var nb = bpc;
            nb.value = maybeR(c, nb.value);
            return LirInst{ .builtin_put_char = nb };
        },
        .builtin_stdout_write => |b| {
            var nb = b;
            nb.ptr = maybeR(c, nb.ptr);
            nb.len = maybeR(c, nb.len);
            return LirInst{ .builtin_stdout_write = nb };
        },
        .builtin_stderr_write => |b| {
            var nb = b;
            nb.ptr = maybeR(c, nb.ptr);
            nb.len = maybeR(c, nb.len);
            return LirInst{ .builtin_stderr_write = nb };
        },
        .builtin_exit => |be| {
            var nb = be;
            nb.value = maybeR(c, nb.value);
            return LirInst{ .builtin_exit = nb };
        },
        .builtin_sleep_ms => |bsm| {
            var nb = bsm;
            nb.value = maybeR(c, nb.value);
            return LirInst{ .builtin_sleep_ms = nb };
        },
        .builtin_console_gotoxy => |bcg| {
            var nb = bcg;
            nb.x = maybeR(c, nb.x);
            nb.y = maybeR(c, nb.y);
            return LirInst{ .builtin_console_gotoxy = nb };
        },
        .builtin_console_set_color => |bcc| {
            var nb = bcc;
            nb.fg = maybeR(c, nb.fg);
            nb.bg = maybeR(c, nb.bg);
            return LirInst{ .builtin_console_set_color = nb };
        },
        .check_trap => |ct| {
            var nc = ct;
            nc.cond = maybeR(c, nc.cond);
            if (nc.kind != @intCast(u8, 6) and nc.kind != @intCast(u8, 2)) { nc.aux = maybeR(c, nc.aux); }
            return LirInst{ .check_trap = nc };
        },
        else => return inst,
    }
}

fn copyPropagate(c: *Ctx) u8 {
    var iter: u32 = @intCast(u32, 0);
    var changed_total: u8 = @intCast(u8, 0);
    while (iter < kCopyPropMaxIter) : (iter += @intCast(u32, 1)) {
        scanAll(c);
        var changed: u8 = @intCast(u8, 0);
        var bi: usize = @intCast(usize, 0);
        while (bi < c.lir_fn.blocks.len) : (bi += @intCast(usize, 1)) {
            var bb = &c.lir_fn.blocks.items[bi];
            var ii: usize = @intCast(usize, 0);
            while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
                var inst = bb.insts.items[ii];
                switch (inst) {
                    .assign => |a| {
                        if (a.name_id != @intCast(u32, 0)) continue;
                        var dst = a.dst;
                        var src = a.src;
                        if (dst == src) continue;
                        if (dst >= c.max_temp or src >= c.max_temp) continue;
                        var dp = c.t2p[@intCast(usize, dst)];
                        var sp = c.t2p[@intCast(usize, src)];
                        if (dp == INVALID or sp == INVALID) continue;
                        var dpos: usize = @intCast(usize, dp);
                        var spos: usize = @intCast(usize, sp);
                        if (c.ex[dpos] != @intCast(u8, 0)) continue;
                        if (c.ex[spos] != @intCast(u8, 0)) continue;
                        if (c.at[dpos] != @intCast(u8, 0)) continue;
                        if (c.at[spos] != @intCast(u8, 0)) continue;
                        if (c.wc[dpos] != @intCast(u32, 1)) continue;
                        if (c.wc[spos] != @intCast(u32, 1)) continue;
                        if (c.rc[dpos] != @intCast(u32, 1)) continue;
                        if (c.rar[dpos] != @intCast(u8, 0)) continue;
                        if (c.rc[spos] != @intCast(u32, 1)) continue;
                        if (c.dp[spos] != @intCast(u8, 1)) continue;
                        if (c.rd_bb[dpos] != @intCast(u32, bi)) continue;
                        if (c.rd_ii[dpos] <= @intCast(u32, ii)) continue;
                        var dt = c.ttype[dpos];
                        var st = c.ttype[spos];
                        if (dt != st) continue;
                        if (dt >= @intCast(u32, c.reg.types_len)) continue;
                        var dty = c.reg.types_items[@intCast(usize, dt)];
                        if (copyScalarKindOk(dty.kind) == @intCast(u8, 0)) continue;
                        if (c.ren[@intCast(usize, dst)] != INVALID) continue;
                        c.ren[@intCast(usize, dst)] = src;
                        bb.insts.items[ii] = LirInst{ .nop = {} };
                        changed = @intCast(u8, 1);
                    },
                    else => {},
                }
            }
        }
        if (changed == @intCast(u8, 0)) break;
        changed_total = @intCast(u8, 1);
        // Resolve rename chains (dst -> src -> ... ) then rewrite explicit
        // operand slots function-wide.
        var t: u32 = @intCast(u32, 0);
        while (t < c.max_temp) : (t += @intCast(u32, 1)) {
            var cur = c.ren[@intCast(usize, t)];
            if (cur == INVALID) continue;
            var guard: u32 = @intCast(u32, 0);
            while (cur != INVALID and cur < c.max_temp and guard < kCopyPropMaxIter) : (guard += @intCast(u32, 1)) {
                var next = c.ren[@intCast(usize, cur)];
                if (next == INVALID or next == cur) break;
                cur = next;
            }
            c.ren[@intCast(usize, t)] = cur;
        }
        var rbi: usize = @intCast(usize, 0);
        while (rbi < c.lir_fn.blocks.len) : (rbi += @intCast(usize, 1)) {
            var bb = &c.lir_fn.blocks.items[rbi];
            var rii: usize = @intCast(usize, 0);
            while (rii < bb.insts.len) : (rii += @intCast(usize, 1)) {
                bb.insts.items[rii] = rewriteInstOperands(c, bb.insts.items[rii]);
            }
        }
    }
    return changed_total;
}

// ----- arg-slot copy coalescing (EMITCOMPACT Part 2, case 1) -----

// Rebuild a def inst with its result field rewritten to `newr`. Mirrors
// defResultTemp's result-tag set; a def kind with no true result field (or an
// impure def the gate already refuses) reports ok=0 and is left untouched.
fn retargetDefResult(inst: LirInst, newr: u32, ok: *u8) LirInst {
    switch (inst) {
        .binary => |b| { var nb = b; nb.result = newr; return LirInst{ .binary = nb }; },
        .unary => |u| { var nu = u; nu.result = newr; return LirInst{ .unary = nu }; },
        .int_const => |ic| { var ni = ic; ni.result = newr; return LirInst{ .int_const = ni }; },
        .float_const => |fc| { var nf = fc; nf.result = newr; return LirInst{ .float_const = nf }; },
        .string_const => |sc| { var ns = sc; ns.result = newr; return LirInst{ .string_const = ns }; },
        .null_const => |nc| { var nn = nc; nn.result = newr; return LirInst{ .null_const = nn }; },
        .set_optional_null => |sn| { var ns = sn; ns.result = newr; return LirInst{ .set_optional_null = ns }; },
        .bool_const => |bc| { var nb = bc; nb.result = newr; return LirInst{ .bool_const = nb }; },
        .undefined_const => |uc| { var nu = uc; nu.result = newr; return LirInst{ .undefined_const = nu }; },
        .enum_const => |ec| { var ne = ec; ne.result = newr; return LirInst{ .enum_const = ne }; },
        .int_cast => |ic| { var ni = ic; ni.result = newr; return LirInst{ .int_cast = ni }; },
        .float_cast => |fc| { var nf = fc; nf.result = newr; return LirInst{ .float_cast = nf }; },
        .ptr_cast => |pc| { var np = pc; np.result = newr; return LirInst{ .ptr_cast = np }; },
        .int_to_float => |itf| { var nt = itf; nt.result = newr; return LirInst{ .int_to_float = nt }; },
        .int_to_ptr => |itp| { var nt = itp; nt.result = newr; return LirInst{ .int_to_ptr = nt }; },
        .ptr_to_int => |pti| { var nt = pti; nt.result = newr; return LirInst{ .ptr_to_int = nt }; },
        .make_slice => |ms| { var nm = ms; nm.result = newr; return LirInst{ .make_slice = nm }; },
        .addr_of => |a| { var na = a; na.result = newr; return LirInst{ .addr_of = na }; },
        .addr_of_field => |a| { var na = a; na.result = newr; return LirInst{ .addr_of_field = na }; },
        .func_ref => |fr| { var nf = fr; nf.result = newr; return LirInst{ .func_ref = nf }; },
        .wrap_optional => |w| { var nw = w; nw.result = newr; return LirInst{ .wrap_optional = nw }; },
        .wrap_error_ok => |w| { var nw = w; nw.result = newr; return LirInst{ .wrap_error_ok = nw }; },
        .wrap_error_err => |w| { var nw = w; nw.result = newr; return LirInst{ .wrap_error_err = nw }; },
        .unwrap_optional => |u| { var nu = u; nu.result = newr; return LirInst{ .unwrap_optional = nu }; },
        .unwrap_optional_checked => |u| { var nu = u; nu.result = newr; return LirInst{ .unwrap_optional_checked = nu }; },
        .unwrap_optional_abi => |u| { var nu = u; nu.result = newr; return LirInst{ .unwrap_optional_abi = nu }; },
        .check_optional => |ch| { var nc = ch; nc.result = newr; return LirInst{ .check_optional = nc }; },
        .unwrap_error_payload => |u| { var nu = u; nu.result = newr; return LirInst{ .unwrap_error_payload = nu }; },
        .unwrap_error_code => |u| { var nu = u; nu.result = newr; return LirInst{ .unwrap_error_code = nu }; },
        .check_error => |ch| { var nc = ch; nc.result = newr; return LirInst{ .check_error = nc }; },
        .load => |l| { var nl = l; nl.result = newr; return LirInst{ .load = nl }; },
        .load_field => |lf| { var nl = lf; nl.result = newr; return LirInst{ .load_field = nl }; },
        .load_bitfield => |lb| { var nl = lb; nl.result = newr; return LirInst{ .load_bitfield = nl }; },
        .load_index => |li| { var nl = li; nl.result = newr; return LirInst{ .load_index = nl }; },
        .load_local => |ll| { var nl = ll; nl.result = newr; return LirInst{ .load_local = nl }; },
        .load_global => |lg| { var nl = lg; nl.result = newr; return LirInst{ .load_global = nl }; },
        else => { ok.* = @intCast(u8, 0); return inst; },
    }
}

// Args-run copy coalescing. A call-argument fill `.assign{name_id==0, dst =
// args_run slot, src = V}` cannot be eliminated by copy-prop above (the slot
// is rar-excluded: its single read is a call ARG slot the pass cannot rewrite
// per-slot). It collapses instead by re-targeting V's single PURE producer to
// WRITE the slot id directly (rename producer result -> slot) and tombstoning
// the fill — the call still reads the same slot id, so no args-run rewrite is
// needed. Gate (spec §4.1, applied verbatim): identical TypeId (never a
// type-changing coalesce), dst and src both single-use (rc==1), src's producer
// pure and not addr-taken, scalar/pointer trivial move (copyScalarKindOk).
// Extra window (no cross-block / ordering risk): producer, fill and the call
// read must all be in the SAME block with producer < fill < read. Anything
// failing any test stays materialized (KEEP; type/identity boundary). The
// tail-call self-param copies (name_id != 0) are never matched (KEEP).
fn coalesceArgCopies(c: *Ctx) u8 {
    var iter: u32 = @intCast(u32, 0);
    var changed_total: u8 = @intCast(u8, 0);
    while (iter < kCopyPropMaxIter) : (iter += @intCast(u32, 1)) {
        scanAll(c);
        var changed: u8 = @intCast(u8, 0);
        var bi: usize = @intCast(usize, 0);
        while (bi < c.lir_fn.blocks.len) : (bi += @intCast(usize, 1)) {
            var bb = &c.lir_fn.blocks.items[bi];
            var ii: usize = @intCast(usize, 0);
            while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
                var inst = bb.insts.items[ii];
                switch (inst) {
                    .assign => |a| {
                        if (a.name_id != @intCast(u32, 0)) continue;
                        var dst = a.dst;
                        var src = a.src;
                        if (dst == src) continue;
                        if (dst >= c.max_temp or src >= c.max_temp) continue;
                        var dp = c.t2p[@intCast(usize, dst)];
                        var sp = c.t2p[@intCast(usize, src)];
                        if (dp == INVALID or sp == INVALID) continue;
                        var dpos: usize = @intCast(usize, dp);
                        var spos: usize = @intCast(usize, sp);
                        // args-run case only: a rar==0 dst copy is copy-prop's
                        // territory and is never touched here.
                        if (c.rar[dpos] == @intCast(u8, 0)) continue;
                        if (c.ex[dpos] != @intCast(u8, 0)) continue;
                        if (c.ex[spos] != @intCast(u8, 0)) continue;
                        if (c.at[dpos] != @intCast(u8, 0)) continue;
                        if (c.at[spos] != @intCast(u8, 0)) continue;
                        if (c.wc[dpos] != @intCast(u32, 1)) continue;
                        if (c.wc[spos] != @intCast(u32, 1)) continue;
                        if (c.rc[dpos] != @intCast(u32, 1)) continue;
                        if (c.rc[spos] != @intCast(u32, 1)) continue;
                        if (c.dp[spos] != @intCast(u8, 1)) continue;
                        // the slot's single read (the call ARG read) must be in
                        // this same block strictly after the fill.
                        if (c.rd_bb[dpos] != @intCast(u32, bi)) continue;
                        if (c.rd_ii[dpos] <= @intCast(u32, ii)) continue;
                        // src's single def must be in this block strictly
                        // before the fill.
                        var pbb = c.df_bb[@intCast(usize, src)];
                        var pii = c.df_ii[@intCast(usize, src)];
                        if (pbb == INVALID or pii == INVALID) continue;
                        if (pbb != @intCast(u32, bi)) continue;
                        if (pii >= @intCast(u32, ii)) continue;
                        // identical TypeId + scalar/pointer trivial move.
                        var dt = c.ttype[dpos];
                        var st = c.ttype[spos];
                        if (dt != st) continue;
                        if (dt >= @intCast(u32, c.reg.types_len)) continue;
                        var dty = c.reg.types_items[@intCast(usize, dt)];
                        if (copyScalarKindOk(dty.kind) == @intCast(u8, 0)) continue;
                        // re-target the producer to write the slot id directly.
                        var pinst = bb.insts.items[@intCast(usize, pii)];
                        var pok: u8 = @intCast(u8, 1);
                        var npinst = retargetDefResult(pinst, dst, &pok);
                        if (pok == @intCast(u8, 0)) continue;
                        bb.insts.items[@intCast(usize, pii)] = npinst;
                        bb.insts.items[ii] = LirInst{ .nop = {} };
                        changed = @intCast(u8, 1);
                    },
                    else => {},
                }
            }
        }
        if (changed == @intCast(u8, 0)) break;
        changed_total = @intCast(u8, 1);
    }
    return changed_total;
}

// Join/merge-temp copy coalescing. An if-expr/switch/orelse/catch merge result
// temp `dst` is filled once per SURVIVING arm by
// `.assign{name_id==0, dst=join_temp, src=arm_val}`; the join temp survives
// copy-prop (its read is POST-merge in a block != the fill block, so the
// same-block-read rule refuses) while the per-arm fill's SRC producer would be
// individually prop-able. Each arm collapses exactly like the arg-slot case:
// re-target the arm's pure single-use producer result -> the join temp id and
// tombstone that arm's fill (the join temp stays; the per-arm intermediate
// disappears). Gate (spec §4.1, verbatim, PER ARM): identical TypeId (never a
// type-changing coalesce); src producer PURE (dp==1), not addr-taken, not
// excluded, single-def (wc==1) and — critically — single-USE (rc==1): a
// producer with any reader beyond this arm's fill would be corrupted by the
// retarget — never coalesce; dst single-use (rc==1), not addr-taken; the
// fill's block must not contain the temp's single read (a "dst read before
// its arm write" join is KEEP, never forced); the fill must be the ONLY def of
// dst in its block (one fill per arm); scalar/pointer trivial move
// (copyScalarKindOk); producer and fill in the SAME block with the producer
// strictly before the fill (the retargeted write keeps the arm's pre-merge
// position). Args-run fills (rar != 0) are Task-3 territory and never touched
// here; tail-call self-param copies (name_id != 0, lower.zig:5322),
// loop/iterator back-edge copies (:5118/:5171 — dst multi-read, rc > 1) and
// decl-init copies (name_id != 0, :5475/:5481) never match (KEEP, byte-
// untouched).
fn coalesceJoinCopies(c: *Ctx) u8 {
    var iter: u32 = @intCast(u32, 0);
    var changed_total: u8 = @intCast(u8, 0);
    while (iter < kCopyPropMaxIter) : (iter += @intCast(u32, 1)) {
        scanAll(c);
        var changed: u8 = @intCast(u8, 0);
        var bi: usize = @intCast(usize, 0);
        while (bi < c.lir_fn.blocks.len) : (bi += @intCast(usize, 1)) {
            var bb = &c.lir_fn.blocks.items[bi];
            var ii: usize = @intCast(usize, 0);
            while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
                var inst = bb.insts.items[ii];
                switch (inst) {
                    .assign => |a| {
                        if (a.name_id != @intCast(u32, 0)) continue;
                        var dst = a.dst;
                        var src = a.src;
                        if (dst == src) continue;
                        if (dst >= c.max_temp or src >= c.max_temp) continue;
                        var dp = c.t2p[@intCast(usize, dst)];
                        var sp = c.t2p[@intCast(usize, src)];
                        if (dp == INVALID or sp == INVALID) continue;
                        var dpos: usize = @intCast(usize, dp);
                        var spos: usize = @intCast(usize, sp);
                        // join-temp case only: an args-run slot dst (rar != 0)
                        // is Task-3's case and is never touched here.
                        if (c.rar[dpos] != @intCast(u8, 0)) continue;
                        if (c.ex[dpos] != @intCast(u8, 0)) continue;
                        if (c.ex[spos] != @intCast(u8, 0)) continue;
                        if (c.at[dpos] != @intCast(u8, 0)) continue;
                        if (c.at[spos] != @intCast(u8, 0)) continue;
                        if (c.wc[spos] != @intCast(u32, 1)) continue;
                        if (c.rc[spos] != @intCast(u32, 1)) continue;
                        if (c.dp[spos] != @intCast(u8, 1)) continue;
                        // dst single-use, and its single read must be in a
                        // block other than this arm's block (a merge read is
                        // post-merge; a same-block read is a "dst read before
                        // its arm write" violation -> KEEP; a multi-read dst
                        // is a loop-carried temp -> KEEP).
                        if (c.rc[dpos] != @intCast(u32, 1)) continue;
                        if (c.rd_bb[dpos] == @intCast(u32, bi)) continue;
                        // the fill must be the ONLY def of dst in this block
                        // (exactly one fill per surviving arm).
                        var di: usize = @intCast(usize, 0);
                        var ddefs: u32 = @intCast(u32, 0);
                        while (di < bb.insts.len) : (di += @intCast(usize, 1)) {
                            var ri = defResultTemp(bb.insts.items[di], c.lir_fn);
                            if (ri == dst) ddefs += @intCast(u32, 1);
                        }
                        if (ddefs != @intCast(u32, 1)) continue;
                        // src's single def (its PURE producer) must be in this
                        // same block strictly before the fill.
                        var pbb = c.df_bb[@intCast(usize, src)];
                        var pii = c.df_ii[@intCast(usize, src)];
                        if (pbb == INVALID or pii == INVALID) continue;
                        if (pbb != @intCast(u32, bi)) continue;
                        if (pii >= @intCast(u32, ii)) continue;
                        // identical TypeId + scalar/pointer trivial move.
                        var dt = c.ttype[dpos];
                        var st = c.ttype[spos];
                        if (dt != st) continue;
                        if (dt >= @intCast(u32, c.reg.types_len)) continue;
                        var dty = c.reg.types_items[@intCast(usize, dt)];
                        if (copyScalarKindOk(dty.kind) == @intCast(u8, 0)) continue;
                        // re-target the producer to write the join temp id
                        // directly (renamed write keeps the producer's pre-merge
                        // position; the fill is the only dst def here).
                        var pinst = bb.insts.items[@intCast(usize, pii)];
                        var pok: u8 = @intCast(u8, 1);
                        var npinst = retargetDefResult(pinst, dst, &pok);
                        if (pok == @intCast(u8, 0)) continue;
                        bb.insts.items[@intCast(usize, pii)] = npinst;
                        bb.insts.items[ii] = LirInst{ .nop = {} };
                        changed = @intCast(u8, 1);
                    },
                    else => {},
                }
            }
        }
        if (changed == @intCast(u8, 0)) break;
        changed_total = @intCast(u8, 1);
    }
    return changed_total;
}

// ----- constant folding -----

// Concrete integer type of an arbitrary temp's declared hoisted type (the
// fold result must be emitted by the int_const arm into exactly this C type).
fn resDeclIntType(c: *Ctx, temp: u32, out_w: *u32, out_s: *u8) u8 {
    if (temp >= c.max_temp) return @intCast(u8, 0);
    var p = c.t2p[@intCast(usize, temp)];
    if (p == INVALID) return @intCast(u8, 0);
    var pos: usize = @intCast(usize, p);
    if (c.ex[pos] != @intCast(u8, 0)) return @intCast(u8, 0);
    var tid = c.ttype[pos];
    if (tid >= @intCast(u32, c.reg.types_len)) return @intCast(u8, 0);
    var ty = c.reg.types_items[@intCast(usize, tid)];
    var w = intKindWidth(ty.kind);
    if (w == @intCast(u32, 0)) return @intCast(u8, 0);
    out_w.* = w;
    out_s.* = intKindSigned(ty.kind);
    return @intCast(u8, 1);
}

// A const-valued operand for a fold: int_const/bool_const-defined, stable
// (single write), not address-taken, not param/local/global-bound, declared
// concrete integer type.
fn constOperandIntType(c: *Ctx, temp: u32, out_w: *u32, out_s: *u8) u8 {
    if (temp >= c.max_temp) return @intCast(u8, 0);
    var p = c.t2p[@intCast(usize, temp)];
    if (p == INVALID) return @intCast(u8, 0);
    var pos: usize = @intCast(usize, p);
    if (c.ex[pos] != @intCast(u8, 0)) return @intCast(u8, 0);
    if (c.at[pos] != @intCast(u8, 0)) return @intCast(u8, 0);
    if (c.wc[pos] != @intCast(u32, 1)) return @intCast(u8, 0);
    if (c.cf[pos] != @intCast(u8, 1)) return @intCast(u8, 0);
    var tid = c.ttype[pos];
    if (tid >= @intCast(u32, c.reg.types_len)) return @intCast(u8, 0);
    var ty = c.reg.types_items[@intCast(usize, tid)];
    var w = intKindWidth(ty.kind);
    if (w == @intCast(u32, 0)) return @intCast(u8, 0);
    out_w.* = w;
    out_s.* = intKindSigned(ty.kind);
    return @intCast(u8, 1);
}

fn tempDeclTypeId(c: *Ctx, temp: u32) u32 {
    if (temp >= c.max_temp) return INVALID;
    var p = c.t2p[@intCast(usize, temp)];
    if (p == INVALID) return INVALID;
    return c.ttype[@intCast(usize, p)];
}

// Interpret a signed quantity's low w bits as a numeric magnitude pair.
// is_neg + mag (mag == 0 when zero/positive).
fn signMagnitude(bits: u64, w: u32, s: u8, out_neg: *u8, out_mag: *u64) void {
    var m = lowMask(w);
    var b = bits & m;
    if (s == @intCast(u8, 0)) {
        out_neg.* = @intCast(u8, 0);
        out_mag.* = b;
        return;
    }
    if ((b & sigBit(w)) == @intCast(u64, 0)) {
        out_neg.* = @intCast(u8, 0);
        out_mag.* = b;
        return;
    }
    out_neg.* = @intCast(u8, 1);
    out_mag.* = ((~b) & m) + @intCast(u64, 1);
}

// three-way signed compare of two w-bit two's-complement quantities.
fn cmpBitsSigned(a: u64, b: u64, w: u32) i8 {
    var m = lowMask(w);
    var ab = a & m;
    var bb = b & m;
    var asb = (ab & sigBit(w)) != @intCast(u64, 0);
    var bsb = (bb & sigBit(w)) != @intCast(u64, 0);
    if (asb != bsb) {
        if (asb) return @intCast(i8, -1);
        return @intCast(i8, 1);
    }
    if (!asb) {
        if (ab < bb) return @intCast(i8, -1);
        if (ab > bb) return @intCast(i8, 1);
        return @intCast(i8, 0);
    }
    var ma = ((~ab) & m) + @intCast(u64, 1);
    var mb = ((~bb) & m) + @intCast(u64, 1);
    if (ma > mb) return @intCast(i8, -1);
    if (ma < mb) return @intCast(i8, 1);
    return @intCast(i8, 0);
}

// Fold one binary/unary op instance over int_const operands. Returns 1 and
// sets out value (masked to the result width) + out_is_bool (emit bool_const).
fn tryFoldBinaryOp(c: *Ctx, inst: LirInst, out_value: *u64, out_is_bool: *u8) u8 {
    var res: u32 = @intCast(u32, 0xFFFFFFFF);
    var op: u8 = @intCast(u8, 0xFF);
    var lhs: u32 = @intCast(u32, 0xFFFFFFFF);
    var rhs: u32 = @intCast(u32, 0xFFFFFFFF);
    var operand: u32 = @intCast(u32, 0xFFFFFFFF);
    var is_unary: u8 = @intCast(u8, 0);
    switch (inst) {
        .binary => |b| {
            res = b.result;
            op = b.op;
            lhs = b.lhs;
            rhs = b.rhs;
        },
        .unary => |u| {
            res = u.result;
            op = u.op;
            operand = u.operand;
            is_unary = @intCast(u8, 1);
        },
        else => return @intCast(u8, 0),
    }

    if (is_unary != @intCast(u8, 0)) {
        var ow: u32 = @intCast(u32, 0);
        var os: u8 = @intCast(u8, 0);
        if (constOperandIntType(c, operand, &ow, &os) == @intCast(u8, 0)) return @intCast(u8, 0);
        var opnd_pos = c.t2p[@intCast(usize, operand)];
        var ob = c.cv[@intCast(usize, opnd_pos)];
        var om = lowMask(ow);
        var obits = ob & om;
        var rt = tempDeclTypeId(c, res);
        if (rt == INVALID) return @intCast(u8, 0);
        if (op == @intCast(u8, 1)) {
            // logical not -> 0/1 into a bool result
            if (rt != type_mod.TYPE_BOOL) return @intCast(u8, 0);
            var v: u64 = if (obits == @intCast(u64, 0)) @intCast(u64, 1) else @intCast(u64, 0);
            out_value.* = v;
            out_is_bool.* = @intCast(u8, 1);
            return @intCast(u8, 1);
        }
        // negate (op 0/3) and bitwise-not (op 2): result declared same width/sign
        var rw: u32 = @intCast(u32, 0);
        var rs: u8 = @intCast(u8, 0);
        if (resDeclIntType(c, res, &rw, &rs) == @intCast(u8, 0)) return @intCast(u8, 0);
        if (rw != ow or rs != os) return @intCast(u8, 0);
        if (op == @intCast(u8, 0) or op == @intCast(u8, 3)) {
            var v: u64 = (@intCast(u64, 0) - obits) & om;
            out_value.* = v;
            out_is_bool.* = @intCast(u8, 0);
            return @intCast(u8, 1);
        }
        if (op == @intCast(u8, 2)) {
            var v: u64 = (~obits) & om;
            out_value.* = v;
            out_is_bool.* = @intCast(u8, 0);
            return @intCast(u8, 1);
        }
        return @intCast(u8, 0);
    }

    // binary
    var lw: u32 = @intCast(u32, 0);
    var ls: u8 = @intCast(u8, 0);
    var rw2: u32 = @intCast(u32, 0);
    var rs2: u8 = @intCast(u8, 0);
    if (constOperandIntType(c, lhs, &lw, &ls) == @intCast(u8, 0)) return @intCast(u8, 0);
    if (constOperandIntType(c, rhs, &rw2, &rs2) == @intCast(u8, 0)) return @intCast(u8, 0);
    if (lw != rw2 or ls != rs2) return @intCast(u8, 0);
    var w: u32 = lw;
    var signed: u8 = ls;
    var is_cmp: u8 = @intCast(u8, 0);
    if (op >= @intCast(u8, 10) and op <= @intCast(u8, 15)) { is_cmp = @intCast(u8, 1); }
    var rt3 = tempDeclTypeId(c, res);
    if (rt3 == INVALID) return @intCast(u8, 0);
    if (is_cmp != @intCast(u8, 0)) {
        if (rt3 != type_mod.TYPE_BOOL) {
            // comparison result may alternatively be a concrete int of the
            // operand type (0/1 value)
            var rw3: u32 = @intCast(u32, 0);
            var rs3: u8 = @intCast(u8, 0);
            if (resDeclIntType(c, res, &rw3, &rs3) == @intCast(u8, 0)) return @intCast(u8, 0);
            if (rw3 != w or rs3 != signed) return @intCast(u8, 0);
        }
    } else {
        if (rt3 == type_mod.TYPE_BOOL) return @intCast(u8, 0);
        var rw4: u32 = @intCast(u32, 0);
        var rs4: u8 = @intCast(u8, 0);
        if (resDeclIntType(c, res, &rw4, &rs4) == @intCast(u8, 0)) return @intCast(u8, 0);
        if (rw4 != w or rs4 != signed) return @intCast(u8, 0);
    }
    var lp = c.t2p[@intCast(usize, lhs)];
    var rp2 = c.t2p[@intCast(usize, rhs)];
    var la = c.cv[@intCast(usize, lp)];
    var rb = c.cv[@intCast(usize, rp2)];
    var m = lowMask(w);
    var ab = la & m;
    var bb = rb & m;
    var v: u64 = @intCast(u64, 0);
    if (op == @intCast(u8, 0) or op == @intCast(u8, 16)) {
        v = (ab + bb) & m;
    } else if (op == @intCast(u8, 1) or op == @intCast(u8, 17)) {
        v = (ab - bb) & m;
    } else if (op == @intCast(u8, 2) or op == @intCast(u8, 18)) {
        v = (ab * bb) & m;
    } else if (op == @intCast(u8, 3)) {
        if (signed != @intCast(u8, 0)) return @intCast(u8, 0);
        if (bb == @intCast(u64, 0)) return @intCast(u8, 0);
        v = (ab / bb) & m;
    } else if (op == @intCast(u8, 4)) {
        if (signed != @intCast(u8, 0)) return @intCast(u8, 0);
        if (bb == @intCast(u64, 0)) return @intCast(u8, 0);
        v = (ab % bb) & m;
    } else if (op == @intCast(u8, 5)) {
        v = ab & bb;
    } else if (op == @intCast(u8, 6)) {
        v = ab | bb;
    } else if (op == @intCast(u8, 7)) {
        v = ab ^ bb;
    } else if (op == @intCast(u8, 8)) {
        if (signed != @intCast(u8, 0)) return @intCast(u8, 0);
        if (bb >= @intCast(u64, w)) return @intCast(u8, 0);
        v = (ab << bb) & m;
    } else if (op == @intCast(u8, 9)) {
        if (signed != @intCast(u8, 0)) return @intCast(u8, 0);
        if (bb >= @intCast(u64, w)) return @intCast(u8, 0);
        v = ab >> bb;
    } else if (op == @intCast(u8, 10)) {
        v = if (ab == bb) @intCast(u64, 1) else @intCast(u64, 0);
    } else if (op == @intCast(u8, 11)) {
        v = if (ab != bb) @intCast(u64, 1) else @intCast(u64, 0);
    } else if (op == @intCast(u8, 12)) {
        if (signed != @intCast(u8, 0)) { v = if (cmpBitsSigned(ab, bb, w) < 0) @intCast(u64, 1) else @intCast(u64, 0); } else { v = if (ab < bb) @intCast(u64, 1) else @intCast(u64, 0); }
    } else if (op == @intCast(u8, 13)) {
        if (signed != @intCast(u8, 0)) { v = if (cmpBitsSigned(ab, bb, w) <= 0) @intCast(u64, 1) else @intCast(u64, 0); } else { v = if (ab <= bb) @intCast(u64, 1) else @intCast(u64, 0); }
    } else if (op == @intCast(u8, 14)) {
        if (signed != @intCast(u8, 0)) { v = if (cmpBitsSigned(ab, bb, w) > 0) @intCast(u64, 1) else @intCast(u64, 0); } else { v = if (ab > bb) @intCast(u64, 1) else @intCast(u64, 0); }
    } else if (op == @intCast(u8, 15)) {
        if (signed != @intCast(u8, 0)) { v = if (cmpBitsSigned(ab, bb, w) >= 0) @intCast(u64, 1) else @intCast(u64, 0); } else { v = if (ab >= bb) @intCast(u64, 1) else @intCast(u64, 0); }
    } else {
        return @intCast(u8, 0);
    }
    out_value.* = v;
    out_is_bool.* = if (rt3 == type_mod.TYPE_BOOL) @intCast(u8, 1) else @intCast(u8, 0);
    return @intCast(u8, 1);
}

// Lossless un-checked int_cast fold: source const value exactly representable
// at the target (result declared == target).
fn tryFoldIntCast(c: *Ctx, inst: LirInst, out_value: *u64) u8 {
    switch (inst) {
        .int_cast => |ic| {
            if (ic.is_checked != @intCast(u8, 0)) return @intCast(u8, 0);
            var res = ic.result;
            var val_t = ic.value;
            var rt = tempDeclTypeId(c, res);
            if (rt == INVALID) return @intCast(u8, 0);
            if (rt != ic.target) return @intCast(u8, 0);
            var ow: u32 = @intCast(u32, 0);
            var os: u8 = @intCast(u8, 0);
            if (constOperandIntType(c, val_t, &ow, &os) == @intCast(u8, 0)) return @intCast(u8, 0);
            if (rt >= @intCast(u32, c.reg.types_len)) return @intCast(u8, 0);
            var ty = c.reg.types_items[@intCast(usize, rt)];
            var tw = intKindWidth(ty.kind);
            if (tw == @intCast(u32, 0)) return @intCast(u8, 0);
            var ts = intKindSigned(ty.kind);
            var vp = c.t2p[@intCast(usize, val_t)];
            var bits = c.cv[@intCast(usize, vp)];
            var m = lowMask(ow);
            var b = bits & m;
            var is_neg: u8 = @intCast(u8, 0);
            var mag: u64 = @intCast(u64, 0);
            signMagnitude(b, ow, os, &is_neg, &mag);
            var ok: u8 = @intCast(u8, 0);
            if (ts == @intCast(u8, 0)) {
                if (is_neg == @intCast(u8, 0)) {
                    var ub: u64 = lowMask(tw);
                    if (mag <= ub) ok = @intCast(u8, 1);
                }
            } else {
                var mag_lim: u64 = sigBit(tw);
                if (is_neg != @intCast(u8, 0)) {
                    if (mag <= mag_lim) ok = @intCast(u8, 1);
                } else {
                    if (mag < mag_lim) ok = @intCast(u8, 1);
                }
            }
            if (ok == @intCast(u8, 0)) return @intCast(u8, 0);
            var tm = lowMask(tw);
            var v: u64 = @intCast(u64, 0);
            if (is_neg != @intCast(u8, 0)) {
                v = (@intCast(u64, 0) - mag) & tm;
            } else {
                v = mag & tm;
            }
            out_value.* = v;
            return @intCast(u8, 1);
        },
        else => return @intCast(u8, 0),
    }
}

fn runConstFold(c: *Ctx) u8 {
    var changed: u8 = @intCast(u8, 0);
    var bi: usize = @intCast(usize, 0);
    while (bi < c.lir_fn.blocks.len) : (bi += @intCast(usize, 1)) {
        var bb = &c.lir_fn.blocks.items[bi];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            var inst = bb.insts.items[ii];
            switch (inst) {
                .binary => |b| {
                    var v: u64 = @intCast(u64, 0);
                    var is_bool: u8 = @intCast(u8, 0);
                    if (tryFoldBinaryOp(c, inst, &v, &is_bool) == @intCast(u8, 1)) {
                        if (is_bool != @intCast(u8, 0)) {
                            var bv: u8 = if (v != @intCast(u64, 0)) @intCast(u8, 1) else @intCast(u8, 0);
                            bb.insts.items[ii] = LirInst{ .bool_const = .{ .value = bv, .result = b.result } };
                        } else {
                            bb.insts.items[ii] = LirInst{ .int_const = .{ .value = v, .result = b.result } };
                        }
                        changed = @intCast(u8, 1);
                    }
                },
                .unary => |u| {
                    var v: u64 = @intCast(u64, 0);
                    var is_bool: u8 = @intCast(u8, 0);
                    if (tryFoldBinaryOp(c, inst, &v, &is_bool) == @intCast(u8, 1)) {
                        if (is_bool != @intCast(u8, 0)) {
                            var bv: u8 = if (v != @intCast(u64, 0)) @intCast(u8, 1) else @intCast(u8, 0);
                            bb.insts.items[ii] = LirInst{ .bool_const = .{ .value = bv, .result = u.result } };
                        } else {
                            bb.insts.items[ii] = LirInst{ .int_const = .{ .value = v, .result = u.result } };
                        }
                        changed = @intCast(u8, 1);
                    }
                },
                .int_cast => |ic| {
                    var v: u64 = @intCast(u64, 0);
                    if (tryFoldIntCast(c, inst, &v) == @intCast(u8, 1)) {
                        bb.insts.items[ii] = LirInst{ .int_const = .{ .value = v, .result = ic.result } };
                        changed = @intCast(u8, 1);
                    }
                },
                else => {},
            }
        }
    }
    return changed;
}

/// Per-function LIR optimization entry: copy propagation + local constant
/// folding. Runs post-reload, pre-emission. Deterministic; mutates
/// `lir_fn` in place. `alloc` is the per-function scratch sand (reset by the
/// emission driver between functions).
pub fn lirOptRun(alloc: *Sand, reg: *TypeRegistry, lir_fn: *LirFunction) void {
    // Invalidate any previous function's published nest metadata (a function
    // that never runs the pass must not be able to read a stale row).
    g_nest_active = @intCast(u8, 0);
    var max_temp = maxTempOf(lir_fn);
    if (max_temp == @intCast(u32, 0)) return;
    var c = Ctx{
        .alloc = alloc,
        .reg = reg,
        .lir_fn = lir_fn,
        .max_temp = max_temp,
        .t2p = allocU32With(alloc, max_temp, INVALID),
        .ttype = allocU32With(alloc, max_temp, type_mod.TYPE_UNDEFINED),
        .rc = allocU32Raw(alloc, max_temp),
        .wc = allocU32Raw(alloc, max_temp),
        .at = allocU8Raw(alloc, max_temp),
        .ex = allocU8Raw(alloc, max_temp),
        .dp = allocU8Raw(alloc, max_temp),
        .rd_bb = allocU32Raw(alloc, max_temp),
        .rd_ii = allocU32Raw(alloc, max_temp),
        .rar = allocU8Raw(alloc, max_temp),
        .cf = allocU8Raw(alloc, max_temp),
        .cv = allocU64Raw(alloc, max_temp),
        .ren = allocU32With(alloc, max_temp, INVALID),
        .cand = allocU8Raw(alloc, max_temp),
        .depth = allocU8Raw(alloc, max_temp),
        .df_bb = allocU32Raw(alloc, max_temp),
        .df_ii = allocU32Raw(alloc, max_temp),
        .ga = allocU8Raw(alloc, max_temp),
        .gam = allocU8Raw(alloc, max_temp),
    };
    var hti: usize = @intCast(usize, 0);
    while (hti < lir_fn.hoisted_temps.len) : (hti += @intCast(usize, 1)) {
        var td = lir_fn.hoisted_temps.items[hti];
        if (td.temp_id < max_temp) {
            c.t2p[@intCast(usize, td.temp_id)] = @intCast(u32, hti);
            c.ttype[@intCast(usize, td.temp_id)] = td.type_id;
        }
    }
    resetScratch(&c);
    _ = copyPropagate(&c);
    // Refresh scratch after copy-prop rewrites, then fold.
    scanAll(&c);
    _ = runConstFold(&c);
    // EMITCOMPACT Part-2 case 1: coalesce call-argument slot copies
    // (producer-result rename -> slot). Runs after copy-prop + const-fold so
    // every remaining fill is a genuine args-run copy and its producer is the
    // final (possibly folded) def.
    _ = coalesceArgCopies(&c);
    // EMITCOMPACT Part-2 case 2: coalesce join/merge-temp copies (per-arm
    // producer-result rename -> join temp). Runs after arg-slot coalescing;
    // disjoint by gate (rar != 0 fills are Task-3's, never matched here).
    _ = coalesceJoinCopies(&c);
    // T4a: record nest-candidate + expression-depth metadata on the FINAL LIR
    // (post copy-prop + const-fold + arg-slot + join-temp coalesce).
    scanAll(&c);
    computeNestMetadata(&c);
    // T4b: publish the active function's rows (arrays stay Sand-backed; valid
    // until the emission driver's next sandReset). The EMITTER reads these
    // during this function's emission only.
    g_nest_active = @intCast(u8, 1);
    g_nest_max = max_temp;
    g_nest_cand = c.cand;
    g_nest_depth = c.depth;
    g_nest_dfbb = c.df_bb;
    g_nest_dfii = c.df_ii;
    g_nest_rdbb = c.rd_bb;
    g_nest_rdii = c.rd_ii;
}

fn allocU32With(alloc: *Sand, n: u32, fill: u32) [*]u32 {
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, n) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable;
    var a = @ptrCast([*]u32, raw);
    var i: u32 = @intCast(u32, 0);
    while (i < n) : (i += @intCast(u32, 1)) {
        a[@intCast(usize, i)] = fill;
    }
    return a;
}

fn allocU32Raw(alloc: *Sand, n: u32) [*]u32 {
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, n) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable;
    return @ptrCast([*]u32, raw);
}

fn allocU64Raw(alloc: *Sand, n: u32) [*]u64 {
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, n) * @intCast(usize, @sizeOf(u64)), @intCast(usize, 4)) catch unreachable;
    return @ptrCast([*]u64, raw);
}

fn allocU8Raw(alloc: *Sand, n: u32) [*]u8 {
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, n) * @intCast(usize, @sizeOf(u8)), @intCast(usize, 1)) catch unreachable;
    return @ptrCast([*]u8, raw);
}
