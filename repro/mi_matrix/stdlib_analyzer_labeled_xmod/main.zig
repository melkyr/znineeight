// stdlib_analyzer_labeled_xmod — FX8 runtime fixture for the `labeled_stmt`
// analyzer-traversal hole (FX2-I §2.3 f1 / §3 T4; repro/labeled_analyzer.z98).
//
// DEFECT pinned (FX8): `visitStatement` had no `AstKind.labeled_stmt` arm, so
// a labeled block or labeled loop fell to the `on_stmt` no-op and everything
// inside stayed invisible to the null/lifetime/double-free passes — an
// allocation leak inside a labeled block was silent rc 0 (probe f1), a null
// deref / double free inside a labeled construct was silent, and defers inside
// labeled constructs were never queued.
//
// FIX (FX8): `visitStatement` unwraps `labeled_stmt` and routes `child_0`
// through the same statement walk (`visitStatement(...)`), so labeled blocks
// and labeled loops get exactly the treatment FX2 gave switch prongs and bare
// blocks (and unlabeled loops): defers enqueue at the walked `current_depth`
// and drain at their own scope exit; the leak/null/lifetime/double-free
// handlers see the body. Lowering alone owns defer execution, so runtime
// behavior is unchanged (analyzer-only fix).
//
// Contract: the stdout rows below, rc 0, byte-exact 3x. `ops` is
// @panic-guarded (5 defer executions + 5 stub allocations = 10). Analyzer
// diagnostics are NOT runtime-visible; the POST census for this program is
// exactly:
//   warning[3038] x7  (if leak x1, bare-block leak x2 — the operator-accepted
//                      duplicate, labeled-block leak x2 [label-block exit +
//                      function exit, same state], labeled-while leak x1
//                      [body scope], labeled-for leak x1 [body scope])
// PRE (`ff059647`) emitted only warning[3038] x3 (the if + bare-block
// controls); the labeled shapes below were silent.
//   if-body
//   if-defer
//   block-body
//   block-defer
//   lbl-body
//   lbl-defer
//   loop-body
//   loop-defer
//   loop-body
//   loop-defer
//   if-leak
//   block-leak
//   lbl-block-leak
//   lbl-while-leak
//   lbl-for-leak
//   done
const std = @import("std");

var heap: [4096]u8 = undefined;
var heap_off: usize = 0;
var ops: i32 = 0;

fn arena_alloc(size: usize) *u8 {
    var p: *u8 = &heap[heap_off];
    heap_off += size;
    ops += 1;
    return p;
}

fn arena_free(alloc: usize, p: *u8) void {
    _ = alloc;
    _ = p;
    ops += 1;
}

fn ifDefer(c: bool) void {
    if (c) {
        defer ops += 1;
        defer std.io.print("if-defer\n", .{});
        std.io.print("if-body\n", .{});
    }
}

fn blockDefer() void {
    {
        defer ops += 1;
        defer std.io.print("block-defer\n", .{});
        std.io.print("block-body\n", .{});
    }
}

fn labeledBlockDefer() void {
    blk: {
        defer ops += 1;
        defer std.io.print("lbl-defer\n", .{});
        std.io.print("lbl-body\n", .{});
    }
}

fn labeledLoopDefer() void {
    var i: i32 = 0;
    lw: while (i < 2) {
        defer ops += 1;
        defer std.io.print("loop-defer\n", .{});
        std.io.print("loop-body\n", .{});
        i += 1;
    }
}

fn leakInIf(c: bool) void {
    if (c) {
        const p = arena_alloc(8);
        _ = p;
    }
    std.io.print("if-leak\n", .{});
}

fn leakInBlock() void {
    {
        const p = arena_alloc(8);
        _ = p;
    }
    std.io.print("block-leak\n", .{});
}

fn leakInLabeledBlock() void {
    blk: {
        const p = arena_alloc(8);
        _ = p;
    }
    std.io.print("lbl-block-leak\n", .{});
}

fn leakInLabeledWhile(c: bool) void {
    lw: while (c) {
        const p = arena_alloc(8);
        _ = p;
        break :lw;
    }
    std.io.print("lbl-while-leak\n", .{});
}

fn leakInLabeledFor() void {
    lf: for (0..1) |i| {
        _ = i;
        const p = arena_alloc(8);
        _ = p;
    }
    std.io.print("lbl-for-leak\n", .{});
}

pub fn main() void {
    ifDefer(true);
    blockDefer();
    labeledBlockDefer();
    labeledLoopDefer();
    leakInIf(true);
    leakInBlock();
    leakInLabeledBlock();
    leakInLabeledWhile(true);
    leakInLabeledFor();
    if (ops != 10) {
        @panic("defer/alloc count after labeled traversal");
    }
    std.io.print("done\n", .{});
}
