// multiarray_for_iter_value_xmod — a `for |row|` item used as an array VALUE
// (by-value whole-row copy) (Track-4 Task 2g-F fix round 1, RED at the fixed
// point 1e82d6ca).
//
// Real Zig's `for (arr) |row|` yields a BY-VALUE copy of the row: `row` is a
// `[N]T` value and may be copied (`var r: [N]T = row;`), indexed, or passed by
// value. The first Task 2g-F cut typed the item as `*[N]T` (a row reference),
// which is correct for streaming but makes a whole-row value use emit
// `r[_i] = row[_i];` with `row: Cell(*)[N]` — gcc rejects
// `incompatible types when assigning to type 'Cell' from type 'Cell *'`
// (dump rc=0, stderr EMPTY = SILENT invalid C).
//
// Fix: the item is materialized as an array-typed temp and the item load is a
// byte-wise element copy (`load_index{decay=3}`), so `row` is a real array
// value. Contract: dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no
// stdout. The fixture copies each row, asserts the copy's full contents, and
// mutates the copy to prove it does NOT alias the source row.
const Cell = struct { v: u32 };

var gc: [3][4]Cell = undefined;

pub fn main() void {
    var p: [*]Cell = @ptrCast([*]Cell, &gc[0][0]);
    var i: usize = 0;
    while (i < 12) : (i += 1) {
        p[i].v = 100 + @intCast(u32, i);
    }
    var rowi: usize = 0;
    for (gc) |row| {
        var r: [4]Cell = row;
        var k: usize = 0;
        while (k < 4) : (k += 1) {
            if (r[k].v != 100 + @intCast(u32, rowi * 4 + k)) {
                @panic("multiarray_for_iter_value_xmod: copy contents mismatch");
            }
        }
        r[0].v = 999;
        if (gc[rowi][0].v != 100 + @intCast(u32, rowi * 4)) {
            @panic("multiarray_for_iter_value_xmod: copy aliases the source row");
        }
        rowi += 1;
    }
    if (rowi != 3) {
        @panic("multiarray_for_iter_value_xmod: row count mismatch");
    }
}
