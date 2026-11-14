// nested_loop_cap_maybe_warn.zig — Task 9h1 fix-round-2 nested-cap fixture.
//
// 33 nested loops exceed `NP_CTRL_MAX` (32). The innermost loop's `break` must
// not be attributed to loop 32, and the unpushed loop must conservatively force
// `maybe` at its own exit. The post-loop dereference is therefore `maybe` and
// emits exactly one WARN_6002, never a false ERR_2004 from mis-targeted control.
fn nested_loop_cap_maybe_warn(n: u32) u32 {
    var q: ?*u32 = null;
    var x: u32 = 7;
    var i: u32 = 0;
    while (i < n) : (i += 1) { // 1
    while (i < n) : (i += 1) { // 2
    while (i < n) : (i += 1) { // 3
    while (i < n) : (i += 1) { // 4
    while (i < n) : (i += 1) { // 5
    while (i < n) : (i += 1) { // 6
    while (i < n) : (i += 1) { // 7
    while (i < n) : (i += 1) { // 8
    while (i < n) : (i += 1) { // 9
    while (i < n) : (i += 1) { // 10
    while (i < n) : (i += 1) { // 11
    while (i < n) : (i += 1) { // 12
    while (i < n) : (i += 1) { // 13
    while (i < n) : (i += 1) { // 14
    while (i < n) : (i += 1) { // 15
    while (i < n) : (i += 1) { // 16
    while (i < n) : (i += 1) { // 17
    while (i < n) : (i += 1) { // 18
    while (i < n) : (i += 1) { // 19
    while (i < n) : (i += 1) { // 20
    while (i < n) : (i += 1) { // 21
    while (i < n) : (i += 1) { // 22
    while (i < n) : (i += 1) { // 23
    while (i < n) : (i += 1) { // 24
    while (i < n) : (i += 1) { // 25
    while (i < n) : (i += 1) { // 26
    while (i < n) : (i += 1) { // 27
    while (i < n) : (i += 1) { // 28
    while (i < n) : (i += 1) { // 29
    while (i < n) : (i += 1) { // 30
    while (i < n) : (i += 1) { // 31
    while (i < n) : (i += 1) { // 32
    while (i < n) : (i += 1) { // 33
        if (i == 0) {
            q = &x;
            break;
        }
        q = null;
    }
    return q.*;
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    }
    return 0;
}

pub fn main() void {
    _ = nested_loop_cap_maybe_warn(0);
}
