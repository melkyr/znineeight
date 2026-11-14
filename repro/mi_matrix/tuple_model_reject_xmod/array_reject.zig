// tuple_model_reject_xmod/array_reject.zig — FB (Volume II D4) array-element
// reject entry: a tuple type with an array element is a level-0 error[3000]
// (operator ruling: no field-wise C array assignment). Split from `main.zig`
// because a type-resolution error suppresses the later sema census.
const TA = struct { [2]i32, i32 };

pub fn main() void {
    var ta: TA = undefined;
    _ = ta;
}
