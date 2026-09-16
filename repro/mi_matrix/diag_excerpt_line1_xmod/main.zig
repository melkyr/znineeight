pub fn main() void { first_line_missing.x = 1; }
//
// diag_excerpt_line1_xmod — the `line_idx == 0` control for the diagnostic
// excerpt renderer (Track-4 Task 2e-I). The diagnostic span MUST stay on file
// line 1: `mem.binary_search` then returns 0 and `diagnostics.zig:501`'s
// `if (line_idx > 0)` guard does not fire, so the excerpt is CORRECT even at
// the RED fixed point 14ffe6b3d08bb273d74bb92fd9d07c13 (the bug only
// manifests on lines >= 2). Do not add a comment above the code: it would
// displace the span off line 1 and silently disable this control.
//
// RED == GREEN here: `main.zig:1:21: error[20]` + excerpt `pub fn main() void
// { first_line_missing.x = 1; }` + 18 carets at column 21.
