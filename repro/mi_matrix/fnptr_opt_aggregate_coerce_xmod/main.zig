// fnptr_opt_aggregate_coerce_xmod — D1 frontend-coercion shape (T0 fixture, red
// before any fix). Plan: docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md
// Spec: docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md §2 bug 1.
// Defect: examples/torrent_example_defects.md "D1 — A function pointer whose
// return type is an optional of an aggregate cannot be emitted", reproducer A.
//
// A free function whose return type is `?Key` (Key = aggregate) assigned to a
// fn-pointer field `fn (*void) ?Key` is rejected with `error[3000]: type
// mismatch in field initialization` because the field's `?Key` and the
// function's `?Key` resolve to two distinct synthetic optional ids
// (`typeRegistryGetOrCreateOptional` caches only when the payload is already
// laid out; `typeRegistryIsAssignable`'s `fn_type` comparison reads
// `return_type` ids directly). Boundary probes `?u8`, `fn (*void) Key`,
// `fn (*void) E!T` are accepted (see fn_ptr_signature_ok_xmod and the defect
// entry); only optional-of-aggregate is broken.
//
// GREEN contract (post-T1, for the fixing task to capture as goldens):
// stdout `coerce sigint ok\n`, rc 0, deterministic 3x — the fn-pointer field
// coerces, the call through `readKey_fn` returns `?Key`, and the capture
// switches on the `.sigint` payload. RED pre-fix: dump rc 2, 0 `.c` (exact
// census in NOTES.md / expected_error.txt).
const std = @import("std");

pub const Key = union(enum) { char: u8, sigint };
pub const Console = struct { readKey_fn: fn (*void) ?Key, state: *void };

fn readKey(state: *void) ?Key {
    _ = state;
    return Key{ .sigint = {} };
}

var st: u8 = 0;

pub fn main() void {
    var c: Console = Console{ .readKey_fn = readKey, .state = @ptrCast(*void, &st) };
    if (c.readKey_fn(c.state)) |k| {
        switch (k) {
            .char => {
                std.io.write("coerce char FAIL\n");
            },
            else => {
                std.io.write("coerce sigint ok\n");
            },
        }
    }
}
