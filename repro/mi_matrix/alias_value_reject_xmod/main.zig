// alias_value_reject_xmod — A5-F type/alias value-position reject census.
// var x = A; / var y = i32; / const T = type; reject (a type value must be
// const/comptime; Z98 does not model the metatype); assignment/call/return of a
// type alias reject. Reuses level-0 error[3000] + source/target notes.
const A = i32;
const T = type;

var x = A;
var y = i32;
var z: i32 = 0;

fn take(v: i32) i32 {
    return v;
}

fn ret() i32 {
    return A;
}

pub fn main() void {
    z = A;
    _ = take(A);
    _ = ret();
    _ = x;
    _ = y;
    _ = z;
    _ = A;
    _ = T;
}
