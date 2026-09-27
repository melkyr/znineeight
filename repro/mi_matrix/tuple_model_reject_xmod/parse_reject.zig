// tuple_model_reject_xmod/parse_reject.zig — FB (Volume II D4) parser reject
// entry: a mixed named/positional struct field list and a packed positional
// struct both reject level-0 error[2000]. Split from `main.zig` because a
// parse error aborts the module parse, which would suppress the sema census.
const Mixed = struct { i32, y: i32 };
const Packed = packed struct { i32, i32 };

pub fn main() void { }
