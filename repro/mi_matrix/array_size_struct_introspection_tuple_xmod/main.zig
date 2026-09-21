// array_size_struct_introspection_tuple_xmod — Task 11H negative control: a
// TUPLE type in an array-size position must stay a clean `error[3050]`, never
// be folded by a blanket `state == 2` check.
//
// A tuple type is created `state == 2` at registration, so a blanket
// `state == 2` fold would accept it. Task 11H deliberately keeps
// `evalConstScalarKind` as the integer whitelist and only adds `struct_type`,
// so the tuple stays rejected. `@TypeOf` is not resolvable as a type
// expression in this position, so the array-size fallback emits the hard error.
// Contract: dump rc=2, 0 `.c`,
//   error[3050]: array size is not a constant expression.
var g: [@sizeOf(@TypeOf(.{ 1, 2 }))]u8 = undefined;

pub fn main() void {
    _ = g;
}
