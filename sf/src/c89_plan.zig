// P6-pre (operator ruling 2026-10-12 (ii)): the C-specific pre-emit SPELLING
// planner. Carriers (the i32/u32/i64/u64 C materialization of an integer
// constant) are C-spelling choices, never LIR fields — an asm backend gets its
// own planner over the same semantic LIR. LIR carries semantic int facts only
// (the const's type/width/signedness + value); this module derives the C
// carriers from those facts at the backend-neutral `phase_EmissionClassification
// boundary, stores them as side-table state (`C89SpellPlan`), and the emitter
// reads them at spell time (Decision-vs-spelling: the emitter spells, never
// decides). P12 (typedef ordering) and P11 (UAC cast direction) later add
// their state to the same `C89SpellPlan`.
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeKind = @import("type_registry.zig").TypeKind;
const type_mod = @import("type_registry.zig");
const LirFunction = @import("lir.zig").LirFunction;
const hash_mod = @import("util/hash.zig");
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");

// Per-fn const-carrier maps: `fn_keys[i]` identifies fn `i` by its LIR spill
// slot offset (unique per fn; stable across the emission-time `lir_slots`
// regrouping), `fn_maps[i]` maps the fn-local flattened inst ordinal (see
// `spellInstOrd`) to the planned carrier type id. P12 adds typedef-order state
// here (same boundary, same mechanism).
pub const C89SpellPlan = struct {
    fn_keys: [*]u32,
    fn_maps: [*]hash_mod.U32ToU32Map,
    fn_count: usize,
    fn_cap: usize,
};

// THE derivation (facts -> carrier). width_bits == 0 is never passed here
// (the caller keeps the historical value rule for that class).
fn carrierFromFacts(width_bits: u8, is_signed: u8) u32 {
    if (width_bits == @intCast(u8, 32)) {
        if (is_signed != @intCast(u8, 0)) { return type_mod.TYPE_I32; }
        return type_mod.TYPE_U32;
    }
    if (is_signed != @intCast(u8, 0)) { return type_mod.TYPE_I64; }
    return type_mod.TYPE_U64;
}

pub fn deriveConstCarrier(reg: *TypeRegistry, semantic_tid: u32, value: u64, width_bits: u8, is_signed: u8) u32 {
    var hty = reg.types_items[@intCast(usize, semantic_tid)];
    if (hty.kind == TypeKind.integer_literal_type) {
        // UNTYPED hoisted: a fact-carryed exact-value materialization takes the
        // facts (the sign disambiguation lives here); a bare untyped literal
        // keeps the historical value rule (I32/U32/U64 — no i64 arm).
        if (width_bits != @intCast(u8, 0)) { return carrierFromFacts(width_bits, is_signed); }
        if (value <= @intCast(u64, 2147483647)) { return type_mod.TYPE_I32; }
        if (value <= @intCast(u64, 4294967295)) { return type_mod.TYPE_U32; }
        return type_mod.TYPE_U64;
    }
    if (semantic_tid == type_mod.TYPE_UNDEFINED) { return type_mod.TYPE_USIZE; }
    return semantic_tid;
}

// Const-id ordinal encoding: the flattened inst position in a fn's block
// order (stable across the emit-time `lirOptRun`, which rewrites insts in
// place only). Per-CONST (not per-temp) keys: join copy coalescing can
// retarget two arm consts onto one join temp, and the carrier is derived per
// const.
pub fn spellInstOrd(lir_fn: *LirFunction, bb_idx: usize, ii: usize) u32 {
    var ord: usize = @intCast(usize, 0);
    var bi: usize = @intCast(usize, 0);
    while (bi < bb_idx) : (bi += @intCast(usize, 1)) {
        ord += lir_fn.blocks.items[bi].insts.len;
    }
    ord += ii;
    return @intCast(u32, ord);
}

fn spellPlanGrow(plan: *C89SpellPlan, alloc: *Sand) void {
    var new_cap: usize = if (plan.fn_cap < @intCast(usize, 8)) @intCast(usize, 8) else plan.fn_cap * @intCast(usize, 2);
    var raw_keys = alloc_mod.sandAlloc(alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_maps = alloc_mod.sandAlloc(alloc, @intCast(usize, @sizeOf(hash_mod.U32ToU32Map)) * new_cap, @intCast(usize, 4)) catch unreachable;
    var ndi: usize = @intCast(usize, 0);
    while (ndi < plan.fn_count) : (ndi += @intCast(usize, 1)) {
        @ptrCast([*]u32, raw_keys)[ndi] = plan.fn_keys[ndi];
        @ptrCast([*]hash_mod.U32ToU32Map, raw_maps)[ndi] = plan.fn_maps[ndi];
    }
    plan.fn_keys = @ptrCast([*]u32, raw_keys);
    plan.fn_maps = @ptrCast([*]hash_mod.U32ToU32Map, raw_maps);
    plan.fn_cap = new_cap;
}

pub fn spellPlanInit(plan: *C89SpellPlan, alloc: *Sand, fn_hint: usize) void {
    plan.fn_keys = undefined;
    plan.fn_maps = undefined;
    plan.fn_count = @intCast(usize, 0);
    plan.fn_cap = @intCast(usize, 0);
    if (fn_hint != @intCast(usize, 0)) {
        var raw_keys = alloc_mod.sandAlloc(alloc, @intCast(usize, 4) * fn_hint, @intCast(usize, 4)) catch unreachable;
        var raw_maps = alloc_mod.sandAlloc(alloc, @intCast(usize, @sizeOf(hash_mod.U32ToU32Map)) * fn_hint, @intCast(usize, 4)) catch unreachable;
        plan.fn_keys = @ptrCast([*]u32, raw_keys);
        plan.fn_maps = @ptrCast([*]hash_mod.U32ToU32Map, raw_maps);
        plan.fn_cap = fn_hint;
    }
}

// Boundary fill for one fn (called from `phase_EmissionClassification`'s LIR
// walk; no marker traffic — the `--markers` stream stays byte-identical).
// Records `deriveConstCarrier` for every inst kind that is — or, after the
// emit-time `lirOptRun`, becomes — an `int_const` (`int_const`/`binary`/
// `unary`/`int_cast`; the const-fold gate refuses untyped temps, so a folded
// const's carrier is its semantic type and value-irrelevant — recorded with
// value 0 for the non-const kinds).
pub fn spellPlanPlanFn(plan: *C89SpellPlan, alloc: *Sand, reg: *TypeRegistry, fn_key: u32, lir_fn: *LirFunction) void {
    if (plan.fn_count >= plan.fn_cap) { spellPlanGrow(plan, alloc); }
    var fi: usize = plan.fn_count;
    plan.fn_keys[fi] = fn_key;
    plan.fn_maps[fi] = hash_mod.u32ToU32MapInitCap(alloc, lir_fn.hoisted_temps.len + @intCast(usize, 16));
    plan.fn_count = fi + @intCast(usize, 1);
    var ord: usize = @intCast(usize, 0);
    var bi: usize = @intCast(usize, 0);
    while (bi < lir_fn.blocks.len) : (bi += @intCast(usize, 1)) {
        var bb = &lir_fn.blocks.items[bi];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            var inst = bb.insts.items[ii];
            var result: u32 = @intCast(u32, 0xFFFFFFFF);
            var value: u64 = @intCast(u64, 0);
            var ic_width: u8 = @intCast(u8, 0);
            var ic_signed: u8 = @intCast(u8, 0);
            var plan_kind: u8 = @intCast(u8, 0);
            switch (inst) {
                .int_const => |ic| {
                    result = ic.result;
                    value = ic.value;
                    ic_width = ic.width_bits;
                    ic_signed = ic.is_signed;
                    plan_kind = @intCast(u8, 1);
                },
                .binary => |b| { result = b.result; plan_kind = @intCast(u8, 1); },
                .unary => |u| { result = u.result; plan_kind = @intCast(u8, 1); },
                .int_cast => |c| { result = c.result; plan_kind = @intCast(u8, 1); },
                else => {},
            }
            if (plan_kind != @intCast(u8, 0) and result != @intCast(u32, 0xFFFFFFFF)) {
                var ht: u32 = @intCast(u32, 0xFFFFFFFF);
                var hi: usize = @intCast(usize, 0);
                while (hi < lir_fn.hoisted_temps.len) : (hi += @intCast(usize, 1)) {
                    if (lir_fn.hoisted_temps.items[hi].temp_id == result) {
                        ht = lir_fn.hoisted_temps.items[hi].type_id;
                        break;
                    }
                }
                if (ht != @intCast(u32, 0xFFFFFFFF)) {
                    var carrier = deriveConstCarrier(reg, ht, value, ic_width, ic_signed);
                    hash_mod.u32ToU32MapPut(&plan.fn_maps[fi], @intCast(u32, ord), carrier);
                }
            }
            ord += @intCast(usize, 1);
        }
    }
}

// Spell-time read (the emitter's only carrier source). `fn_key` is the
// current fn's LIR spill slot offset; `inst_ord` the const's `spellInstOrd`.
pub fn spellPlanCarrier(plan: *C89SpellPlan, fn_key: u32, inst_ord: u32) ?u32 {
    var fi: usize = @intCast(usize, 0);
    while (fi < plan.fn_count) : (fi += @intCast(usize, 1)) {
        if (plan.fn_keys[fi] == fn_key) {
            return hash_mod.u32ToU32MapGet(&plan.fn_maps[fi], inst_ord);
        }
    }
    return null;
}
