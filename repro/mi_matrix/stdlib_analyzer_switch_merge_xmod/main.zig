// stdlib_analyzer_switch_merge_xmod — FX7 runtime fixture for switch-merge
// prong-name propagation (repro/switch_merge.z98, FX2-I §2.3).
//
// DEFECT pinned (FX7): visitStatement's `swt_ex` arm merged each prong with
// `stateMapMergeStates(state, state, ps, 99)` (`sf/src/analyzer.zig`), whose
// second loop cannot ADD a name that exists only in the prong state. A pointer
// assigned `arena_alloc(...)` in a switch prong was therefore untracked after
// the switch: the later `arena_free` read "untracked" (WARN_6006 / 3039).
//
// FIX (FX7): after each prong merge in the double-free pass, prong-only names
// are inserted into the enclosing state as `AllocState.unknown` (5) — the
// sound conservative join of "maybe allocated here, untracked on the other
// prongs"; neither `allocated` (no spurious leak) nor absent/untracked (no
// spurious WARN_6006). Emitted C and runtime behavior are unchanged
// (analyzer-only fix).
//
// Contract: the runtime rows below, rc 0, byte-exact 3x. `ops` @panic-guards
// the nine alloc/free stub calls. Analyzer diagnostics are NOT runtime-visible;
// the POST census for this program is exactly:
//   warning[3038] x7  (then-block a1, bare-block a2 x2, prong a3,
//                      if then-block a4, bare-block a5, switch prong a6)
//   warning[3039] x1  (a4's if-allocated name freed after the if, which the
//                      if-merge still drops — the unchanged control)
// PRE (base `1a258bd4`) emitted the same 3038s plus `warning[3039]` x2 (a4 and
// a6).
//   if-leak
//   block-leak
//   prong-leak
//   if-free
//   block-free
//   prong-free
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

fn leakInProng(c: bool) void {
    switch (c) {
        true => {
            const p = arena_alloc(8);
            _ = p;
        },
        else => {},
    }
    std.io.print("prong-leak\n", .{});
}

fn freeAfterIf(c: bool) void {
    var p: *u8 = undefined;
    if (c) {
        p = arena_alloc(8);
    }
    arena_free(0, p);
    std.io.print("if-free\n", .{});
}

fn freeAfterBlock(c: bool) void {
    var p: *u8 = undefined;
    {
        p = arena_alloc(8);
    }
    arena_free(0, p);
    std.io.print("block-free\n", .{});
}

fn freeAfterSwitch(c: bool) void {
    var p: *u8 = undefined;
    switch (c) {
        true => {
            p = arena_alloc(8);
        },
        else => {},
    }
    arena_free(0, p);
    std.io.print("prong-free\n", .{});
}

pub fn main() void {
    leakInIf(true);
    leakInBlock();
    leakInProng(true);
    freeAfterIf(true);
    freeAfterBlock(true);
    freeAfterSwitch(true);
    if (ops != 9) {
        @panic("alloc/free count after switch/block");
    }
    std.io.print("done\n", .{});
}
