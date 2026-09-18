// field_store_continue_xmod — Plan C Task 1b-I RED pin (the I half of the
// Task 1b I/F pair, operator ruling m1670) for the field-store-as-continue-
// expression ICE.
//
// TRIGGER. A compound assignment to a struct field used as the continue
// expression of a `while` loop:
//
//     while (s.buf_len < 56) : (s.buf_len += 1) { ... }
//
// RED today (fixed point 414cccee639bdb61c7a9f1f2ddddb166): the lowering of the
// continue expression has no field-store base, so `zig1 -ffast --dump-c89`
// fails rc=3 with 0 emitted `.c`:
//
//     error[3043]: internal: unsupported field-store base (node N)
//
// `error[3043]` is in the canonical classifier's ICE regex
// (`scripts/corpus/classify`), so this dir buckets **ICE** (RED).
//
// WORKAROUND (used by `sf/src/std_crypto.zig` Final padding loops): move the
// increment into the loop body, or use a local counter:
//
//     while (s.buf_len < 56) { s.buf[s.buf_len] = 0; s.buf_len += 1; }
//
// RED -> GREEN contract (Task 1b-F). The continue-expression form lowers like
// the body form; this program runs and prints exactly `field store continue ok`
// with exit code 0. The committed goldens (`expected.txt`/`expected.rc`) encode
// this DESIRED GREEN behaviour, so this pin is RED until Task 1b-F.
//
// This is a compiler-graph pin only: no `sf/src` change here, and the fixed
// point stays UNMOVED at 414cccee639bdb61c7a9f1f2ddddb166.
const std = @import("std");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub const S = struct {
    buf: [64]u8,
    buf_len: usize,
};

// The exact trigger shape: a compound field-store as a while continue expr.
fn fill(s: *S) void {
    while (s.buf_len < 56) : (s.buf_len += 1) {
        s.buf[s.buf_len] = 0;
    }
}

pub fn main() void {
    var s: S = undefined;
    s.buf_len = 0;
    fill(&s);

    ck(s.buf_len == 56, "buf_len after continue-store loop");

    var i: usize = 0;
    while (i < 56) : (i += 1) {
        ck(s.buf[i] == 0, "buf byte zeroed by continue-store loop");
    }

    if (g_fail == 0) {
        std.io.write("field store continue ok\n");
    } else {
        std.io.write("field store continue FAIL\n");
    }
}
