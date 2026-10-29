// Off-corpus mutable-for fixture (Task 3 Step 1a; Task 4 e2e). Excluded from
// the corpus universe by the `known_excluded` guard in
// scripts/corpus/list_corpus_dirs.sh. The printed values prove the capture is
// a pointer into the caller's buffer (`x.* = 1` mutates `buf` in place).
const std = @import("std");

fn take(p: *u32) void {
    p.* = p.* + 1;
}

fn fill(s: []u32) void {
    for (s) |*x| {
        take(x);
        x.* = 1;
    }
}

pub fn main() void {
    var buf: [3]u32 = .{ 0, 0, 0 };
    fill(buf[0..]);
    std.io.printInt(@intCast(i32, buf[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, buf[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, buf[2]));
    std.io.writeByte('\n');
}
