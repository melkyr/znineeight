// switch_str_literal_prong_xmod_xmod / last.zig — the LAST module in the import order
// (main.zig imports mid.zig then last.zig), so `mid` is neither first nor last. This
// exercises the per-module emission grouping: after the fix the string-prong slice must
// be correct regardless of which module owns the switch. See main.zig.
pub fn ping() i32 {
    return 1;
}
