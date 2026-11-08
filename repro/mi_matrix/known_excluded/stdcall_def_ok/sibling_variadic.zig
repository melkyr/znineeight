// D5/D10 sibling probe: variadic stdcall extern declaration. Record the
// current accept/reject behavior (the convention rules reject variadic
// stdcall today).
extern "stdcall" fn vf(x: i32, ...) i32;

pub fn main() void {
    _ = vf;
}
