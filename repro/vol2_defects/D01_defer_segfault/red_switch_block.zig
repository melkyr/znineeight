// D1 (FX2 extras) sibling shape: plain `defer` fn + `defer` inside a switch
// prong + `defer` inside a bare block.
//
// Under the seed these shapes were invisible to the analyzers; under a
// FX2-only compiler the prong defer newly reaches the stale-queue reader
// (SIGSEGV, FX2-I e2), and under FG+FX2 the module compiles/builds/runs rc 0
// with the stdout recorded in NOTES.md. FX2 makes the defers visible to the
// null/lifetime/double-free passes and drains them at their own block exit.
const std = @import("std");

fn plain() void {
    defer std.io.print("plain-defer\n", .{});
    std.io.print("plain-body\n", .{});
}

fn switchDefer() void {
    const v: i32 = 2;
    switch (v) {
        2 => {
            defer std.io.print("switch-defer\n", .{});
            std.io.print("switch {}\n", .{v});
        },
        else => {
            std.io.print("switch-else\n", .{});
        },
    }
}

fn blockDefer() void {
    {
        defer std.io.print("block-defer\n", .{});
        std.io.print("block-body\n", .{});
    }
}

pub fn main() void {
    plain();
    switchDefer();
    blockDefer();
}
