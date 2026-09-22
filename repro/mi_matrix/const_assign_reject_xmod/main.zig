// const_assign_reject_xmod — Task 7B regression fixture (const enforcement).
//
// Zig1 did not enforce `const`: assignment to a const local/param/capture, a
// module const, a `*const T` deref, or a `[]const T` element compiled rc=0 with
// no diagnostic and the emitted C performed the mutation. This contradicts
// spec §1.7 (`docs/reference/Language_Spec_Z98.md`: "The Z98 frontend strictly
// enforces `const` qualifiers") and `docs/sf/Design_p2.md:1375`.
//
// EXPECTED (after the fix): every assignment below clean-rejects with
// `error[3002]` ("cannot assign to immutable variable"), dump rc=2, 0 `.c`.
// The canonical corpus classifier GREENs only `error[3000]`, so this dir
// classifies FAIL (an expected reject; OK under the pre-fix compiler).
//
// Covered shapes (12 assignment sites):
//   1. local `const` plain assignment          7. module `const S: []const T`
//   2. local `const` compound assignment       8. local const-array element
//   3. nested-block `const`                    9. scalar function parameter
//   4. module `const`                         10. `*const T` parameter deref
//   5. module `const P: *const T` deref       11. `[]const T` parameter element
//   6. local `const p: *const T` deref        12. `for` capture
//      (plus local `const s: []const T` element, shape 6b)

const G: u32 = 1;
var GV: u32 = 1;
const P: *const u32 = &GV;

fn setParam(x: u32) void {
    x = 2; // 9. scalar parameter
    _ = x;
}

fn setConstPtr(p: *const u32) void {
    p.* = 2; // 10. *const T parameter deref
}

fn setConstSlice(s: []const u32) void {
    s[0] = 2; // 11. []const T parameter element
}

pub fn main() void {
    var sink: u32 = 0;
    var arr: [2]u32 = .{ 1, 2 };

    const x: u32 = 1;
    x = 2; // 1. local const plain
    sink = x;
    const y: u32 = 1;
    y += 1; // 2. local const compound
    sink = y;
    G = 2; // 4. module const
    P.* = 2; // 5. module const pointer deref
    const p: *const u32 = &GV;
    p.* = 2; // 6. local const pointer deref
    const s: []const u32 = &arr;
    s[0] = 2; // 6b. local const slice element
    const a: [2]u32 = .{ 1, 2 };
    a[0] = 2; // 8. const fixed-array element
    {
        const z: u32 = 5;
        z = 6; // 3. nested-block const
        sink = z;
    }
    for (arr) |it| {
        it = 2; // 12. for capture
        sink = it;
    }
    setParam(1);
    setConstPtr(&GV);
    setConstSlice(&arr);
    _ = sink;
}
