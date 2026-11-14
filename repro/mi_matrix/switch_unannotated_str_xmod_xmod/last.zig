// switch_unannotated_str_xmod_xmod / last.zig — the LAST module in the import order
// (main.zig imports mid.zig then last.zig), so `mid` is neither first nor last. This
// exercises per-module emission grouping. See main.zig.
pub fn ping() i32 {
    return 1;
}
