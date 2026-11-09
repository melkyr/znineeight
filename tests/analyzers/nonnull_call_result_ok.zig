// nonnull_call_result_ok.zig — Task 9h2 D4h2 fixture.
//
// A call whose declared result is a non-optional pointer is non-null, whether
// the callee is a local function or an extern declaration. Neither dereference
// emits WARN_6002.
fn localPtr() *u32 {
    return @intToPtr(*u32, 8);
}

extern "c" fn externalPtr() *u32;

fn call_ok() u32 {
    var a = localPtr();
    var b = externalPtr();
    return a.* + b.*;
}

pub fn main() void {
    _ = localPtr();
}
