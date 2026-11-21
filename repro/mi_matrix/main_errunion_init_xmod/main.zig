// main_errunion_init_xmod — strict-C89 `main` wrapper declaration order.
//
// The module-global `g` has a runtime initializer, so the wrapper emits
// `__module_init()` calls at the top of `main`. An error-union `main` return
// (`pub fn main() !void`) also needs a local `zT_main_result`. In strict C89
// that local must be declared BEFORE the module-init calls (block
// declarations precede statements); the assignment/return stay after them.
//
// Contract: emission rc=0, all emitted .c clean under
// `gcc -std=c89 -pedantic -Werror=declaration-after-statement -fsyntax-only`
// (gate_strict_c89.sh), and runtime stdout `41\n` with rc 0.
const std = @import("std");

fn compute() i32 {
    return 41;
}

var g: i32 = compute();

pub fn main() !void {
    std.io.printInt(g);
    std.io.writeByte('\n');
}
