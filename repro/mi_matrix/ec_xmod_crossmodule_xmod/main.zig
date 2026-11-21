// ec_xmod_crossmodule_xmod — extra-children index-side spill, cross-module.
// main.zig contributes module_root decls + block statements + fn_call args;
// lib.zig contributes struct_decl fields + struct_init field inits + blocks.
// The extra-children pool is write-through spilled at -s0; this fixture crosses
// the module boundary so children sourced from both modules are read back.
// Contract: GREEN — dump rc=0, gcc-clean, self-contained link, run rc=0,
// stdout md5 stable x3.
const std = @import("std");
const lib = @import("lib.zig");

pub fn main() void {
    var s: i32 = lib.sum3(@intCast(i32, 10), @intCast(i32, 20), @intCast(i32, 30));
    var p: lib.Pair = lib.makePair(@intCast(i32, 7), @intCast(i32, 9));
    var t: i32 = lib.pairSum(p);
    std.io.printInt(s + t);
}
