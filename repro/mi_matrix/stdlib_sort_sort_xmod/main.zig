// stdlib_sort_sort_xmod — std_sort (L4) `sort(Sortable)` GREEN fixture.
//
// Contract (blueprint §3 L4): `Sortable{ lenFn, lessFn, swapFn, data }` and
// `sort(s) void`. The vtable path is the only way a user type sorts; the
// concrete `sortI32`/`sortU32`/`sortStr` wrappers are covered by their own
// fixtures. `sort` is introsort: not stable, no allocation, no error set.
//
// Cases pinned (all on a user-defined `Pair{ key, val }` ordered by `key`):
//   - random keys, already-sorted keys, reverse-sorted keys, duplicate keys;
//   - empty and single-element inputs (no-op);
//   - after every sort: keys non-decreasing AND the key-sum / val-sum are
//     preserved (a permutation, not a lossy transform).
// Stability is deliberately NOT asserted (introsort is not stable).
//
// GREEN (contract): deterministic byte-exact stdout `sort ok\n` (RUNRC=0).
const std = @import("std");
const sort = @import("std_sort.zig");

const Pair = struct {
    key: u32,
    val: u32,
};

const PairBox = struct {
    items: []Pair,
};

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn pairLen(data: *void) usize {
    var b: *PairBox = @ptrCast(*PairBox, data);
    return b.items.len;
}

fn pairLess(data: *void, i: usize, j: usize) bool {
    var b: *PairBox = @ptrCast(*PairBox, data);
    return b.items[i].key < b.items[j].key;
}

fn pairSwap(data: *void, i: usize, j: usize) void {
    var b: *PairBox = @ptrCast(*PairBox, data);
    var t: Pair = b.items[i];
    b.items[i] = b.items[j];
    b.items[j] = t;
}

// Sorts `items` through the vtable and verifies sortedness + multiset sums.
fn runCase(items: []Pair, what: []const u8) void {
    var keysum: u32 = 0;
    var valsum: u32 = 0;
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        keysum += items[i].key;
        valsum += items[i].val;
    }

    var box = PairBox{ .items = items };
    var s = sort.Sortable{
        .lenFn = pairLen,
        .lessFn = pairLess,
        .swapFn = pairSwap,
        .data = @ptrCast(*void, &box),
    };
    sort.sort(s);

    i = 1;
    while (i < items.len) : (i += 1) {
        ck(items[i - 1].key <= items[i].key, what);
    }

    var k2: u32 = 0;
    var v2: u32 = 0;
    i = 0;
    while (i < items.len) : (i += 1) {
        k2 += items[i].key;
        v2 += items[i].val;
    }
    ck(k2 == keysum, what);
    ck(v2 == valsum, what);
}

pub fn main() void {
    // Array-of-struct literals (`[_]Pair{...}`) are not supported today (the
    // declaration is typed `void`), so the Pair arrays are built with the
    // ordinary `[N]T = undefined` + element-assignment idiom.
    // random
    var a: [10]Pair = undefined;
    a[0] = .{ .key = 7, .val = 70 };
    a[1] = .{ .key = 2, .val = 20 };
    a[2] = .{ .key = 9, .val = 90 };
    a[3] = .{ .key = 4, .val = 40 };
    a[4] = .{ .key = 1, .val = 10 };
    a[5] = .{ .key = 8, .val = 80 };
    a[6] = .{ .key = 3, .val = 30 };
    a[7] = .{ .key = 6, .val = 60 };
    a[8] = .{ .key = 5, .val = 50 };
    a[9] = .{ .key = 0, .val = 0 };
    runCase(a[0..], "sort random");

    // already sorted
    var b: [6]Pair = undefined;
    b[0] = .{ .key = 0, .val = 1 };
    b[1] = .{ .key = 1, .val = 1 };
    b[2] = .{ .key = 2, .val = 1 };
    b[3] = .{ .key = 3, .val = 1 };
    b[4] = .{ .key = 4, .val = 1 };
    b[5] = .{ .key = 5, .val = 1 };
    runCase(b[0..], "sort sorted");

    // reverse sorted
    var c: [6]Pair = undefined;
    c[0] = .{ .key = 5, .val = 1 };
    c[1] = .{ .key = 4, .val = 1 };
    c[2] = .{ .key = 3, .val = 1 };
    c[3] = .{ .key = 2, .val = 1 };
    c[4] = .{ .key = 1, .val = 1 };
    c[5] = .{ .key = 0, .val = 1 };
    runCase(c[0..], "sort reverse");

    // duplicates
    var d: [10]Pair = undefined;
    d[0] = .{ .key = 3, .val = 1 };
    d[1] = .{ .key = 1, .val = 2 };
    d[2] = .{ .key = 3, .val = 3 };
    d[3] = .{ .key = 2, .val = 4 };
    d[4] = .{ .key = 1, .val = 5 };
    d[5] = .{ .key = 3, .val = 6 };
    d[6] = .{ .key = 2, .val = 7 };
    d[7] = .{ .key = 1, .val = 8 };
    d[8] = .{ .key = 2, .val = 9 };
    d[9] = .{ .key = 3, .val = 10 };
    runCase(d[0..], "sort dup");

    // single + empty
    var one: [1]Pair = undefined;
    one[0] = .{ .key = 42, .val = 7 };
    runCase(one[0..], "sort one");
    var none: [1]Pair = undefined;
    none[0] = .{ .key = 0, .val = 0 };
    runCase(none[0..0], "sort empty");

    if (g_fail == 0) {
        std.io.write("sort ok\n");
    } else {
        std.io.write("sort FAIL\n");
    }
}

