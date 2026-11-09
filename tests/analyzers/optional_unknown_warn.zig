// optional_unknown_warn.zig — Task 9h D4h negative fixture.
//
// Optional and unknown-call bases remain conservative (`maybe`), so each of the
// four dereferences below must still emit exactly one WARN_6002.
const Holder = struct { q: ?*u32 };

fn unknownPtr() *u32 {
    return @intToPtr(*u32, 8);
}

fn unknown_call_deref() u32 {
    var p = unknownPtr();
    return p.*;
}

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
    _ = unknownPtr();
}
