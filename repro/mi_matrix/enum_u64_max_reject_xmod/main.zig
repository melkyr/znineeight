// enum_u64_max_reject_xmod — a `u64` enum member above the i64 storage maximum
// is a documented limitation (enum member values are stored in an i64 slot;
// changing that needs registry layout work). It must reject with a clear
// `error[3000]` that names the supported range, not the misleading
// `type 'u64' cannot represent integer value '-1'` cascade caused by the
// wrapped i64 store.
//
// Contract: rc 2, no `.c`, exactly one `error[3000]` with the explicit
// supported-enum-value-range message, and no `error[3062]`.
const E = enum(u64) { A = 18446744073709551615 };

pub fn main() void {
    _ = E.A;
}
