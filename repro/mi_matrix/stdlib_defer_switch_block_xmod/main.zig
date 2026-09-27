// stdlib_defer_switch_block_xmod — FX2 runtime fixture for the D1 traversal
// extras (repro/vol2_defects/D01_defer_segfault).
//
// DEFECT pinned (D1 extras): a statement switch is parsed as
// `expr_stmt(swt_ex)` (`sf/src/parser.zig`) and the analyzer's `expr_stmt` arm
// only recursed the condition, so the `swt_ex` prong bodies were never walked;
// a bare `block` statement fell to the `on_stmt` no-op. Defers inside them were
// invisible to the null/lifetime/double-free passes.
//
// FIX (FX2): `visitStatement` recurses a statement switch through the `swt_ex`
// arm (which first analyzes the condition, preserving the previous behavior)
// and routes a bare `block` through `walkBlock`, so defers enqueue at the
// walked `current_depth` and drain at their own block exit.
//
// Contract: the stdout rows below, rc 0, byte-exact 3x. Runtime behavior is
// unchanged by definition (analyzer-only fix); the fixture pins the defer
// ordering inside a switch prong and a bare block. The `ops` counter is
// @panic-guarded so a dropped defer cannot silently pass the golden.
//   plain-body
//   plain-defer
//   prong 1
//   prong-defer
//   prong-else
//   block-body
//   block-defer
//   done
const std = @import("std");

var ops: i32 = 0;

fn plain() void {
    defer ops += 1;
    defer std.io.print("plain-defer\n", .{});
    std.io.print("plain-body\n", .{});
}

fn switchDefer(v: i32) void {
    switch (v) {
        1 => {
            defer ops += 1;
            defer std.io.print("prong-defer\n", .{});
            std.io.print("prong {}\n", .{v});
        },
        else => {
            std.io.print("prong-else\n", .{});
        },
    }
}

fn blockDefer() void {
    {
        defer ops += 1;
        defer std.io.print("block-defer\n", .{});
        std.io.print("block-body\n", .{});
    }
}

pub fn main() void {
    plain();
    switchDefer(1);
    switchDefer(2);
    blockDefer();
    if (ops != 3) {
        @panic("defer count after switch/block");
    }
    std.io.print("done\n", .{});
}
