const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;
const AstNode = @import("ast.zig").AstNode;
const StringInterner = @import("string_interner.zig").StringInterner;
const SymbolRegistry = @import("symbol_table.zig").SymbolRegistry;
const sym_mod = @import("symbol_table.zig");
const type_mod = @import("type_registry.zig");
const ast_mod = @import("ast.zig");
const interner_mod = @import("string_interner.zig");
const type_resolver = @import("type_resolver.zig");
const diag_mod = @import("diagnostics.zig");
const hash_mod = @import("util/hash.zig");
const alloc_mod = @import("allocator.zig");

// Task 2: fixed-cap arbitrary-precision comptime integer (Task 1 design §2).
// Little-endian u32 magnitude limbs, 8 limbs = 256 bits; `len` is one past the
// top non-zero limb (0 = zero); `neg` is the sign (`false` when zero).
pub const COMPTIME_INT_LIMBS: u8 = 8;

pub const ComptimeInt = struct {
    mag: [8]u32,
    len: u8,
    neg: bool,
};

// `kind` replaces the old `width_bits` sentinel role (Task 1 §2): 0 = integer
// comptime_int, 1 = bool (the old `width_bits == 1` test), 2 = float (the old
// WIDTH_FLOAT sentinel; the f64 bit pattern rides in `float_bits`).
pub const KIND_INT: u8 = 0;
pub const KIND_BOOL: u8 = 1;
pub const KIND_FLOAT: u8 = 2;

// Task 9 (Part II): significand widths of the IEEE binary formats, used to
// require an integer comparison operand to be exactly representable in the
// comparison's float peer before the float fold may fire.
pub const F32_SIGNIFICAND_BITS: u32 = 24;
pub const F64_SIGNIFICAND_BITS: u32 = 53;

pub const ComptimeVal = struct {
    v: ComptimeInt,
    kind: u8,
    float_bits: u64,
};

// Task 4 (Task 1 §6.2): the fold table keeps the EXACT folded value, not a
// 64-bit pattern. Node -> slot in a dense `ComptimeVal` array; both live in the
// module arena. Exact storage is required because the u64 pattern cannot
// distinguish `-1` from `18446744073709551615`, and because a folded value
// outside [i64 min, u64 max] must be rejected at the materialisation site
// (Task 1 §8 risk 1) instead of silently vanishing from the table.
pub const ComptimeFoldTable = struct {
    slots: hash_mod.U32ToU32Map,
    vals: [*]ComptimeVal,
    len: usize,
    capacity: usize,
    alloc: *alloc_mod.Sand,
};

pub fn comptimeFoldTableInit(alloc: *alloc_mod.Sand) ComptimeFoldTable {
    return ComptimeFoldTable{
        .slots = hash_mod.u32ToU32MapInit(alloc),
        .vals = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .alloc = alloc,
    };
}

fn comptimeFoldTableGrow(self: *ComptimeFoldTable) void {
    var old_cap = self.capacity;
    var old_vals = self.vals;
    var new_cap: usize = @intCast(usize, 16);
    if (old_cap >= @intCast(usize, 16)) { new_cap = old_cap * @intCast(usize, 2); }
    var raw = alloc_mod.sandAlloc(self.alloc, @sizeOf(ComptimeVal) * new_cap, @intCast(usize, 8)) catch unreachable;
    var new_vals = @ptrCast([*]ComptimeVal, raw);
    var i: usize = 0;
    while (i < self.len) : (i += @intCast(usize, 1)) { new_vals[i] = old_vals[i]; }
    self.vals = new_vals;
    self.capacity = new_cap;
}

pub fn comptimeFoldTablePut(self: *ComptimeFoldTable, node_idx: u32, v: ComptimeVal) void {
    if (hash_mod.u32ToU32MapGet(&self.slots, node_idx)) |slot| {
        self.vals[@intCast(usize, slot)] = v;
        return;
    }
    if (self.len >= self.capacity) { comptimeFoldTableGrow(self); }
    self.vals[self.len] = v;
    hash_mod.u32ToU32MapPut(&self.slots, node_idx, @intCast(u32, self.len));
    self.len += 1;
}

pub fn comptimeFoldTableGet(self: *ComptimeFoldTable, node_idx: u32) ?ComptimeVal {
    if (hash_mod.u32ToU32MapGet(&self.slots, node_idx)) |slot| {
        if (@intCast(usize, slot) < self.len) { return self.vals[@intCast(usize, slot)]; }
    }
    return null;
}

pub const ComptimeEval = struct {
    registry: *TypeRegistry,
    store: *AstStore,
    interner: *StringInterner,
    symbol_reg: *SymbolRegistry,
    size_of_id: u32,
    align_of_id: u32,
    offset_of_id: u32,
    bit_size_of_id: u32,
    bit_offset_of_id: u32,
    int_cast_id: u32,
    as_id: u32,
    float_cast_id: u32,
    int_to_float_id: u32,
    is_windows_id: u32,
    host_is_windows: bool,
    // Task 9D (Gap B): the enclosing function's local-const scope, consulted by
    // the ident_expr arm before the module symbol registry so a function-local
    // `const` participates in the fold (mirrors type_resolver's evalConstU32Full
    // variant (e)). null outside a function body or when the caller has no scope.
    local_consts: ?*type_resolver.LocalConstScope,
    // Task 11S (c): the fold pass may reject an out-of-range comptime
    // `@intCast` (error[3000]); null when no collector is available.
    diag: ?*diag_mod.DiagnosticCollector,
};

pub fn comptimeEvalInit(registry: *TypeRegistry, store: *AstStore, interner: *StringInterner, symbol_reg: *SymbolRegistry) ComptimeEval {
    var s_size: []const u8 = "@sizeOf";
    var s_align: []const u8 = "@alignOf";
    var s_intc: []const u8 = "@intCast";
    var intc_id = interner_mod.stringInternerIntern(interner, s_intc);
    var s_as: []const u8 = "@as";
    var as_id = interner_mod.stringInternerIntern(interner, s_as);
    var s_fc: []const u8 = "@floatCast";
    var fc_id = interner_mod.stringInternerIntern(interner, s_fc);
    var s_itf: []const u8 = "@intToFloat";
    var itf_id = interner_mod.stringInternerIntern(interner, s_itf);
    var size_id = interner_mod.stringInternerIntern(interner, s_size);
    var align_id = interner_mod.stringInternerIntern(interner, s_align);
    var s_off: []const u8 = "@offsetOf";
    var s_bitsz: []const u8 = "@bitSizeOf";
    var s_bitoff: []const u8 = "@bitOffsetOf";
    var off_id = interner_mod.stringInternerIntern(interner, s_off);
    var bitsz_id = interner_mod.stringInternerIntern(interner, s_bitsz);
    var bitoff_id = interner_mod.stringInternerIntern(interner, s_bitoff);
    var s_iw: []const u8 = "@isWindows";
    var iw_id = interner_mod.stringInternerIntern(interner, s_iw);
    return ComptimeEval{
        .registry = registry, .store = store, .interner = interner, .symbol_reg = symbol_reg,
        .size_of_id = size_id, .align_of_id = align_id, .int_cast_id = intc_id, .as_id = as_id,
        .float_cast_id = fc_id, .int_to_float_id = itf_id,
        .offset_of_id = off_id, .bit_size_of_id = bitsz_id, .bit_offset_of_id = bitoff_id,
        .is_windows_id = iw_id,
        .host_is_windows = false,
        .local_consts = null,
        .diag = null,
    };
}

// ---------------------------------------------------------------------------
// Task 2: arbitrary-precision comptime integer core.
//
// `ComptimeInt` is a fixed-cap sign-magnitude big integer: 8 little-endian
// u32 magnitude limbs (256 bits), a significant-limb count, and a sign bit.
// Invariants (re-established by `ciNormalize`): `len == 0` means zero and
// forces `neg == false` (`-0` normalizes to `0`); `mag[len-1] != 0` when
// `len > 0`; limbs at/above `len` are zero. Every arithmetic op is EXACT or
// declines (`false`/`null`) when the exact result needs more than 256
// magnitude bits -- no wrap, no truncation (Task 1 design §3).
// ---------------------------------------------------------------------------

pub fn ciZeroInt() ComptimeInt {
    return ComptimeInt{ .mag = [8]u32{ @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0) }, .len = @intCast(u8, 0), .neg = false };
}

pub fn ciFromU64(x: u64) ComptimeInt {
    var v = ciZeroInt();
    if (x == @intCast(u64, 0)) return v;
    v.mag[0] = @intCast(u32, x & @intCast(u64, 4294967295));
    v.mag[1] = @intCast(u32, (x >> @intCast(u64, 32)) & @intCast(u64, 4294967295));
    v.len = @intCast(u8, 1);
    if (v.mag[1] != @intCast(u32, 0)) { v.len = @intCast(u8, 2); }
    return v;
}

// 2^k as a ComptimeInt (k <= 255; used for range bounds with k <= 64).
fn ciPow2(k: u32) ComptimeInt {
    var v = ciZeroInt();
    var word: usize = @intCast(usize, k / @intCast(u32, 32));
    var bit: u32 = k % @intCast(u32, 32);
    v.mag[word] = @intCast(u32, 1) << @intCast(u32, bit);
    v.len = @intCast(u8, word + @intCast(usize, 1));
    return v;
}

fn ciSet(out: *ComptimeInt, src: ComptimeInt) void {
    var i: usize = 0;
    while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) { out.mag[i] = src.mag[i]; }
    out.len = src.len;
    out.neg = src.neg;
}

fn ciNormalize(v: *ComptimeInt) void {
    var l: usize = @intCast(usize, v.len);
    var done: bool = false;
    while (!done) {
        if (l == 0) { done = true; } else if (v.mag[l - 1] == @intCast(u32, 0)) { l -= 1; } else { done = true; }
    }
    v.len = @intCast(u8, l);
    if (l == 0) {
        v.neg = false;
        var i: usize = 0;
        while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) { v.mag[i] = @intCast(u32, 0); }
    }
}

pub fn ciIsZero(v: ComptimeInt) bool {
    return v.len == @intCast(u8, 0);
}

// -1 / 0 / 1 magnitude comparison.
fn ciMagCmp(a: ComptimeInt, b: ComptimeInt) i32 {
    if (a.len != b.len) {
        if (a.len < b.len) return @intCast(i32, -1);
        return @intCast(i32, 1);
    }
    var i: usize = @intCast(usize, a.len);
    while (i > 0) {
        i -= 1;
        if (a.mag[i] != b.mag[i]) {
            if (a.mag[i] < b.mag[i]) return @intCast(i32, -1);
            return @intCast(i32, 1);
        }
    }
    return @intCast(i32, 0);
}

// Task 3 (Task 1 §4): exact signedness-free three-way comparison (-1 / 0 / 1).
// `-0` is normalized to `0`, so (neg, mag) is a total order and no sign class
// or declared type is ever consulted.
pub fn ciCmp(a: ComptimeInt, b: ComptimeInt) i32 {
    if (a.neg != b.neg) {
        if (a.neg) return @intCast(i32, -1);
        return @intCast(i32, 1);
    }
    var m: i32 = ciMagCmp(a, b);
    if (a.neg) { m = @intCast(i32, 0) - m; }
    return m;
}

// Low 64 bits as a two's-complement pattern (for materialisation only).
pub fn ciToU64(v: ComptimeInt) u64 {
    var m: u64 = @intCast(u64, 0);
    if (v.len > @intCast(u8, 0)) { m = @intCast(u64, v.mag[0]); }
    if (v.len > @intCast(u8, 1)) { m = m | (@intCast(u64, v.mag[1]) << @intCast(u64, 32)); }
    if (v.neg) { m = @intCast(u64, 0) - m; }
    return m;
}

// Exact int -> f64 for @intToFloat (limb accumulation; documented residual:
// values above 2^53 may differ from a correctly-rounded conversion by 1 ulp).
fn ciToF64(v: ComptimeInt) f64 {
    var fv: f64 = 0.0;
    var i: usize = @intCast(usize, v.len);
    while (i > 0) {
        i -= 1;
        fv = fv * 4294967296.0 + @intToFloat(f64, v.mag[i]);
    }
    if (v.neg) { fv = -fv; }
    return fv;
}

fn ciIntVal(v: ComptimeInt) ComptimeVal {
    return ComptimeVal{ .v = v, .kind = KIND_INT, .float_bits = @intCast(u64, 0) };
}

fn ciBoolVal(b: bool) ComptimeVal {
    var v = ciZeroInt();
    if (b) { v = ciFromU64(@intCast(u64, 1)); }
    return ComptimeVal{ .v = v, .kind = KIND_BOOL, .float_bits = @intCast(u64, 0) };
}

fn ciMagAnd(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) void {
    var i: usize = 0;
    while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) { out.mag[i] = a.mag[i] & b.mag[i]; }
    out.len = @intCast(u8, COMPTIME_INT_LIMBS);
    out.neg = false;
    ciNormalize(out);
}

fn ciMagOr(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) void {
    var i: usize = 0;
    while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) { out.mag[i] = a.mag[i] | b.mag[i]; }
    out.len = @intCast(u8, COMPTIME_INT_LIMBS);
    out.neg = false;
    ciNormalize(out);
}

fn ciMagXor(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) void {
    var i: usize = 0;
    while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) { out.mag[i] = a.mag[i] ^ b.mag[i]; }
    out.len = @intCast(u8, COMPTIME_INT_LIMBS);
    out.neg = false;
    ciNormalize(out);
}

// 256-bit complement of a magnitude.
fn ciMagNot(a: ComptimeInt, out: *ComptimeInt) void {
    var i: usize = 0;
    while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) { out.mag[i] = ~a.mag[i]; }
    out.len = @intCast(u8, COMPTIME_INT_LIMBS);
    out.neg = false;
    ciNormalize(out);
}

// Magnitude addition; false on carry out of limb 7 (needs > 256 bits).
fn ciMagAddInto(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) bool {
    var carry: u64 = @intCast(u64, 0);
    var i: usize = 0;
    while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) {
        var av: u64 = @intCast(u64, 0);
        var bv: u64 = @intCast(u64, 0);
        if (i < @intCast(usize, a.len)) { av = @intCast(u64, a.mag[i]); }
        if (i < @intCast(usize, b.len)) { bv = @intCast(u64, b.mag[i]); }
        var s: u64 = av + bv + carry;
        out.mag[i] = @intCast(u32, s & @intCast(u64, 4294967295));
        carry = s >> @intCast(u64, 32);
    }
    if (carry != @intCast(u64, 0)) return false;
    out.len = @intCast(u8, COMPTIME_INT_LIMBS);
    out.neg = false;
    ciNormalize(out);
    return true;
}

// Magnitude subtraction; requires a >= b.
fn ciMagSubInto(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) bool {
    var borrow: u64 = @intCast(u64, 0);
    var i: usize = 0;
    while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) {
        var av: u64 = @intCast(u64, 0);
        var bv: u64 = @intCast(u64, 0);
        if (i < @intCast(usize, a.len)) { av = @intCast(u64, a.mag[i]); }
        if (i < @intCast(usize, b.len)) { bv = @intCast(u64, b.mag[i]); }
        var d: u64 = av + @intCast(u64, 4294967296) - bv - borrow;
        out.mag[i] = @intCast(u32, d & @intCast(u64, 4294967295));
        if (d >= @intCast(u64, 4294967296)) { borrow = @intCast(u64, 0); } else { borrow = @intCast(u64, 1); }
    }
    out.len = @intCast(u8, COMPTIME_INT_LIMBS);
    out.neg = false;
    ciNormalize(out);
    return true;
}

// a + 1; false if a is the cap (2^256 - 1).
fn ciMagAddOne(a: ComptimeInt, out: *ComptimeInt) bool {
    var one = ciFromU64(@intCast(u64, 1));
    return ciMagAddInto(a, one, out);
}

// a - 1; requires a > 0.
fn ciMagSubOne(a: ComptimeInt, out: *ComptimeInt) bool {
    var borrow: u32 = @intCast(u32, 1);
    var i: usize = 0;
    while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) {
        var av: u32 = a.mag[i];
        var d: u32 = av - borrow;
        if (av < borrow) { borrow = @intCast(u32, 1); } else { borrow = @intCast(u32, 0); }
        out.mag[i] = d;
    }
    out.len = @intCast(u8, COMPTIME_INT_LIMBS);
    out.neg = false;
    ciNormalize(out);
    return true;
}

pub fn ciAdd(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) bool {
    if (a.neg == b.neg) {
        if (!ciMagAddInto(a, b, out)) return false;
        out.neg = a.neg;
        if (out.len == @intCast(u8, 0)) { out.neg = false; }
        return true;
    }
    var m = ciMagCmp(a, b);
    if (m == 0) { ciSet(out, ciZeroInt()); return true; }
    if (m > 0) {
        if (!ciMagSubInto(a, b, out)) return false;
        out.neg = a.neg;
        return true;
    }
    if (!ciMagSubInto(b, a, out)) return false;
    out.neg = b.neg;
    return true;
}

pub fn ciSub(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) bool {
    var nb = b;
    if (!ciIsZero(nb)) { nb.neg = !nb.neg; } else { nb.neg = false; }
    return ciAdd(a, nb, out);
}

pub fn ciNeg(a: ComptimeInt, out: *ComptimeInt) bool {
    ciSet(out, a);
    if (!ciIsZero(a)) { out.neg = !a.neg; } else { out.neg = false; }
    return true;
}

// Schoolbook multiplication; false when the exact product needs > 256 bits.
pub fn ciMul(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) bool {
    if (ciIsZero(a) or ciIsZero(b)) { ciSet(out, ciZeroInt()); return true; }
    var acc: [16]u64 = undefined;
    var zi: usize = 0;
    while (zi < @intCast(usize, 16)) : (zi += 1) { acc[zi] = @intCast(u64, 0); }
    var alen: usize = @intCast(usize, a.len);
    var blen: usize = @intCast(usize, b.len);
    var i: usize = 0;
    while (i < alen) : (i += 1) {
        var carry: u64 = @intCast(u64, 0);
        var j: usize = 0;
        while (j < blen) : (j += 1) {
            var p: u64 = @intCast(u64, a.mag[i]) * @intCast(u64, b.mag[j]) + acc[i + j] + carry;
            acc[i + j] = p & @intCast(u64, 4294967295);
            carry = p >> @intCast(u64, 32);
        }
        var k: usize = i + blen;
        var c2: u64 = carry;
        while (c2 != @intCast(u64, 0)) {
            if (k >= @intCast(usize, 16)) return false;
            var s: u64 = acc[k] + c2;
            acc[k] = s & @intCast(u64, 4294967295);
            c2 = s >> @intCast(u64, 32);
            k += 1;
        }
    }
    var oi: usize = @intCast(usize, COMPTIME_INT_LIMBS);
    while (oi < @intCast(usize, 16)) : (oi += 1) {
        if (acc[oi] != @intCast(u64, 0)) return false;
    }
    i = 0;
    while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) { out.mag[i] = @intCast(u32, acc[i]); }
    out.len = @intCast(u8, COMPTIME_INT_LIMBS);
    out.neg = false;
    ciNormalize(out);
    out.neg = (a.neg != b.neg);
    if (out.len == @intCast(u8, 0)) { out.neg = false; }
    return true;
}

// Truncating division (Zig `/` and `%`): |q| = |a| / |b|, q.neg = a.neg xor
// b.neg; |r| = |a| mod |b|, r.neg = a.neg. False on division by zero.
// Binary long division over the 256 dividend bits with a 9-limb remainder.
pub fn ciDivMod(a: ComptimeInt, b: ComptimeInt, q: *ComptimeInt, r: *ComptimeInt) bool {
    if (ciIsZero(b)) return false;
    if (ciIsZero(a)) { ciSet(q, ciZeroInt()); ciSet(r, ciZeroInt()); return true; }
    if (ciMagCmp(a, b) < 0) {
        ciSet(q, ciZeroInt());
        ciSet(r, a);
        if (r.len == @intCast(u8, 0)) { r.neg = false; }
        return true;
    }
    var rem: [9]u32 = undefined;
    var k: usize = 0;
    while (k < @intCast(usize, 9)) : (k += 1) { rem[k] = @intCast(u32, 0); }
    var rem_len: usize = 0;
    var qm = ciZeroInt();
    var bit: usize = 256;
    while (bit > 0) {
        bit -= 1;
        var carry: u32 = @intCast(u32, 0);
        k = 0;
        while (k < @intCast(usize, 9)) : (k += 1) {
            var nv: u32 = (rem[k] << 1) | carry;
            carry = rem[k] >> 31;
            rem[k] = nv;
        }
        var word: usize = bit / 32;
        var pos: u32 = @intCast(u32, bit % 32);
        if (word < 8 and word < @intCast(usize, a.len)) {
            var abit: u32 = (a.mag[word] >> @intCast(u32, pos)) & @intCast(u32, 1);
            rem[0] = rem[0] | abit;
        }
        if (rem_len < 9 and rem[rem_len] != @intCast(u32, 0)) { rem_len += 1; }
        var ge: bool = false;
        if (rem_len == 9) {
            ge = true;
        } else if (rem_len > @intCast(usize, b.len)) {
            ge = true;
        } else if (rem_len == @intCast(usize, b.len)) {
            // Compare top-down: the FIRST differing limb is decisive, so stop.
            var diff_found: bool = false;
            var m: usize = @intCast(usize, b.len);
            while (m > 0 and !diff_found) {
                m -= 1;
                if (rem[m] != b.mag[m]) {
                    diff_found = true;
                    if (rem[m] < b.mag[m]) { ge = false; } else { ge = true; }
                }
            }
            if (!diff_found) { ge = true; }
        }
        if (ge) {
            var borrow: u32 = @intCast(u32, 0);
            var m2: usize = 0;
            while (m2 < @intCast(usize, 9)) : (m2 += 1) {
                var bv: u32 = @intCast(u32, 0);
                if (m2 < @intCast(usize, b.len)) { bv = b.mag[m2]; }
                var sub: u32 = bv + borrow;
                var diff: u32 = rem[m2] - sub;
                if (rem[m2] < sub) { borrow = @intCast(u32, 1); } else { borrow = @intCast(u32, 0); }
                rem[m2] = diff;
            }
            rem_len = 9;
            var found: bool = false;
            while (rem_len > 0 and !found) {
                if (rem[rem_len - 1] != @intCast(u32, 0)) { found = true; } else { rem_len -= 1; }
            }
            var qword: usize = bit / 32;
            var qpos: u32 = @intCast(u32, bit % 32);
            qm.mag[qword] = qm.mag[qword] | (@intCast(u32, 1) << @intCast(u32, qpos));
        }
    }
    ciSet(q, qm);
    q.len = @intCast(u8, COMPTIME_INT_LIMBS);
    ciNormalize(q);
    q.neg = (a.neg != b.neg);
    if (q.len == @intCast(u8, 0)) { q.neg = false; }
    var ri: usize = 0;
    while (ri < @intCast(usize, COMPTIME_INT_LIMBS)) : (ri += 1) { r.mag[ri] = rem[ri]; }
    r.len = @intCast(u8, COMPTIME_INT_LIMBS);
    r.neg = a.neg;
    ciNormalize(r);
    if (r.len == @intCast(u8, 0)) { r.neg = false; }
    return true;
}

// Bitwise ops with infinite-precision two's-complement semantics, reduced to
// magnitude ops via `~m == -m - 1`: -m <-> ~(m-1).
pub fn ciBitAnd(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) bool {
    if (!a.neg and !b.neg) { ciMagAnd(a, b, out); return true; }
    if (a.neg and b.neg) {
        var am = ciZeroInt();
        var bm = ciZeroInt();
        if (!ciMagSubOne(a, &am)) return false;
        if (!ciMagSubOne(b, &bm)) return false;
        var t = ciZeroInt();
        ciMagOr(am, bm, &t);
        if (!ciMagAddOne(t, out)) return false;
        out.neg = true;
        return true;
    }
    var m = ciZeroInt();
    var n = ciZeroInt();
    if (a.neg) { if (!ciMagSubOne(a, &m)) return false; ciSet(&n, b); } else { if (!ciMagSubOne(b, &m)) return false; ciSet(&n, a); }
    var notm = ciZeroInt();
    ciMagNot(m, &notm);
    ciMagAnd(notm, n, out);
    return true;
}

pub fn ciBitOr(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) bool {
    if (!a.neg and !b.neg) { ciMagOr(a, b, out); return true; }
    var m = ciZeroInt();
    var n = ciZeroInt();
    if (a.neg and b.neg) {
        if (!ciMagSubOne(a, &m)) return false;
        if (!ciMagSubOne(b, &n)) return false;
        var t = ciZeroInt();
        ciMagAnd(m, n, &t);
        if (!ciMagAddOne(t, out)) return false;
        out.neg = true;
        return true;
    }
    if (a.neg) { if (!ciMagSubOne(a, &m)) return false; ciSet(&n, b); } else { if (!ciMagSubOne(b, &m)) return false; ciSet(&n, a); }
    var notn = ciZeroInt();
    ciMagNot(n, &notn);
    var t2 = ciZeroInt();
    ciMagAnd(m, notn, &t2);
    if (!ciMagAddOne(t2, out)) return false;
    out.neg = true;
    return true;
}

pub fn ciBitXor(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) bool {
    if (!a.neg and !b.neg) { ciMagXor(a, b, out); return true; }
    var m = ciZeroInt();
    var n = ciZeroInt();
    if (a.neg and b.neg) {
        if (!ciMagSubOne(a, &m)) return false;
        if (!ciMagSubOne(b, &n)) return false;
        ciMagXor(m, n, out);
        return true;
    }
    if (a.neg) { if (!ciMagSubOne(a, &m)) return false; ciSet(&n, b); } else { if (!ciMagSubOne(b, &m)) return false; ciSet(&n, a); }
    var t = ciZeroInt();
    ciMagXor(m, n, &t);
    if (!ciMagAddOne(t, out)) return false;
    out.neg = true;
    return true;
}

// ~x = -x - 1 (Task 1 §4: Z98 keeps `~`, Zig 0.15.2 rejects it).
pub fn ciBitNot(a: ComptimeInt, out: *ComptimeInt) bool {
    if (a.neg) {
        if (!ciMagSubOne(a, out)) return false;
        out.neg = false;
        return true;
    }
    if (!ciMagAddOne(a, out)) return false;
    out.neg = true;
    return true;
}

// Exact `a << b` (multiply by 2^b); false for a negative/oversized count or
// when the exact result needs > 256 bits. A negative lhs keeps its sign.
pub fn ciShl(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) bool {
    if (b.neg and !ciIsZero(b)) return false;
    if (b.len > @intCast(u8, 1)) return false;
    if (ciIsZero(a)) { ciSet(out, ciZeroInt()); return true; }
    var sh: u32 = @intCast(u32, 0);
    if (b.len == @intCast(u8, 1)) { sh = b.mag[0]; }
    if (sh >= @intCast(u32, 256)) return false;
    var word: usize = @intCast(usize, sh / @intCast(u32, 32));
    var bits: u32 = sh % @intCast(u32, 32);
    var tmp: [8]u64 = undefined;
    var i: usize = 0;
    while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) {
        var src: u64 = @intCast(u64, 0);
        if (i < @intCast(usize, a.len)) { src = @intCast(u64, a.mag[i]); }
        tmp[i] = src << @intCast(u64, bits);
        // Review fix (Critical): a nonzero shifted source limb whose target
        // starts at or beyond limb 8 is never consumed by the accumulation
        // below, so it must decline here -- otherwise the result is silently
        // truncated (e.g. `(1 << 200) << 64`, `(1 << 32) << 224`).
        if (tmp[i] != @intCast(u64, 0) and i + word >= @intCast(usize, COMPTIME_INT_LIMBS)) return false;
    }
    var carry: u64 = @intCast(u64, 0);
    i = 0;
    while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) {
        var val: u64 = carry;
        if (i >= word) {
            var si: usize = i - word;
            if (si < @intCast(usize, COMPTIME_INT_LIMBS)) { val += tmp[si]; }
        }
        out.mag[i] = @intCast(u32, val & @intCast(u64, 4294967295));
        carry = val >> @intCast(u64, 32);
    }
    if (carry != @intCast(u64, 0)) return false;
    out.len = @intCast(u8, COMPTIME_INT_LIMBS);
    out.neg = false;
    ciNormalize(out);
    out.neg = a.neg;
    if (out.len == @intCast(u8, 0)) { out.neg = false; }
    return true;
}

// Floor right shift (arithmetic): a >> b = floor(a / 2^b). False for a
// negative/oversized count; the result never exceeds the cap.
pub fn ciShr(a: ComptimeInt, b: ComptimeInt, out: *ComptimeInt) bool {
    if (b.neg and !ciIsZero(b)) return false;
    if (b.len > @intCast(u8, 1)) return false;
    if (ciIsZero(a)) { ciSet(out, ciZeroInt()); return true; }
    var sh: u32 = @intCast(u32, 0);
    if (b.len == @intCast(u8, 1)) { sh = b.mag[0]; }
    if (sh >= @intCast(u32, 256)) {
        if (a.neg) { ciSet(out, ciFromU64(@intCast(u64, 1))); out.neg = true; } else { ciSet(out, ciZeroInt()); }
        return true;
    }
    var word: usize = @intCast(usize, sh / @intCast(u32, 32));
    var bits: u32 = sh % @intCast(u32, 32);
    var sticky: bool = false;
    var i: usize = 0;
    while (i < word) : (i += 1) {
        if (i < @intCast(usize, a.len) and a.mag[i] != @intCast(u32, 0)) { sticky = true; }
    }
    if (bits > @intCast(u32, 0) and word < @intCast(usize, a.len)) {
        var mask: u32 = (@intCast(u32, 1) << @intCast(u32, bits)) - @intCast(u32, 1);
        if ((a.mag[word] & mask) != @intCast(u32, 0)) { sticky = true; }
    }
    i = 0;
    while (i < @intCast(usize, COMPTIME_INT_LIMBS)) : (i += 1) {
        var idx: usize = i + word;
        var lo: u64 = @intCast(u64, 0);
        if (idx < @intCast(usize, a.len)) { lo = @intCast(u64, a.mag[idx]) >> @intCast(u64, bits); }
        var hi: u64 = @intCast(u64, 0);
        if (bits > @intCast(u32, 0) and idx + 1 < @intCast(usize, a.len)) {
            hi = @intCast(u64, a.mag[idx + 1]) << @intCast(u64, 32 - bits);
        }
        out.mag[i] = @intCast(u32, (lo | hi) & @intCast(u64, 4294967295));
    }
    out.len = @intCast(u8, COMPTIME_INT_LIMBS);
    out.neg = false;
    ciNormalize(out);
    if (a.neg) {
        if (sticky) {
            var carry: u64 = @intCast(u64, 1);
            var k2: usize = 0;
            while (k2 < @intCast(usize, COMPTIME_INT_LIMBS)) : (k2 += 1) {
                var s: u64 = @intCast(u64, out.mag[k2]) + carry;
                out.mag[k2] = @intCast(u32, s & @intCast(u64, 4294967295));
                carry = s >> @intCast(u64, 32);
                if (carry == @intCast(u64, 0)) { k2 = @intCast(usize, COMPTIME_INT_LIMBS); }
            }
            if (carry != @intCast(u64, 0)) return false;
            out.len = @intCast(u8, COMPTIME_INT_LIMBS);
            ciNormalize(out);
        }
        if (out.len != @intCast(u8, 0)) { out.neg = true; }
    }
    return true;
}

// Task 3 (Task 1 §5.4): exact arithmetic/bitwise/shift fold with the operand
// peer-fit rule — the rule that keeps Zig-rejected shapes like
// `const u: u8 = 200; (u - 300) < 0` rejected. Compute the operand peer type
// P: one operand declared integer T + the other untyped -> P = T; both declared
// -> the sema width rule (wider wins, ties keep lhs); otherwise no P. Then:
// (1) each UNTYPED operand's exact value must fit P (Zig: "type 'u8' cannot
// represent integer value '300'"), and (2) the exact result must fit P (Zig:
// "overflow of integer type 'u64' with value ..."). A failed fit makes the fold
// decline (`null`), which preserves today's verdicts: a comptime-required
// position rejects, a runtime position keeps the runtime path. Comparisons are
// exempt (see `comptimeEvalCompare`).
fn comptimeEvalBinOp(self: *ComptimeEval, node_idx: u32, op_kind: AstKind, depth: u32) ?ComptimeVal {
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    var lhs = comptimeEvalEvaluateDepth(self, node.child_0, depth);
    var rhs = comptimeEvalEvaluateDepth(self, node.child_1, depth);
    if (lhs) |l| {
        if (rhs) |r| {
            if (l.kind != KIND_INT or r.kind != KIND_INT) return null;
            var peer_tid: u32 = @intCast(u32, 0);
            var lt = comptimeEvalOperandType(self, node.child_0);
            var rt = comptimeEvalOperandType(self, node.child_1);
            if (lt) |lti| {
                if (rt) |rti| {
                    peer_tid = comptimeEvalWiderIntType(self, lti, rti);
                } else {
                    peer_tid = lti;
                }
            } else {
                if (rt) |rti2| { peer_tid = rti2; }
            }
            if (peer_tid != @intCast(u32, 0)) {
                if (lt == null) {
                    if (!comptimeIntFitsType(self.registry, l.v, peer_tid)) return null;
                }
                if (rt == null) {
                    if (!comptimeIntFitsType(self.registry, r.v, peer_tid)) return null;
                }
            }
            var res = ciZeroInt();
            if (op_kind == AstKind.add) {
                if (!ciAdd(l.v, r.v, &res)) return null;
            } else if (op_kind == AstKind.sub) {
                if (!ciSub(l.v, r.v, &res)) return null;
            } else if (op_kind == AstKind.mul) {
                if (!ciMul(l.v, r.v, &res)) return null;
            } else if (op_kind == AstKind.div) {
                var rem = ciZeroInt();
                if (!ciDivMod(l.v, r.v, &res, &rem)) return null;
            } else if (op_kind == AstKind.mod_op) {
                var q2 = ciZeroInt();
                if (!ciDivMod(l.v, r.v, &q2, &res)) return null;
            } else if (op_kind == AstKind.bit_and) {
                if (!ciBitAnd(l.v, r.v, &res)) return null;
            } else if (op_kind == AstKind.bit_or) {
                if (!ciBitOr(l.v, r.v, &res)) return null;
            } else if (op_kind == AstKind.bit_xor) {
                if (!ciBitXor(l.v, r.v, &res)) return null;
            } else if (op_kind == AstKind.shl) {
                if (!ciShl(l.v, r.v, &res)) return null;
            } else if (op_kind == AstKind.shr) {
                if (!ciShr(l.v, r.v, &res)) return null;
            } else {
                return null;
            }
            if (peer_tid != @intCast(u32, 0)) {
                if (!comptimeIntFitsType(self.registry, res, peer_tid)) return null;
            }
            return ciIntVal(res);
        }
    }
    return null;
}

// Task 3 (Task 1 §4 compare row): signedness-free comparison
// (`==`/`!=`/`<`/`<=`/`>`/`>=`) of two exact comptime integers. `ComptimeInt`
// carries only magnitude+sign, so `(umax - 1) > 0`, `-1 < U64MAX`, and
// arithmetic-derived conditions fold exactly like Zig's `comptime_int`; bools
// compare as 0/1 (`-0` is normalized to `0`). The Task 9D sign-class
// machinery, the declared-type lookup, and the 64-bit `ciValToOldBits` bridge
// are all gone. Comparisons deliberately do NOT apply the arithmetic peer-fit
// rule (Task 1 §5.4): the oracle accepts `const u: u8 = 200; u > -1` (true) and
// `u > 300` (false), so a comparison is mathematical and range rulings belong
// to the arithmetic folds beneath it.
//
// Task 9 (Part II): an all-integer/bool comparison stays on the exact `ciCmp`
// path; any float operand goes to `comptimeEvalCompareFloat` (below).
fn comptimeEvalCompare(self: *ComptimeEval, node_idx: u32, op_kind: AstKind, depth: u32) ?ComptimeVal {
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    var lhs = comptimeEvalEvaluateDepth(self, node.child_0, depth);
    var rhs = comptimeEvalEvaluateDepth(self, node.child_1, depth);
    if (lhs) |l| {
        if (rhs) |r| {
            if (l.kind != KIND_FLOAT and r.kind != KIND_FLOAT) {
                var c: i32 = ciCmp(l.v, r.v);
                var res: bool = false;
                if (op_kind == AstKind.cmp_eq) res = c == @intCast(i32, 0);
                if (op_kind == AstKind.cmp_ne) res = c != @intCast(i32, 0);
                if (op_kind == AstKind.cmp_lt) res = c < @intCast(i32, 0);
                if (op_kind == AstKind.cmp_le) res = c <= @intCast(i32, 0);
                if (op_kind == AstKind.cmp_gt) res = c > @intCast(i32, 0);
                if (op_kind == AstKind.cmp_ge) res = c >= @intCast(i32, 0);
                return ciBoolVal(res);
            }
        }
    }
    return comptimeEvalCompareFloat(self, node_idx, op_kind, depth);
}

// Task 9 (Part II): float comparison folding at the existing f64 precision.
// The float sub-evaluator (`comptimeEvalFloat`) supplies each float operand at
// f64 precision (a typed `f32` rounds through f32 first, matching the C
// `float` the emitted program holds; an untyped literal is the f64 the runtime
// comparison uses). An INTEGER operand participates only when it is EXACTLY
// representable in the comparison's peer precision (<= 53 significand bits for
// an f64 / `comptime_float` peer, <= 24 for an f32 peer), so the folded
// verdict is the mathematical comparison official Zig folds and cannot
// disagree with the emitted runtime comparison of the same values (the
// integer->float coercion is then exact). Any other shape declines (no fold),
// preserving the pre-Task-9 verdict.
//
// Oracle-checked peer rules (Zig 0.15.2): a typed `f64` operand makes the peer
// f64 (an `f32` operand widens exactly); otherwise a typed `f32` operand makes
// the peer f32, so an UNTYPED (`comptime_float`) operand is folded only when
// its f64 value is exactly f32-representable (f64 values that are not exact in
// f32 are NOT rounded: Z98's emitted C widens to double, so rounding would
// fold a verdict the runtime never computes); with no typed float operand the
// comparison is comptime_float, evaluated here at f64 (the documented
// precision residual).
fn comptimeEvalCompareFloat(self: *ComptimeEval, node_idx: u32, op_kind: AstKind, depth: u32) ?ComptimeVal {
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    var lop = comptimeEvalCompareOperand(self, node.child_0, depth);
    var rop = comptimeEvalCompareOperand(self, node.child_1, depth);
    if (lop) |l| {
        if (rop) |r| {
            if (!l.ok or !r.ok) return null;
            if (!l.is_float and !r.is_float) return null;
            if (l.is_bool or r.is_bool) return null;
            var has_f64: bool = (l.is_float and l.ftype == type_mod.TYPE_F64) or (r.is_float and r.ftype == type_mod.TYPE_F64);
            var has_f32: bool = (l.is_float and l.ftype == type_mod.TYPE_F32) or (r.is_float and r.ftype == type_mod.TYPE_F32);
            if (has_f64 or !has_f32) {
                if (!l.is_float and l.sig_bits > F64_SIGNIFICAND_BITS) return null;
                if (!r.is_float and r.sig_bits > F64_SIGNIFICAND_BITS) return null;
            } else {
                if (l.is_float and l.ftype == @intCast(u32, 0) and !comptimeEvalF64IsF32Exact(l.fval)) return null;
                if (r.is_float and r.ftype == @intCast(u32, 0) and !comptimeEvalF64IsF32Exact(r.fval)) return null;
                if (!l.is_float and l.sig_bits > F32_SIGNIFICAND_BITS) return null;
                if (!r.is_float and r.sig_bits > F32_SIGNIFICAND_BITS) return null;
            }
            var lv: f64 = l.fval;
            var rv: f64 = r.fval;
            var res: bool = false;
            if (op_kind == AstKind.cmp_eq) res = lv == rv;
            if (op_kind == AstKind.cmp_ne) res = lv != rv;
            if (op_kind == AstKind.cmp_lt) res = lv < rv;
            if (op_kind == AstKind.cmp_le) res = lv <= rv;
            if (op_kind == AstKind.cmp_gt) res = lv > rv;
            if (op_kind == AstKind.cmp_ge) res = lv >= rv;
            return ciBoolVal(res);
        }
    }
    return null;
}

// Task 9: one comparison operand for the float path: the operand's f64 value,
// whether it is float-valued (as opposed to int/bool), its declared float type
// (TYPE_F32 / TYPE_F64; 0 = untyped `comptime_float`), and -- for an integer
// operand -- its magnitude's significant-bit count so the caller can require
// exact representability in the peer's significand.
const CmpFloatOperand = struct {
    ok: bool,
    is_float: bool,
    is_bool: bool,
    ftype: u32,
    fval: f64,
    sig_bits: u32,
};

fn comptimeEvalCompareOperand(self: *ComptimeEval, node_idx: u32, depth: u32) ?CmpFloatOperand {
    var op = CmpFloatOperand{ .ok = false, .is_float = false, .is_bool = false, .ftype = @intCast(u32, 0), .fval = 0.0, .sig_bits = @intCast(u32, 0) };
    if (comptimeEvalEvaluateDepth(self, node_idx, depth)) |cv| {
        if (cv.kind == KIND_FLOAT) {
            op.ok = true;
            op.is_float = true;
            op.ftype = comptimeEvalFloatOperandType(self, node_idx);
            op.fval = comptimeEvalFloatBits(cv);
            return op;
        }
        if (cv.kind == KIND_BOOL) {
            op.ok = true;
            op.is_bool = true;
            if (!ciIsZero(cv.v)) { op.fval = 1.0; }
            return op;
        }
        op.ok = true;
        op.sig_bits = ciSignificantBits(cv.v);
        op.fval = ciToF64(cv.v);
        return op;
    }
    if (comptimeEvalFloat(self, node_idx, depth)) |fv| {
        op.ok = true;
        op.is_float = true;
        op.ftype = comptimeEvalFloatOperandType(self, node_idx);
        op.fval = fv;
    }
    return op;
}

// Task 9: reinterpret a folded float `ComptimeVal`'s f64 bit pattern.
fn comptimeEvalFloatBits(cv: ComptimeVal) f64 {
    var fb: u64 = cv.float_bits;
    var fp: *f64 = @ptrCast(*f64, &fb);
    return fp.*;
}

// Task 9: significant bits of a `ComptimeInt` magnitude (0 for zero). A value
// with <= 53 (f64) or <= 24 (f32) significant bits is exactly representable in
// that IEEE binary format (the 256-bit cap is far inside the exponent range).
fn ciSignificantBits(v: ComptimeInt) u32 {
    if (v.len == @intCast(u8, 0)) return @intCast(u32, 0);
    var bits: u32 = @intCast(u32, 0);
    var top: u32 = v.mag[@intCast(usize, v.len - @intCast(u8, 1))];
    while (top != @intCast(u32, 0)) {
        bits += @intCast(u32, 1);
        top = top >> @intCast(u32, 1);
    }
    var i: u8 = @intCast(u8, 0);
    while (i < v.len) : (i += @intCast(u8, 1)) {
        var limb: u32 = v.mag[@intCast(usize, i)];
        if (limb == @intCast(u32, 0)) {
            bits -= @intCast(u32, 32);
        } else {
            while ((limb & @intCast(u32, 1)) == @intCast(u32, 0)) {
                bits -= @intCast(u32, 1);
                limb = limb >> @intCast(u32, 1);
            }
            return bits;
        }
    }
    return bits;
}

// Task 9: is the f64 value exactly an f32 value (round-trip)?
fn comptimeEvalF64IsF32Exact(x: f64) bool {
    var x32: f32 = @floatCast(f32, x);
    var back: f64 = @floatCast(f64, x32);
    return back == x;
}

// Task 9: the declared float type of a comparison operand -- TYPE_F32 /
// TYPE_F64 for a typed shape, 0 for an untyped `comptime_float` or a non-float
// shape (the caller knows which from the evaluated value). Mirrors
// `comptimeEvalOperandTypeDepth` for the float kinds and consults the same
// function-local const scope.
fn comptimeEvalFloatOperandType(self: *ComptimeEval, node_idx: u32) u32 {
    return comptimeEvalFloatOperandTypeDepth(self, node_idx, @intCast(u32, 0));
}

fn comptimeEvalFloatOperandTypeDepth(self: *ComptimeEval, node_idx: u32, depth: u32) u32 {
    if (node_idx == @intCast(u32, 0)) return @intCast(u32, 0);
    if (depth >= @intCast(u32, 16)) return @intCast(u32, 0);
    var idx = node_idx;
    var guard: u32 = @intCast(u32, 0);
    while (guard < @intCast(u32, 32)) : (guard += @intCast(u32, 1)) {
        var wn = ast_mod.astStoreNodeAt(self.store, idx);
        if (wn.kind == AstKind.paren_expr) { idx = wn.child_0; } else { break; }
    }
    var node = ast_mod.astStoreNodeAt(self.store, idx);
    if (node.kind == AstKind.float_literal) return @intCast(u32, 0);
    if (node.kind == AstKind.negate) return comptimeEvalFloatOperandTypeDepth(self, node.child_0, depth + @intCast(u32, 1));
    if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(self.store, idx);
        if (self.local_consts) |lcs| {
            if (type_resolver.localConstScopeLookup(lcs, name_id)) |l_decl_node| {
                var l_decl = ast_mod.astStoreNodeAt(self.store, l_decl_node);
                if (l_decl.child_0 != @intCast(u32, 0)) {
                    if (comptimeEvalResolveTypeArg(self, l_decl.child_0)) |lt| {
                        if (lt == type_mod.TYPE_F32 or lt == type_mod.TYPE_F64) return lt;
                    }
                    return @intCast(u32, 0);
                }
                if (l_decl.child_1 != @intCast(u32, 0)) {
                    return comptimeEvalFloatOperandTypeDepth(self, l_decl.child_1, depth + @intCast(u32, 1));
                }
                return @intCast(u32, 0);
            }
        }
        var mi: usize = 0;
        while (mi < @intCast(usize, self.symbol_reg.tables_len)) : (mi += 1) {
            var c_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbol_reg, @intCast(u32, mi), name_id);
            if (c_sym) |cs| {
                if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                    var c_decl = ast_mod.astStoreNodeAt(self.store, cs.decl_node);
                    if (c_decl.child_0 != @intCast(u32, 0)) {
                        if (comptimeEvalResolveTypeArg(self, c_decl.child_0)) |t| {
                            if (t == type_mod.TYPE_F32 or t == type_mod.TYPE_F64) return t;
                        }
                        return @intCast(u32, 0);
                    }
                    if (c_decl.child_1 != @intCast(u32, 0)) {
                        return comptimeEvalFloatOperandTypeDepth(self, c_decl.child_1, depth + @intCast(u32, 1));
                    }
                }
            }
        }
        return @intCast(u32, 0);
    }
    if (node.kind == AstKind.builtin_call) {
        if (node.child_0 == self.int_to_float_id or node.child_0 == self.float_cast_id) {
            if (comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, idx, @intCast(u32, 0)))) |t2| {
                if (t2 == type_mod.TYPE_F32 or t2 == type_mod.TYPE_F64) return t2;
            }
        }
        return @intCast(u32, 0);
    }
    return @intCast(u32, 0);
}

// Task 9D: fold `and`/`or`/`!` on comptime bools. `and`/`or` short-circuit:
// when the lhs folds, a decisive lhs (`0` for `and`, `1` for `or`) returns
// without evaluating the rhs; when the lhs does NOT fold, a decisive RHS still
// decides (`<runtime> or true` -> true, `<runtime> and false` -> false) without
// requiring the lhs — matching Zig's comptime-known-true acceptance (fix round
// 1). Any other operand that does not fold, or is not bool-kind, yields null.
fn comptimeEvalLogical(self: *ComptimeEval, node_idx: u32, op_kind: AstKind, depth: u32) ?ComptimeVal {
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    var lhs = comptimeEvalEvaluateDepth(self, node.child_0, depth);
    if (op_kind == AstKind.bool_not) {
        if (lhs) |l| {
            if (l.kind != KIND_BOOL) return null;
            return ciBoolVal(ciIsZero(l.v));
        }
        return null;
    }
    if (op_kind == AstKind.bool_and) {
        if (lhs) |l| {
            if (l.kind != KIND_BOOL) return null;
            if (ciIsZero(l.v)) return ciBoolVal(false);
            var rhs_a = comptimeEvalEvaluateDepth(self, node.child_1, depth);
            if (rhs_a) |ra| {
                if (ra.kind != KIND_BOOL) return null;
                return ciBoolVal(!ciIsZero(ra.v));
            }
            return null;
        }
        // lhs does not fold: a false rhs decides the conjunction.
        if (comptimeEvalEvaluateDepth(self, node.child_1, depth)) |ra2| {
            if (ra2.kind != KIND_BOOL) return null;
            if (ciIsZero(ra2.v)) return ciBoolVal(false);
        }
        return null;
    }
    if (op_kind == AstKind.bool_or) {
        if (lhs) |l| {
            if (l.kind != KIND_BOOL) return null;
            if (!ciIsZero(l.v)) return ciBoolVal(true);
            var rhs_o = comptimeEvalEvaluateDepth(self, node.child_1, depth);
            if (rhs_o) |ro| {
                if (ro.kind != KIND_BOOL) return null;
                return ciBoolVal(!ciIsZero(ro.v));
            }
            return null;
        }
        // lhs does not fold: a true rhs decides the disjunction.
        if (comptimeEvalEvaluateDepth(self, node.child_1, depth)) |ro2| {
            if (ro2.kind != KIND_BOOL) return null;
            if (!ciIsZero(ro2.v)) return ciBoolVal(true);
        }
        return null;
    }
    return null;
}

// Task 3 (Task 1 §5.4 / §8 risk 3): the integer type a binop operand receives
// in sema, or null when the operand is untyped (an int/char/bool literal, or a
// shape whose type cannot be derived). This replaces the Task 9D
// `comptimeEvalOperandDeclaredSigned` (signedness is never recovered any more);
// the only consumer is the arithmetic peer-fit rule in `comptimeEvalBinOp`.
// Leaves: an ident's declared integer type (function-local const scope first,
// Task 9D Gap B, then the module symbol tables); `@intCast`/`@as` integer
// targets. Compound expressions MIRROR sema's typing so the fold cannot
// disagree with the runtime type: `negate`/`bit_not` propagate their operand
// (sema :1525-1541), and the integer binops apply the INT_LIT/numeric arm plus
// the wider-wins/ties-lhs width rule (sema :1440-1449, :1462-1463) via
// `comptimeEvalWiderIntType`. The recursion matters: for `((u - 1) - 300)` with
// `u: u8` the outer sub's sema type is `u8`, so the peer fit must see `u8` and
// decline -- without it the fold would accept a result the runtime arithmetic
// wraps (a silent miscompile).
fn comptimeEvalOperandType(self: *ComptimeEval, node_idx: u32) ?u32 {
    return comptimeEvalOperandTypeDepth(self, node_idx, @intCast(u32, 0));
}

fn comptimeEvalOperandTypeDepth(self: *ComptimeEval, node_idx: u32, depth: u32) ?u32 {
    if (node_idx == @intCast(u32, 0)) return null;
    if (depth >= @intCast(u32, 16)) return null;
    var idx = node_idx;
    var guard: u32 = 0;
    while (guard < @intCast(u32, 32)) : (guard += 1) {
        var wn = ast_mod.astStoreNodeAt(self.store, idx);
        if (wn.kind == AstKind.paren_expr) { idx = wn.child_0; } else { break; }
    }
    var node = ast_mod.astStoreNodeAt(self.store, idx);
    if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(self.store, idx);
        if (self.local_consts) |lcs| {
            if (type_resolver.localConstScopeLookup(lcs, name_id)) |l_decl_node| {
                var l_decl = ast_mod.astStoreNodeAt(self.store, l_decl_node);
                if (l_decl.child_0 != @intCast(u32, 0)) {
                    if (comptimeEvalResolveTypeArg(self, l_decl.child_0)) |lt| {
                        if (type_mod.typeRegistryIsInteger(self.registry, lt)) return lt;
                    }
                } else if (l_decl.child_1 != @intCast(u32, 0)) {
                    // Task 3 fix round 1 (Important): an UNANNOTATED const has
                    // no declared type, but sema types the name by its
                    // initializer (`const c = @as(u8, 200)` is a u8). Recurse
                    // into the init so the mirror sees the same type (the
                    // deleted `comptimeEvalSignClass` did this too); without it
                    // `(c + 300) == 500` folded and accepted a Zig-rejected
                    // program.
                    return comptimeEvalOperandTypeDepth(self, l_decl.child_1, depth + @intCast(u32, 1));
                }
            }
        }
        var mi: usize = 0;
        while (mi < @intCast(usize, self.symbol_reg.tables_len)) : (mi += 1) {
            var c_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbol_reg, @intCast(u32, mi), name_id);
            if (c_sym) |cs| {
                if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                    var c_decl = ast_mod.astStoreNodeAt(self.store, cs.decl_node);
                    if (c_decl.child_0 != @intCast(u32, 0)) {
                        if (comptimeEvalResolveTypeArg(self, c_decl.child_0)) |t| {
                            if (type_mod.typeRegistryIsInteger(self.registry, t)) return t;
                        }
                    } else if (c_decl.child_1 != @intCast(u32, 0)) {
                        return comptimeEvalOperandTypeDepth(self, c_decl.child_1, depth + @intCast(u32, 1));
                    }
                }
            }
        }
        return null;
    }
    if (node.kind == AstKind.builtin_call) {
        if (node.child_0 == self.int_cast_id or node.child_0 == self.as_id) {
            if (comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, idx, @intCast(u32, 0)))) |t2| {
                if (type_mod.typeRegistryIsInteger(self.registry, t2)) return t2;
            }
        }
        return null;
    }
    if (node.kind == AstKind.negate or node.kind == AstKind.bit_not) {
        return comptimeEvalOperandTypeDepth(self, node.child_0, depth + @intCast(u32, 1));
    }
    if (node.kind == AstKind.add or node.kind == AstKind.sub or
        node.kind == AstKind.mul or node.kind == AstKind.div or
        node.kind == AstKind.mod_op or node.kind == AstKind.bit_and or
        node.kind == AstKind.bit_or or node.kind == AstKind.bit_xor or
        node.kind == AstKind.shl or node.kind == AstKind.shr) {
        var lt = comptimeEvalOperandTypeDepth(self, node.child_0, depth + @intCast(u32, 1));
        var rt = comptimeEvalOperandTypeDepth(self, node.child_1, depth + @intCast(u32, 1));
        if (lt) |ltv| {
            if (rt) |rtv| { return comptimeEvalWiderIntType(self, ltv, rtv); }
            return ltv;
        }
        return rt;
    }
    return null;
}

// Task 3 (Task 1 §5.4): the peer type of TWO declared integer operand types —
// mirror of `semanticAnalyzerResolveArithmetic`'s integer width rule (the
// wider type wins; a tie keeps the lhs). Both ids are integer types.
fn comptimeEvalWiderIntType(self: *ComptimeEval, lt: u32, rt: u32) u32 {
    if (lt == rt) return lt;
    var lw: u8 = type_mod.typeRegistryIntWidthBits(self.registry, lt);
    var rw: u8 = type_mod.typeRegistryIntWidthBits(self.registry, rt);
    if (lw >= rw) return lt;
    return rt;
}

fn comptimeEvalResolveTypeArg(self: *ComptimeEval, node_idx: u32) ?u32 {
    if (node_idx == @intCast(u32, 0)) return null;
    var env = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbol_reg, .interner = self.interner, .module_id = type_resolver.MODULE_ID_NONE, .source_file_id = @intCast(u32, 0), .diag = null, .local_consts = null, .local_types = null };
    var tid = type_resolver.resolveTypeExprFull(&env, node_idx, @intCast(u32, 0));
    if (tid == type_mod.TYPE_UNDEFINED) return null;
    return tid;
}

// Task 2: exact range check of a `ComptimeInt` against an integer type `t`.
// Replaces the old 64-bit `comptimeValFitsType` sign-class heuristic: the exact
// value distinguishes `-1` from `18446744073709551615`, so a negative source
// never fits an unsigned target and the signed/unsigned boundaries are exact.
// Task 11S (c) semantics are preserved: an out-of-range `@intCast`/`@as` still
// emits error[3000] and stops folding.
//
// Task 4: registry-based (Task 1 §5.1) so the lowerer can range-check a
// materialised fold without constructing an evaluator.
pub fn comptimeIntFitsType(registry: *TypeRegistry, v: ComptimeInt, t: u32) bool {
    if (@intCast(usize, t) >= registry.types_len) return false;
    if (!type_mod.typeRegistryIsInteger(registry, t)) return false;
    var wb: u32 = @intCast(u32, type_mod.typeRegistryIntWidthBits(registry, t));
    if (wb == @intCast(u32, 0)) return false;
    var tsig: bool = type_mod.typeRegistryIntIsSigned(registry, t);
    if (v.neg) {
        if (!tsig) return false;
        var lim = ciPow2(wb - @intCast(u32, 1));
        return ciMagCmp(v, lim) <= 0;
    }
    if (tsig) {
        var lim2 = ciPow2(wb - @intCast(u32, 1));
        return ciMagCmp(v, lim2) < 0;
    }
    var lim3 = ciPow2(wb);
    return ciMagCmp(v, lim3) < 0;
}

// Task 4 (Task 1 §5.1): the two's-complement pattern of an already-fit value.
pub fn comptimeIntMaterialize(v: ComptimeInt) u64 {
    return ciToU64(v);
}

// Task 4: does the exact value fit the untyped 64-bit window [i64 min, u64 max]?
pub fn comptimeIntFits64(v: ComptimeInt) bool {
    if (v.neg) {
        var lim = ciPow2(@intCast(u32, 63));
        return ciMagCmp(v, lim) <= 0;
    }
    var lim2 = ciPow2(@intCast(u32, 64));
    return ciMagCmp(v, lim2) < 0;
}

// Task 4 (Task 1 §5.2 untyped row): choose the materialisation temp type for an
// UNTYPED (comptime_int) slot by exact value: negative -> signed (I32/I64),
// non-negative -> the narrowest fitting type (I32/U32/I64/U64). null when the
// value exceeds the 64-bit window (the caller emits error[3000]).
pub fn comptimeIntUntypedType(v: ComptimeInt) ?u32 {
    var b31 = ciPow2(@intCast(u32, 31));
    var b32 = ciPow2(@intCast(u32, 32));
    var b63 = ciPow2(@intCast(u32, 63));
    var b64 = ciPow2(@intCast(u32, 64));
    if (v.neg) {
        if (ciMagCmp(v, b31) <= 0) return type_mod.TYPE_I32;
        if (ciMagCmp(v, b63) <= 0) return type_mod.TYPE_I64;
        return null;
    }
    if (ciMagCmp(v, b31) < 0) return type_mod.TYPE_I32;
    if (ciMagCmp(v, b32) < 0) return type_mod.TYPE_U32;
    if (ciMagCmp(v, b63) < 0) return type_mod.TYPE_I64;
    if (ciMagCmp(v, b64) < 0) return type_mod.TYPE_U64;
    return null;
}

// Task 2 helper retained for the unit tests (Task 4 moved the production fold
// table to exact `ComptimeVal`s -- see `ComptimeFoldTable`). Materialise a
// folded ComptimeVal to a 64-bit pattern: bools as 0/1, floats as their f64 bit
// pattern, integers as their two's-complement pattern when the exact value fits
// [i64 min, u64 max]; otherwise null.
pub fn comptimeValStoreU64(cv: ComptimeVal) ?u64 {
    if (cv.kind == KIND_FLOAT) return cv.float_bits;
    if (cv.kind == KIND_BOOL) {
        if (ciIsZero(cv.v)) return @intCast(u64, 0);
        return @intCast(u64, 1);
    }
    if (!comptimeIntFits64(cv.v)) return null;
    return ciToU64(cv.v);
}


fn comptimeEvalBuiltin(self: *ComptimeEval, node_idx: u32, depth: u32) ?ComptimeVal {
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    if (node.child_0 == self.size_of_id) {
        var tid = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
        if (tid) |t| {
            var ty = self.registry.types_items[@intCast(usize, t)];
            if (ty.state == @intCast(u8, 2)) return ciIntVal(ciFromU64(@intCast(u64, ty.size)));
        }
        return null;
    }
    if (node.child_0 == self.align_of_id) {
        var tid = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
        if (tid) |t| {
            var ty = self.registry.types_items[@intCast(usize, t)];
            if (ty.state == @intCast(u8, 2)) return ciIntVal(ciFromU64(@intCast(u64, ty.alignment)));
        }
        return null;
    }
    if (node.child_0 == self.offset_of_id or node.child_0 == self.bit_offset_of_id) {
        var ec2_n = ast_mod.astStoreNodeExtraChildCount(self.store, node_idx);
        if (ec2_n >= @intCast(u32, 2)) {
            var tid = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
            if (tid) |t| {
                var ty = self.registry.types_items[@intCast(usize, t)];
                if (ty.state == @intCast(u8, 2) and ty.kind == type_mod.TypeKind.struct_type) {
                    var fields: []type_mod.FieldEntry = undefined;
                    type_mod.typeRegistryGetStructFields(self.registry, t, &fields);
                    var packed_fields: []type_mod.PackedBitField = undefined;
                    var has_pk = type_mod.typeRegistryGetPackedBitFields(self.registry, t, &packed_fields);
                    var fname_node = ast_mod.astStoreNodeAt(self.store, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1)));
                    if (fname_node.kind == AstKind.string_literal) {
                        var sv_idx = ast_mod.astStoreNodePayload(self.store, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1)));
                        var want_id = self.store.string_values.items[@intCast(usize, sv_idx)];
                        var fi: usize = 0;
                        while (fi < fields.len) : (fi += 1) {
                            if (fields[fi].name_id == want_id) {
                                var bo: u64 = @intCast(u64, fields[fi].offset);
                                if (has_pk) {
                                    var pk_bo: u64 = @intCast(u64, 0);
                                    if (fi < packed_fields.len) {
                                        pk_bo = @intCast(u64, packed_fields[fi].bit_offset);
                                    }
                                    if (node.child_0 == self.bit_offset_of_id) {
                                        bo = pk_bo;
                                    } else {
                                        bo = pk_bo / @intCast(u64, 8);
                                    }
                                } else {
                                    if (node.child_0 == self.bit_offset_of_id) {
                                        bo = bo * @intCast(u64, 8);
                                    }
                                }
                                return ciIntVal(ciFromU64(bo));
                            }
                        }
                    }
                } else if (ty.state == @intCast(u8, 2) and ty.kind == type_mod.TypeKind.packed_union_type) {
                    var u_fields: []type_mod.FieldEntry = undefined;
                    type_mod.typeRegistryGetUnionFields(self.registry, t, &u_fields);
                    var fname_node2 = ast_mod.astStoreNodeAt(self.store, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1)));
                    if (fname_node2.kind == AstKind.string_literal) {
                        var sv_idx2 = ast_mod.astStoreNodePayload(self.store, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1)));
                        var want_id2 = self.store.string_values.items[@intCast(usize, sv_idx2)];
                        var fi2: usize = 0;
                        while (fi2 < u_fields.len) : (fi2 += 1) {
                            if (u_fields[fi2].name_id == want_id2) {
                                var ubo: u64 = @intCast(u64, 0);
                                if (node.child_0 == self.offset_of_id) {
                                    ubo = @intCast(u64, 0);
                                }
                                return ciIntVal(ciFromU64(ubo));
                            }
                        }
                    }
                }
            }
        }
        return null;
    }
    if (node.child_0 == self.bit_size_of_id) {
        var ec3_n = ast_mod.astStoreNodeExtraChildCount(self.store, node_idx);
        if (ec3_n >= @intCast(u32, 1)) {
            var tid2 = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
            if (tid2) |t2| {
                var ty2 = self.registry.types_items[@intCast(usize, t2)];
                if (ty2.state == @intCast(u8, 2)) {
                    var bsz: u64 = @intCast(u64, ty2.size) * @intCast(u64, 8);
                    if (ty2.kind == type_mod.TypeKind.struct_type and (ty2.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
                        bsz = @intCast(u64, type_mod.typeRegistryGetPackedTotalBits(self.registry, t2));
                    }
                    if (ty2.kind == type_mod.TypeKind.packed_union_type) {
                        bsz = @intCast(u64, type_mod.typeRegistryGetPackedUnionTotalBits(self.registry, t2));
                    }
                    if (type_mod.typeRegistryIsInteger(self.registry, t2)) {
                        bsz = @intCast(u64, type_mod.typeRegistryIntWidthBits(self.registry, t2));
                    }
                    if (ty2.kind == type_mod.TypeKind.enum_type) {
                        var ebt = type_mod.typeRegistryEnumBackingType(self.registry, t2);
                        bsz = @intCast(u64, type_mod.typeRegistryIntWidthBits(self.registry, ebt));
                    }
                    if (ty2.kind == type_mod.TypeKind.bool_type) {
                        bsz = @intCast(u64, 1);
                    }
                    return ciIntVal(ciFromU64(bsz));
                }
            }
        }
        return null;
    }
    if (node.child_0 == self.int_cast_id or node.child_0 == self.as_id) {
        var tid = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
        var inner = comptimeEvalEvaluateDepth(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1)), depth);
        if (tid) |t| {
            if (inner) |cv| {
                if (cv.kind == KIND_FLOAT) return null;
                var is_int_t: bool = type_mod.typeRegistryIsInteger(self.registry, t);
                // @as with a NON-integer target must NOT fold here: the arm
                // yields an integer ComptimeVal, which enters the integer
                // binop evaluator and silently miscompiles float arithmetic
                // (e.g. `@as(f64,3)/2` -> integer 3/2). Fold @as only when the
                // target is an integer. (@intCast's non-integer behavior is
                // deliberately left unchanged, out of scope.)
                if (node.child_0 == self.as_id and !is_int_t) return null;
                // Task 2: the exact ComptimeInt value is range-checked against
                // the target width/signedness (Task 11S (c) semantics, now
                // exact -- no masking, no 64-bit sign-class heuristic). An
                // out-of-range `@intCast`/`@as` emits error[3000] and stops
                // folding; the pass's post-phase diag check exits rc=2 before
                // any emission. The message names the builtin actually used
                // (Task B3 item 3); `source_file_id` stays 0 because the global
                // comptime node sweep has no module context (Task B3 item 4).
                if (is_int_t and !comptimeIntFitsType(self.registry, cv.v, t)) {
                    if (self.diag) |dg| {
                        if (diag_mod.diagnosticCollectorMarkNodeOnce(dg, node_idx)) {
                            var ic_msg: []const u8 = "@intCast value does not fit the target type";
                            if (node.child_0 == self.as_id) { ic_msg = "@as value does not fit the target type"; }
                            _ = diag_mod.diagnosticCollectorAdd(dg, @intCast(u8, 0),
                                @intCast(u16, 3000),
                                @intCast(u32, 0), node.span_start,
                                node.span_start + @intCast(u32, node.span_len), ic_msg);
                        }
                    }
                    return null;
                }
                // Exact value; the cast result is an integer kind. A
                // NON-integer `@intCast` target restores the pre-Task-2
                // masking/truncation (carry item): the target's byte size is
                // its material width, so the folded bits are reduced to
                // `size * 8` low bits of the two's-complement pattern
                // (e.g. `@intCast(f32, 4294967596)` folds 300, not the exact
                // 4294967596). `@as` never reaches here with a non-integer
                // target (declined above).
                if (!is_int_t) {
                    var nty = self.registry.types_items[@intCast(usize, t)];
                    var nwb: u32 = @intCast(u32, nty.size) * @intCast(u32, 8);
                    if (nwb == 0) {
                        var zm = ciZeroInt();
                        return ciIntVal(zm);
                    }
                    if (nwb < @intCast(u32, 64)) {
                        var npat = ciToU64(cv.v);
                        var nmask: u64 = (@intCast(u64, 1) << @intCast(u64, nwb)) - @intCast(u64, 1);
                        npat = npat & nmask;
                        return ciIntVal(ciFromU64(npat));
                    }
                }
                var outv = cv;
                outv.kind = KIND_INT;
                return outv;
            }
        }
        return null;
    }
    if (node.child_0 == self.is_windows_id) {
        if (self.host_is_windows) return ciBoolVal(true);
        return ciBoolVal(false);
    }
    if (node.child_0 == self.int_to_float_id or node.child_0 == self.float_cast_id) {
        var fv = comptimeEvalFloatBuiltin(self, node_idx, depth);
        if (fv) |v| {
            // Z98 @bitCast is integer-only, so transport the f64 bit pattern
            // through a pointer reinterpretation (no value conversion).
            var fb: f64 = v;
            var fbp: *u64 = @ptrCast(*u64, &fb);
            return ComptimeVal{ .v = ciZeroInt(), .kind = KIND_FLOAT, .float_bits = fbp.* };
        }
        return null;
    }
    return null;
}

// Float-valued sub-evaluator. Deliberately SEPARATE from
// comptimeEvalEvaluateDepth so a float bit pattern can never enter the integer
// binop/negate/bit_not/int_cast paths (`kind == KIND_FLOAT` gates them). Handles
// float literals, `negate` (a negative float literal is
// `negate(float_literal)`), parentheses, nested @intToFloat/@floatCast, and
// const ident chains.

fn comptimeEvalFloat(self: *ComptimeEval, node_idx: u32, depth: u32) ?f64 {
    if (node_idx == @intCast(u32, 0)) return null;
    if (depth >= @intCast(u32, 16)) return null;
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    if (node.kind == AstKind.float_literal) {
        return self.store.float_values.items[@intCast(usize, ast_mod.astStoreNodePayload(self.store, node_idx))];
    } else if (node.kind == AstKind.negate) {
        var inner = comptimeEvalFloat(self, node.child_0, depth + @intCast(u32, 1));
        // Unary minus (not `0.0 - fv`) so `-0.0` keeps its sign bit.
        if (inner) |fv| { return -fv; }
        return null;
    } else if (node.kind == AstKind.paren_expr) {
        return comptimeEvalFloat(self, node.child_0, depth + @intCast(u32, 1));
    } else if (node.kind == AstKind.builtin_call) {
        if (node.child_0 == self.int_to_float_id or node.child_0 == self.float_cast_id) {
            return comptimeEvalFloatBuiltin(self, node_idx, depth + @intCast(u32, 1));
        }
        return null;
    } else if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(self.store, node_idx);
        // Task 9 (Part II): consult the enclosing function's local-const scope
        // FIRST (mirrors the integer evaluator and the module arm below): a
        // local `const` shadows a module const of the same name. This is what
        // lets a function-local `const f: f64 = ...` participate in a float
        // comparison fold.
        if (self.local_consts) |lcs| {
            if (type_resolver.localConstScopeLookup(lcs, name_id)) |l_decl_node| {
                var l_decl = ast_mod.astStoreNodeAt(self.store, l_decl_node);
                if (l_decl.child_1 != @intCast(u32, 0)) {
                    var lin = comptimeEvalFloat(self, l_decl.child_1, depth + @intCast(u32, 1));
                    if (lin) |lfv| {
                        var ldt = comptimeEvalResolveTypeArg(self, l_decl.child_0);
                        if (ldt) |lt| {
                            if (lt == type_mod.TYPE_F32) {
                                var lf32: f32 = @floatCast(f32, lfv);
                                return @floatCast(f64, lf32);
                            }
                        }
                        return lfv;
                    }
                    return null;
                }
            }
        }
        var mi: usize = 0;
        while (mi < @intCast(usize, self.symbol_reg.tables_len)) : (mi += 1) {
            var c_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbol_reg, @intCast(u32, mi), name_id);
            if (c_sym) |cs| {
                if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                    var c_decl = ast_mod.astStoreNodeAt(self.store, cs.decl_node);
                    if (c_decl.child_1 != @intCast(u32, 0)) {
                        var inner = comptimeEvalFloat(self, c_decl.child_1, depth + @intCast(u32, 1));
                        if (inner) |fv| {
                            // Round through the const's DECLARED type: a typed
                            // `const S: f32 = 0.1` is f32(0.1), not the raw f64
                            // literal. Skipping this silently changes semantics
                            // when the const is later widened to f64.
                            var dt = comptimeEvalResolveTypeArg(self, c_decl.child_0);
                            if (dt) |t| {
                                if (t == type_mod.TYPE_F32) {
                                    var f32v: f32 = @floatCast(f32, fv);
                                    return @floatCast(f64, f32v);
                                }
                            }
                            return fv;
                        }
                        return null;
                    }
                }
            }
        }
        return null;
    } else {
        return null;
    }
}

// Evaluate one @intToFloat/@floatCast call to an f64. The target must resolve
// to TYPE_F32/TYPE_F64; an f32 target rounds through f32. @intToFloat's operand
// is evaluated with the integer evaluator (Task 2: the exact ComptimeInt value
// is converted from its sign/magnitude limbs); @floatCast's with
// comptimeEvalFloat. A non-float target or non-foldable operand returns null
// (no fold; the runtime lowering is unchanged).
fn comptimeEvalFloatBuiltin(self: *ComptimeEval, node_idx: u32, depth: u32) ?f64 {
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    var tid = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
    if (tid) |t| {
        if (t != type_mod.TYPE_F32 and t != type_mod.TYPE_F64) return null;
        var inner_idx = ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1));
        var fv: f64 = 0.0;
        if (node.child_0 == self.int_to_float_id) {
            var iv = comptimeEvalEvaluateDepth(self, inner_idx, depth);
            if (iv) |cv| {
                if (cv.kind == KIND_FLOAT) return null;
                if (cv.kind == KIND_BOOL) {
                    if (ciIsZero(cv.v)) { fv = 0.0; } else { fv = 1.0; }
                } else {
                    fv = ciToF64(cv.v);
                }
            } else {
                return null;
            }
        } else if (node.child_0 == self.float_cast_id) {
            var xv = comptimeEvalFloat(self, inner_idx, depth);
            if (xv) |x| { fv = x; } else { return null; }
        } else {
            return null;
        }
        if (t == type_mod.TYPE_F32) {
            var f32v: f32 = @floatCast(f32, fv);
            return @floatCast(f64, f32v);
        }
        return fv;
    }
    return null;
}

pub fn comptimeEvalEvaluate(self: *ComptimeEval, node_idx: u32) ?ComptimeVal {
    return comptimeEvalEvaluateDepth(self, node_idx, @intCast(u32, 0));
}

fn comptimeEvalEvaluateDepth(self: *ComptimeEval, node_idx: u32, depth: u32) ?ComptimeVal {
    if (node_idx == @intCast(u32, 0)) return null;
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    if (node.kind == AstKind.int_literal) {
        return ciIntVal(ciFromU64(ast_mod.astStoreIntValue(self.store, node_idx)));
    } else if (node.kind == AstKind.char_literal) {
        return ciIntVal(ciFromU64(ast_mod.astStoreIntValue(self.store, node_idx)));
    } else if (node.kind == AstKind.bool_literal) {
        if ((node.flags & @intCast(u8, 1)) != @intCast(u8, 0)) return ciBoolVal(true);
        return ciBoolVal(false);
    } else if (node.kind == AstKind.negate) {
        var inner = comptimeEvalEvaluateDepth(self, node.child_0, depth);
        if (inner) |cv| {
            if (cv.kind != KIND_INT) return null;
            var nv = ciZeroInt();
            _ = ciNeg(cv.v, &nv);
            // Task 3 fix round 1 (Important): the unary fold obeys the same
            // peer-fit rule as the binops. Sema types `-x` as x's type
            // (`semanticAnalyzerResolveNegate`), so `-umax` on a u64 must
            // decline (Zig: "negation of type 'u64'"); the runtime negation
            // would wrap to u64 while the exact fold is negative.
            var pt = comptimeEvalOperandType(self, node.child_0);
            if (pt) |ptid| {
                if (!comptimeIntFitsType(self.registry, nv, ptid)) return null;
            }
            return ciIntVal(nv);
        }
        return null;
    } else if (node.kind == AstKind.bit_not) {
        var bnv = comptimeEvalEvaluateDepth(self, node.child_0, depth);
        if (bnv) |bv| {
            if (bv.kind != KIND_INT) return null;
            var bnb = ciZeroInt();
            if (!ciBitNot(bv.v, &bnb)) return null;
            // Task 3 fix round 1/2: `~` is the ONE unary that does NOT apply the
            // peer fit. Task 1 §4 keeps Z98's exact `~x = -x - 1` (Zig 0.15.2
            // rejects `~` on `comptime_int`), while sema types `~x` as x's type
            // and the runtime complement wraps to it — so for a typed unsigned
            // operand the exact result is negative and a fit check would reject
            // EVERY `~u` fold (fix round 1 review Important: it broke the valid,
            // Zig-equal `if ((~u) != 0) ...`). Declared divergence (documented in
            // doc 04): a comparison/use that depends on the WRAPPED complement
            // (e.g. `(~u) == 4294967295` with u: u32) still folds with the exact
            // value and can false-reject; the accepted `(~u) != 0` class is
            // runtime-equal to Zig.
            return ciIntVal(bnb);
        }
        return null;
    } else if (node.kind == AstKind.bool_not) {
        return comptimeEvalLogical(self, node_idx, node.kind, depth);
    } else if (node.kind == AstKind.add or node.kind == AstKind.sub or
               node.kind == AstKind.mul or node.kind == AstKind.div or
               node.kind == AstKind.mod_op or node.kind == AstKind.bit_and or
               node.kind == AstKind.bit_or or node.kind == AstKind.bit_xor or
               node.kind == AstKind.shl or node.kind == AstKind.shr) {
        return comptimeEvalBinOp(self, node_idx, node.kind, depth);
    } else if (node.kind == AstKind.cmp_eq or node.kind == AstKind.cmp_ne or
               node.kind == AstKind.cmp_lt or node.kind == AstKind.cmp_le or
               node.kind == AstKind.cmp_gt or node.kind == AstKind.cmp_ge) {
        return comptimeEvalCompare(self, node_idx, node.kind, depth);
    } else if (node.kind == AstKind.bool_and or node.kind == AstKind.bool_or) {
        return comptimeEvalLogical(self, node_idx, node.kind, depth);
    } else if (node.kind == AstKind.builtin_call) {
        return comptimeEvalBuiltin(self, node_idx, depth);
    } else if (node.kind == AstKind.paren_expr) {
        return comptimeEvalEvaluateDepth(self, node.child_0, depth);
    } else if (node.kind == AstKind.ident_expr) {
        if (depth >= @intCast(u32, 16)) return null;
        var name_id = ast_mod.astStoreIdentifier(self.store, node_idx);
        // Task 9D (Gap B): consult the enclosing function's local-const scope
        // before the module symbol registry. A local `const` is a statement, not
        // a module symbol, so only this scope can see it; it shadows a module
        // const of the same name (mirrors evalConstU32Full variant (e)).
        if (self.local_consts) |lcs| {
            if (type_resolver.localConstScopeLookup(lcs, name_id)) |l_decl_node| {
                var l_decl = ast_mod.astStoreNodeAt(self.store, l_decl_node);
                if (l_decl.child_1 != @intCast(u32, 0)) {
                    var lv = comptimeEvalEvaluateDepth(self, l_decl.child_1, depth + @intCast(u32, 1));
                    if (lv) |lvv| {
                        if (!comptimeEvalDeclFits(self, l_decl_node, lvv)) return null;
                    }
                    return lv;
                }
            }
        }
        var mi: usize = 0;
        while (mi < @intCast(usize, self.symbol_reg.tables_len)) : (mi += 1) {
            var c_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbol_reg, @intCast(u32, mi), name_id);
            if (c_sym) |cs| {
                if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                    var c_decl = ast_mod.astStoreNodeAt(self.store, cs.decl_node);
                    if (c_decl.child_1 != @intCast(u32, 0)) {
                        var cv = comptimeEvalEvaluateDepth(self, c_decl.child_1, depth + @intCast(u32, 1));
                        if (cv) |cvv| {
                            if (!comptimeEvalDeclFits(self, cs.decl_node, cvv)) return null;
                        }
                        return cv;
                    }
                }
            }
        }
        return null;
    } else {
        return null;
    }
}

// Task 4 (Task 1 §5.3): typed-slot fold rule. When a name's declaration has a
// declared integer type T and the exact initializer value does not fit T, the
// name is UNFOLDABLE (`false`), so the fold cannot invent a value the runtime
// slot never holds (`const u: u8 = 300;` materialises 44 with warning[3000]
// today, so folding 300 would be wrong). A non-integer value or an absent /
// non-integer declared type accepts.
fn comptimeEvalDeclFits(self: *ComptimeEval, decl_node: u32, v: ComptimeVal) bool {
    if (v.kind != KIND_INT) return true;
    var d = ast_mod.astStoreNodeAt(self.store, decl_node);
    if (d.child_0 == @intCast(u32, 0)) return true;
    if (comptimeEvalResolveTypeArg(self, d.child_0)) |t| {
        if (type_mod.typeRegistryIsInteger(self.registry, t)) {
            return comptimeIntFitsType(self.registry, v.v, t);
        }
    }
    return true;
}
