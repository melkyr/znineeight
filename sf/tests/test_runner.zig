// zig1 test runner
// Usage: zig1 --test [--test-filter name]
//
// Discovers and runs all test_* functions in the project.
// Reports passed/failed/skipped counts.

pub const TestResult = struct {
    name: []const u8,
    passed: bool,
    message: []const u8,
};

pub const TestRunner = struct {
    results: std.ArrayList(TestResult),

    pub fn init(allocator: *std.mem.Allocator) TestRunner {}
    pub fn run(self: *TestRunner) !void {}
    pub fn report(self: *TestRunner) void {}
};

// Assert primitives for Z98
pub fn assert_true(ok: bool) void {
    if (!ok) @panic("assert_true failed");
}

pub fn assert_eq_u32(expected: u32, actual: u32) void {
    if (expected != actual) {
        @panic("assert_eq_u32 failed");
    }
}

pub fn assert_eq_str(expected: []const u8, actual: []const u8) void {
    if (!mem_eql(expected, actual)) {
        @panic("assert_eq_str failed");
    }
}

pub fn assert_eq_i32(expected: i32, actual: i32) void {
    if (expected != actual) {
        @panic("assert_eq_i32 failed");
    }
}

pub fn assert_eq_u64(expected: u64, actual: u64) void {
    if (expected != actual) {
        @panic("assert_eq_u64 failed");
    }
}

fn mem_eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) {
        if (a[i] != b[i]) return false;
        i += 1;
    }
    return true;
}

const std = @import("std");
