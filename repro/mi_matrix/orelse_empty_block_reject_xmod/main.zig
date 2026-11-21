// orelse_empty_block_reject_xmod — A9-F (Volume IV Amendment A9, operator m1740).
//
// A non-diverging value-less `orelse { ... }` fallback used in a VALUE position
// compiled rc 0 on the base fixed point (ca21a1ba) but emitted gcc-invalid C:
// `zT_7 = zT_8;` with `zT_8` undeclared (empty block), or a self-read of the
// uninitialized target (non-empty value-less block). Zig 0.15.2 rejects these
// (`expected type 'i32', found 'void'`). After A9-F the value positions are a
// clean level-0 reject, reusing `error[3059]` with an orelse-tailored message:
//   error[3059]: orelse block fallback without a value cannot be used as a value
// rc 2, 0 `.c`, one diagnostic per value position (no cascade). The direct
// discard `_ = ...` and the bare-statement form stay accepted (parked
// tolerance). The canonical classifier buckets non-`error[3000]` rejects as
// FAIL — an intentional, oracle-matching reject, NOT a green-guard.

fn maybe(x: i32) ?i32 { return if (x > 0) x else null; }
var g: i32 = 0;
fn sideEffect() void { g += 1; }

fn f() i32 { return maybe(-1) orelse {}; }

pub fn main() void {
    var a: i32 = maybe(-1) orelse {};                 // value: typed var, empty block
    const c: i32 = maybe(-1) orelse {};               // value: const, empty block
    var b: i32 = maybe(-1) orelse { sideEffect(); };  // value: typed var, value-less block
    var n: i32 = (maybe(-1) orelse {}) + 1;           // value: nested expression
    _ = maybe(-1) orelse {};                          // accepted: direct discard
    maybe(-1) orelse {};                              // parked: bare statement
    _ = f();
    _ = a; _ = b; _ = c; _ = n;
}
