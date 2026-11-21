// D5/D10 sibling probe: prototype/definition convention mismatch. The
// declaration is stdcall, the definition is bare cdecl; post-fix sema must
// reject the disagreement.
extern "stdcall" fn mm(x: u32) i32;

pub extern fn mm(x: u32) i32 {
    return @intCast(i32, x);
}

pub fn main() void {
    _ = mm;
}
