// diag_excerpt_positions_xmod — diagnostic excerpt line/caret selection across
// span start positions (Track-4 Task 2e-I, pinned RED at the fixed point
// 14ffe6b3d08bb273d74bb92fd9d07c13).
//
// Exercises the excerpt renderer in `sf/src/diagnostics.zig` (the block at
// `:498-538`). Each function below puts a hard `error[20]` (undefined symbol,
// `ERR_3001_UNDEFINED_SYMBOL`) or a tolerated `warning[3000]` (type-mismatch)
// at a different span position:
//   * column 0 (line start)      -> excerpt renders the PREVIOUS line
//   * column 1                   -> excerpt renders the PREVIOUS line
//   * mid-line column            -> excerpt renders the PREVIOUS line
//   * multi-line span            -> excerpt renders the PREVIOUS line
//   * blank previous line        -> NO excerpt at all
// The `line_idx == 0` control lives in the sibling `diag_excerpt_line1_xmod`
// (the span must be on file line 1, which a header comment would displace).
//
// RED (fixed point 14ffe6b3…): the header `file:line:col` is correct
// (`sourceManagerGetLocation` uses `mem.binary_search` correctly) but the
// excerpt source line is one line early — `diagnostics.zig:501` applies an
// extra `if (line_idx > 0) line_idx -= 1;` on top of `binary_search`'s
// already-upper_bound-minus-one result. When the previous line is blank,
// `l_start == l_end` and the excerpt is skipped entirely.
//
// GREEN (Task 2e-F): each excerpt shows the source line that CONTAINS the span,
// with the caret at `loc.col` (0-based) and `span_end - span_start` carets.
// Dump stays rc=2 with 0 `.c` (the `error[20]`s are real); only stderr changes.

pub fn main() void {
    var ok: u32 = 1;
    _ = ok;
}
fn col0() void {
missing_at_col0.x = 1;
}
fn col1() void {
 missing_at_col1.x = 1;
}
fn midline() void {
    var y: u32 = middle_line_missing.x;
}
fn multiline() void {
    var z: u32 =
        multiline_missing;
}
fn blankprev() void {

    var w: u32 = blankprev_missing.x;
}
