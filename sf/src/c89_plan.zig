// P6-pre (operator ruling 2026-10-12 (ii)): the C-specific pre-emit SPELLING
// planner. Carriers (the i32/u32/i64/u64 C materialization of an integer
// constant) are C-spelling choices, never LIR fields — an asm backend gets its
// own planner over the same semantic LIR. LIR carries semantic int facts only
// (the const's type/width/signedness + value); this module derives the C
// carriers from those facts at the backend-neutral `phase_EmissionClassification
// boundary, stores them as side-table state (`C89SpellPlan`), and the emitter
// reads them at spell time (Decision-vs-spelling: the emitter spells, never
// decides). P12 (typedef ordering — `typedef_order`, planned ONCE at the same
// boundary; the emitter walks the carried order and never sorts) joins the
// same `C89SpellPlan`; P11 (UAC cast direction) later adds its state here too.
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
// `spellInstOrd`) to the planned carrier type id. P12: `typedef_order` is the
// typedef emission order (planned ONCE at the boundary; see
// `spellPlanPlanTypeOrder`).
pub const C89SpellPlan = struct {
    fn_keys: [*]u32,
    fn_maps: [*]hash_mod.U32ToU32Map,
    fn_count: usize,
    fn_cap: usize,
    typedef_order: [*]u32,
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
    plan.typedef_order = undefined;
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

// P2 (emitter sanitization, D8 root cause): typedef ordering derives from the
// single type-reference relation in `type_registry.zig` (`typeRefs` /
// `typeRefsContains` / `typeNeedsFullDef`). The former
// hand-rolled edge machinery (`c89NeedsEmitEdge`, `tstEdgesWalk`,
// `tstSeenInRange`, `tstEdgesCount`, `tstEdgesFill`, `tstIsDep`) is deleted —
// no divergent kind membership remains. The relation covers ALL kinds, incl.
// `fn_type` return/param refs (D8: a fn-ptr typedef now follows its return
// typedef) and `packed_union`.
// P12: moved here verbatim from `c89_emit.zig` (the ordering DECISION is the
// planner's; the emitter walks the carried order and never sorts). The five
// `sandAlloc`s stay consecutive — `result` is immediately followed by `queue`
// in the bump arena, and the emission passes' pre-existing live-`types_len`
// walks over-read into that `queue` buffer exactly as before (P2 deferred
// minor: bounded harm; the follow-up "bound on snapshot length" is unchanged
// and NOT taken here).
fn tstTopologicalSort(reg: *TypeRegistry, alloc: *Sand) [*]u32 {
    var tl: usize = reg.types_len;
    var indegree_raw = alloc_mod.sandAlloc(alloc, 4 * tl, 4) catch unreachable;
    var indegree: [*]u32 = @ptrCast([*]u32, indegree_raw);
    var ti: u32 = @intCast(u32, 0);
    var edge_raw = alloc_mod.sandAlloc(alloc, 4 * tl, 4) catch unreachable;
    var edge_buf: [*]u32 = @ptrCast([*]u32, edge_raw);
    while (@intCast(usize, ti) < tl) : (ti += 1) {
        indegree[@intCast(usize, ti)] = type_mod.typeRefs(reg, ti, edge_buf);
    }
    var result_raw = alloc_mod.sandAlloc(alloc, 4 * tl, 4) catch unreachable;
    var result: [*]u32 = @ptrCast([*]u32, result_raw);
    var queue_raw = alloc_mod.sandAlloc(alloc, 4 * tl, 4) catch unreachable;
    var queue: [*]u32 = @ptrCast([*]u32, queue_raw);
    var popped_raw = alloc_mod.sandAlloc(alloc, 1 * tl, 1) catch unreachable;
    var popped: [*]u8 = @ptrCast([*]u8, popped_raw);
    var zi: usize = @intCast(usize, 0);
    while (zi < tl) : (zi += 1) { popped[zi] = @intCast(u8, 0); }
    var qhead: usize = 0;
    var qtail: usize = 0;
    ti = @intCast(u32, 0);
    while (@intCast(usize, ti) < tl) : (ti += 1) {
        if (indegree[@intCast(usize, ti)] == 0) {
            queue[qtail] = ti; qtail += 1;
        }
    }
    var ri: usize = 0;
    while (qhead < qtail) {
        var cur = queue[qhead]; qhead += 1;
        result[ri] = cur; ri += 1;
        popped[@intCast(usize, cur)] = @intCast(u8, 1);
        var tj: u32 = @intCast(u32, 0);
        while (@intCast(usize, tj) < tl) : (tj += 1) {
            if (type_mod.typeRefsContains(reg, tj, cur)) {
                var idx = @intCast(usize, tj);
                indegree[idx] = indegree[idx] - @intCast(u32, 1);
                if (indegree[idx] == 0) {
                    queue[qtail] = tj; qtail += 1;
                }
            }
        }
    }
    // P2 fix round 1 (controller ruling — APPEND variant): Kahn leaves any
    // cycle residue (nodes whose indegree never reaches 0) out of `result`, and
    // the type-emission passes walk `sorted[0..types_len]` — an uncovered tail
    // reads uninitialized arena memory. Append the residue in stable
    // ascending-tid order so `sorted` ALWAYS covers all `types_len` entries
    // (no garbage reads possible). For acyclic programs this is a no-op (ri ==
    // tl already). A post-resolve cyclic type still emits (possibly invalid C)
    // instead of clean-rejecting — the pre-P2 behavior class; the diagnose/
    // reject variant is rejected by ruling (no new error codes).
    var ai: usize = @intCast(usize, 0);
    while (ai < tl) : (ai += 1) {
        if (popped[ai] == @intCast(u8, 0)) {
            result[ri] = @intCast(u32, ai);
            ri += 1;
        }
    }
    return result;
}

// P12: THE typedef emission order, planned ONCE at the
// `phase_EmissionClassification` boundary from the P2 relation (ordering is on
// the "emitter never decides" list — the emitter walks `typedef_order` and
// never sorts). Deterministic (same registry → same order every compilation);
// covers every `types_len` tid exactly once at planning time. No marker
// emitted (the `--markers` stream stays byte-identical).
pub fn spellPlanPlanTypeOrder(plan: *C89SpellPlan, alloc: *Sand, reg: *TypeRegistry) void {
    plan.typedef_order = tstTopologicalSort(reg, alloc);
}
