// optional_unknown_warn.zig — Task 9h2 D4h2 negative fixture.
//
// Optional and unknown bases remain conservative (`maybe`): an optional
// parameter, an optional pointer field, and an unguarded `@intToPtr` from an
// unknown integer each emit exactly one WARN_6002.
const Holder = struct { q: ?*u32 };

fn optional_param_deref(p: ?*u32) u32 {
    return p.*;
}

fn optional_field_deref(h: *Holder) u32 {
    return h.q.*;
}

fn unguarded_inttoptr_deref(addr: usize) u32 {
    var p: *u32 = @intToPtr(*u32, addr);
    return p.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = x;
}
