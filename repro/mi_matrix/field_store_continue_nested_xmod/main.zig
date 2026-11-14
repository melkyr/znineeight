// field_store_continue_nested_xmod — Plan C Task 1b-F nested extension pin.
//
// TRIGGER. A compound assignment to a NESTED struct field used as the continue
// expression of a `while` loop:
//
//     while (o.inner.n < 56) : (o.inner.n += 1) { ... }
//
// RED before the nested extension: the semantic analyzer never visited a
// `while` continue expression (`child_2`), so the resolved-type entries the
// lowering needs for the nested base (`o.inner`) were missing and
// `zig1 -ffast --dump-c89` failed rc=3 with 0 emitted `.c`:
//
//     error[3043]: internal: unsupported address-of l-value (node N)
//
// Task 1b-F fixed the single-level shape (`field_store_continue_xmod`); this
// nested extension resolves the continue expression in
// `semanticAnalyzerResolveWhileHeader`, so the nested field store lowers like
// the body form.
//
// GREEN contract: this program runs and prints exactly
// `nested field store continue ok` with exit code 0.
const std = @import("std");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub const Inner = struct {
    n: usize,
};

pub const Outer = struct {
    inner: Inner,
    buf: [64]u8,
};

// The exact nested trigger shape: a compound field-store through a nested
// field access as a while continue expression.
fn fill(o: *Outer) void {
    while (o.inner.n < 56) : (o.inner.n += 1) {
        o.buf[o.inner.n] = 0;
    }
}

pub fn main() void {
    var o: Outer = undefined;
    o.inner.n = 0;
    fill(&o);

    ck(o.inner.n == 56, "nested n after continue-store loop");

    var i: usize = 0;
    while (i < 56) : (i += 1) {
        ck(o.buf[i] == 0, "buf byte zeroed by nested continue-store loop");
    }

    if (g_fail == 0) {
        std.io.write("nested field store continue ok\n");
    } else {
        std.io.write("nested field store continue FAIL\n");
    }
}
