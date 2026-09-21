// eu_payload_diff_reject_xmod — Task B5 clean-reject control.
//
// A runtime error-union-to-error-union coercion whose payloads differ
// (`F!i32 -> E!i64`) is INVALID Zig. Official Zig's EU->EU rule requires the
// destination error set to be a superset (`E1 subset E2`) AND the payloads to
// be in-memory identical; only comptime-known values may coerce. Zig 0.13.0
// rejects the runtime forms below with
//   error: expected type 'error{Boom,Other}!i64', found 'error{Boom}!i32'
//   note: error union payload 'i32' cannot cast into error union payload 'i64'
//
// DEFECT (before the fix): `sf/src/type_registry.zig`'s EU->EU assignability
// branch accepted the coercion whenever the payloads were merely *assignable*
// (integer widening is assignable), so Z98 accepted this invalid Zig and
// emitted C that failed to compile
// (`incompatible types when assigning to type 'zT_..._EU_7' from type
// 'zT_..._EU_6'`).
//
// FIX (Task B5): the EU->EU branch now requires exact payload TypeId equality
// (`eu_src.payload == eu_tgt.payload`), so every runtime payload-differing
// EU->EU context is a clean reject: `error[3000]`, rc=2, 0 `.c`.
//
// The four shapes below cover the return (ordinary and errdefer/dynamic),
// var-declaration/assignment, and call-argument contexts; the same single
// type-layer predicate gates all of them.
//
// Contract: dump rc=2, 0 `.c`, `error[3000]` — the canonical classifier's
// GREEN clean-reject bucket.
//
// The Zig-legal same-payload subset path (`F!i32 -> E!i32`) stays ACCEPTED and
// is pinned at runtime by `stdlib_eu_samepayload_xmod` (and the Task 10F
// `stdlib_errdefer_dyn_xmod`).
const E = error{Boom, Other};
const F = error{Boom};

fn g() F!i32 { return error.Boom; }
fn gok() F!i32 { return 7; }

// (a) ordinary return: payload-differing EU->EU.
fn retWiden() E!i64 {
    return g();
}

// (b) errdefer/dynamic return: same payload-differing EU->EU.
fn retWidenGuard() E!i64 {
    errdefer _ = 0;
    return gok();
}

// (c) call argument: payload-differing EU->EU.
fn takesE(x: E!i64) void {
    _ = x;
}

pub fn main() void {
    var a: E!i64 = 0;
    // (d) assignment / var-declaration init: payload-differing EU->EU.
    a = g();
    takesE(gok());
    _ = retWiden;
    _ = retWidenGuard;
    _ = a;
}
