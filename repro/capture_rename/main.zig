extern fn __bootstrap_print_int(x: i32) void;

const Val1 = union(enum) {
    A: i32,
    B: i32,
    C: i32,
    D: i32,
};

const Val2 = union(enum) {
    A: i32,
    B: i32,
};

const ValNest = union(enum) {
    A: i32,
    B: i32,
};

const MyErrorSet = error {
    OutOfMemory,
    Other,
    Overflow,
};

fn makeOther() MyErrorSet!i32 { return error.Other; }
fn makeOOM() MyErrorSet!i32 { return error.OutOfMemory; }
fn makeOv() MyErrorSet!i32 { return error.Overflow; }

pub fn main() void {
    // ============================================================
    // CASE 2: catch capture same-name same-type (cross-catch)  [RED]
    // Two catch expressions, both using |err|, but with DIFFERENT
    // error values. The second catch's |err| must resolve to the
    // second error code, not the first. Catch expressions do NOT
    // call maybeDisambiguateCapture, so the second |err| aliases
    // the first catch's error code temp.
    //
    // First catch: error.OutOfMemory → err = OOM code
    // Second catch: error.Other → err should = Other code
    // If RED: err in second body = OOM code (stale first decl)
    // ============================================================
    var c_err: i32 = 0;
    _ = makeOOM() catch |err| { _ = err; };
    _ = makeOther() catch |err| {
        if (err == error.Other) {
            c_err = @intCast(i32, 99);
        } else {
            c_err = @intCast(i32, 77);
        }
    };
    __bootstrap_print_int(c_err); // expected: 99; RED: 77

    // ============================================================
    // CASE 1: switch capture same-name same-type (cross-switch)
    // switch captures are scoped (local_decl_count restored after
    // prong lowering), so cross-switch same-name does NOT trigger
    // the bug. However, cross-context with same-name var_decl can
    // be tested.
    // ============================================================
    var s1: i32 = 0;
    var s2: i32 = 0;
    var sw_a: Val1 = Val1{ .A = @intCast(i32, 1) };
    var sw_b: Val1 = Val1{ .B = @intCast(i32, 2) };
    switch (sw_a) {
        .A => |x| s1 = x + 1,
        else => {},
    }
    switch (sw_b) {
        .B => |x| s2 = x + 1,
        else => {},
    }
    __bootstrap_print_int(s1 + s2); // expected: 5 (2+3); marker for case order

    // ============================================================
    // CASE 4: switch capture same-name different-type
    // maybeDisambiguateCapture handles this (existing behavior).
    // Verify it still works.
    // ============================================================
    var sd: i32 = 0;
    var sw_c: Val1 = Val1{ .C = @intCast(i32, 5) };
    var sw_d: Val2 = Val2{ .A = @intCast(i32, 37) };
    switch (sw_c) {
        .C => |x| sd = x,
        else => {},
    }
    switch (sw_d) {
        .A => |x| sd += x,
        else => {},
    }
    __bootstrap_print_int(sd); // expected: 42 (5 + 37)

    // ============================================================
    // CASE 5: catch capture same-name as var_decl
    // Local var_decl name collides with catch capture name.
    // If not disambiguated, may cause shadowing or ICE.
    // ============================================================
    var err_shadow: i32 = 5;
    _ = makeOv() catch |err_shadow| {
        _ = err_shadow;
    };
    __bootstrap_print_int(@intCast(i32, 6)); // placeholder; RED if ICE/compile err

    // ============================================================
    // CASE 6: nested captures (for-in inside switch prong)
    // |outer| from switch, then iterate array.
    // Uses while loop due to for-in codegen bug (infinite loop).
    // Tests that nested capture decls are distinct.
    // ============================================================
    var ns: i32 = 0;
    var narr: [2]i32 = [2]i32{ @intCast(i32, 10), @intCast(i32, 20) };
    var nsw: ValNest = ValNest{ .A = @intCast(i32, 0) };
    switch (nsw) {
        .A => |outer| {
            _ = outer;
            var ni: usize = 0;
            while (ni < 2) {
                var inner: i32 = narr[ni];
                ns += inner;
                ni += 1;
            }
        },
        else => {},
    }
    __bootstrap_print_int(ns); // expected: 30

    // ============================================================
    // CASE 3: for-in capture same-name as previous for-in (LAST)
    // Must be last because for-in over slice infinite-loops due
    // to codegen bug (missing loop counter update in generated C).
    // Previous cases output before this infinite loop triggers.
    // ============================================================
    var f1: i32 = 0;
    var f2: i32 = 0;
    var a_arr: [3]i32 = [3]i32{ @intCast(i32, 7), @intCast(i32, 8), @intCast(i32, 9) };
    var a_arr2: [3]i32 = [3]i32{ @intCast(i32, 1), @intCast(i32, 2), @intCast(i32, 3) };
    var sl1: []i32 = a_arr[0..3];
    var sl2: []i32 = a_arr2[0..3];
    for (sl1) |v| { f1 += v; }
    for (sl2) |v| { f2 += v; }
    __bootstrap_print_int(f1 + f2); // expected: 30; unreachable: infinite loop
}

// ============================================================
// AUX: for-in capture compilation test (unused fn)
// Exercises for-in capture same-name pattern. Generates C that
// compiles but would infinite-loop at runtime. Tests that zig1's
// capture disambiguation in for-in code path at least compiles.
// ============================================================
fn for_capture_compile_test() void {
    var a1: [3]i32 = [3]i32{ @intCast(i32, 1), @intCast(i32, 2), @intCast(i32, 3) };
    var a2: [3]i32 = [3]i32{ @intCast(i32, 4), @intCast(i32, 5), @intCast(i32, 6) };
    var s1: []i32 = a1[0..3];
    var s2: []i32 = a2[0..3];
    var t: i32 = 0;
    for (s1) |v| { t += v; }
    for (s2) |v| { t += v; }
}
