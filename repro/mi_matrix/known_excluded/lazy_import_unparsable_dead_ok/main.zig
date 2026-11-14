// lazy_import_unparsable_dead_ok — Phase 3.5 D3 repro (unparsable dead arm).
//
// The dead arm's file EXISTS but cannot be parsed. The parser's eager load
// still opens and parses it pre-fix, so the compile rejects with an
// `error[3048]`-class diagnostic (or a parser error on `unparsable.zig`).
// Post-fix the dead arm is never opened, so the file's content is irrelevant.
//
// GREEN (post-fix): stdout `exists ping\nunparsable dead ok\n`, rc 0.
const std = @import("std");

const impl = if (1 == 1) @import("exists.zig") else @import("unparsable.zig");

pub fn main() void {
    impl.ping();
    std.io.write("unparsable dead ok\n");
}
