// lazy_import_fold_ok — Phase 3.5 D3 repro (evaluator-foldable condition).
//
// The condition `1 == 1` is comptime-known to the evaluator but not to the
// parser's conservative fold probe. Pre-fix the parse-time load eagerly opens
// the dead arm's `missing.zig` and rejects with `error[3048]`.
//
// GREEN (post-fix): the dead arm never opens its file; stdout
// `exists ping\nlazy import fold ok\n`, rc 0.
const std = @import("std");

const impl = if (1 == 1) @import("exists.zig") else @import("missing.zig");

pub fn main() void {
    impl.ping();
    std.io.write("lazy import fold ok\n");
}
