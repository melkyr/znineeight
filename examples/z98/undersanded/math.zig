// math.zig — UNDERSANDED fixed-point helpers (spec §25.4).
//
// Integer percent math only (R11); truncation toward zero, applied once.
// min/max/abs/clamp are reused from std_math (G12) — do not copy them here.

pub fn applyPct(v: i32, pct: i32) i32 {
    return (v * pct) / 100;
}

pub fn ceilPct(v: i32, pct: i32) i32 {
    return (v * pct + 99) / 100;
}
