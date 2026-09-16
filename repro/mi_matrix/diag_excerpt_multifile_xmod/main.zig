// diag_excerpt_multifile_xmod — a diagnostic whose span lives in an IMPORTED
// module (`mod.zig`), exercising the excerpt renderer's per-file content and
// line-offset lookup (`sourceManagerGetSourceContent` /
// `sourceManagerGetLineOffsets`, keyed by `d.file_id`). Track-4 Task 2e-I pin,
// RED at the fixed point 14ffe6b3d08bb273d74bb92fd9d07c13.
//
// RED: header is `mod.zig:6:6` (correct) but the excerpt prints mod.zig's
// line 5 (`    var y: u32 = 0;`) because of the extra `line_idx -= 1` in
// `sf/src/diagnostics.zig:501`. GREEN (Task 2e-F): the excerpt prints
// mod.zig's line 6 (`    y = missing;`) with the caret at column 6.
//
// Dump rc=0, 5 `.c` (the warning is tolerated); only the stderr excerpt changes.
const mod = @import("mod.zig");

pub fn main() void {
    mod.run();
}
