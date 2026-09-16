// multiarray_for_iter_xmod — `for (g) |row|` over a multi-dimensional fixed
// array (Track-4 Task 2g-I, RED at the fixed point 7f9afa82deaa2356633b20a693282cf1).
//
// `g: [5][4]u8` and `gc: [5][4]Cell` globals. The for-loop lowerer
// (`sf/src/lower.zig:6097-6133`) resolves the iterated array's element type
// (`elem_type[0] = [4]u8` / `[4]Cell`) and then emits the per-item load with a
// HARDCODED `decay = 0` (`sf/src/lower.zig:6131`):
//
//   item_temp = nextTemp(self, elem_type[0]);   // ARRAY-typed temp
//   load_index{ base=ptr_temp, index=idx, result=item_temp, decay=0 }
//
// `emitBaseIdxAccess` (`sf/src/c89_emit.zig:194`, kind==0, decay==0) renders
// `item = base[idx];` — an ARRAY-to-ARRAY C assignment, illegal in C89. This is
// the SAME array-to-array defect class Task 2f-F closed for direct element
// access, reached through `for` iteration; `decay` is never set here, so the
// 2f-F decay mechanism is bypassed.
//
// RED (fixed point 7f9afa82…): dump rc=0, 0 target diagnostics (SILENT), 4 `.c`;
// gcc rejects `assignment to expression with array type` (one for the `[5][4]u8`
// row, one for the `[5][4]Cell` row). Shape:
//   zT_..._Arr_unsigned_char_4 row;         /* array-typed item */
//   row = zG_..._g[zT_25];                  /* array = array; invalid C89 */
//   zT_..._Arr_zT_..._Cel row_1;
//   row_1 = zG_..._gc[zT_43];               /* array = array; invalid C89 */
//
// GREEN (Task 2g-F): the for-loop item must not materialize an array-typed temp
// (decay the row to a pointer / emit an element address, reusing the 2f-F
// `load_index{decay}` mechanism and typing the capture as `*[N]T`). Contract:
// dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no stdout (assertion holds).
const Cell = struct { v: u32 };

var g: [5][4]u8 = undefined;
var gc: [5][4]Cell = undefined;

pub fn main() void {
    g[0][0] = 3;
    g[2][3] = 7;
    var p: [*]Cell = @ptrCast([*]Cell, &gc[1][0]);
    p[2].v = 5;
    var total: u32 = 0;
    for (g) |row| {
        var k: usize = 0;
        while (k < 4) : (k += 1) {
            total += row[k];
        }
    }
    for (gc) |row| {
        total += row[2].v;
    }
    if (total != 15) {
        @panic("multiarray_for_iter_xmod: row sum mismatch");
    }
}
