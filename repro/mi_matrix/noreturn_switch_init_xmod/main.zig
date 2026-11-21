// noreturn_switch_init_xmod — A19 value-position fixture (switch initializer).
// Every prong diverges via `return`, so the switch_expr is noreturn-valued.
// Both non-block and block prong bodies are covered; the annotated initializer
// shape is the one the resolver accepts (a bare inferred `const = switch` is
// rejected by sema as void — out of A19 scope, diagnostic unchanged).
// Contract (GREEN): compiles + runs, prints "10\n11\n20\n21\n".
const std = @import("std");

fn viaSwitchAnnotated(x: i32) i32 {
    const y: i32 = switch (x) {
        0 => return 10,
        else => return 11,
    };
    _ = y;
}

fn viaSwitchBlock(x: i32) i32 {
    const z: i32 = switch (x) {
        0 => {
            return 20;
        },
        else => {
            return 21;
        },
    };
    _ = z;
}

pub fn main() void {
    std.io.printInt(@intCast(i32, viaSwitchAnnotated(0)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaSwitchAnnotated(1)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaSwitchBlock(0)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaSwitchBlock(1)));
    std.io.writeByte('\n');
}
