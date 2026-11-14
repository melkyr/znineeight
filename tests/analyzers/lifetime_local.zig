// lifetime_local.zig — Task 9d LIFE-1 fixture.
//
// True positives that must stay reported through the real analyzer state map
// (no front-end scope map, no hand-fed symbols):
//   - return &local             -> ERR_2020 (error[3030])
//   - return &local.field       -> ERR_2020 (error[3030])
//   - var p = &local; return p  -> WARN_6010 (warning[3032])
//   - return local_array[0..n]  -> WARN_6011 (warning[3033])
//
// Documented limits (no interprocedural analysis, no alias tracking through
// pointer dereferences): `return *ptr` / `return (*p).field` are not caught.
const Point = struct { x: u32, y: u32 };

fn local_address() *u32 {
    var x: u32 = 1;
    return &x;
}

fn local_field_address() *u32 {
    var p: Point = Point{ .x = 1, .y = 2 };
    return &p.x;
}

fn local_pointer_variable() *u32 {
    var x: u32 = 1;
    var p: *u32 = &x;
    return p;
}

fn local_slice() []u32 {
    var arr: [4]u32 = undefined;
    return arr[0..2];
}

pub fn main() void {
    _ = local_address();
    _ = local_field_address();
    _ = local_pointer_variable();
    _ = local_slice();
}
