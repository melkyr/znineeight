// lifetime_param.zig — Task 9d LIFE-2 fixture.
//
// Parameters are seeded by runLifetimeAnalyzer into the real state map,
// including the FIRST proto (index 0). Pointer-like params are caller-owned
// (`external`), by-value params are call-frame storage (`param`).
//
// Documented limits: no interprocedural analysis; provenance is not tracked
// through pointer dereferences.
const Point = struct { x: u32, y: u32 };

// First function in the module => proto index 0. Before 9d the payload==0
// absence sentinel skipped seeding here, so this was misclassified as a
// local (ERR_2020) instead of ERR_2021.
fn param_binding_address(p: u32) *u32 {
    return &p;
}

fn param_pointer_value(p: *Point) *Point {
    return p;
}

fn param_pointer_interior(p: *Point) *u32 {
    return &p.x;
}

fn param_pointer_binding_address(p: *Point) *Point {
    return &p;
}

pub fn main() void {
    var v: u32 = 0;
    var pt: Point = Point{ .x = 0, .y = 0 };
    _ = param_binding_address(v);
    _ = param_pointer_value(&pt);
    _ = param_pointer_interior(&pt);
    _ = param_pointer_binding_address(&pt);
}
