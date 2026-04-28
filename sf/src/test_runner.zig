const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const StringInterner = @import("string_interner.zig").StringInterner;
const Lexer = @import("lexer.zig").Lexer;
const sm_mod = @import("source_manager.zig");

pub const TestResult = struct {
    name: []const u8,
    passed: bool,
    message: []const u8,
};

pub const TestResultArrayList = struct {
    items: [*]TestResult,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn testResultArrayListInit(allocator: *Sand) TestResultArrayList {
    return TestResultArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn testResultArrayListEnsureCapacity(self: *TestResultArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 20) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]TestResult, raw);
    var i: usize = 0;
    while (i < self.len) {
        new_items[i] = self.items[i];
        i += 1;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn testResultArrayListAppend(self: *TestResultArrayList, value: TestResult) void {
    testResultArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn testResultArrayListGetSlice(self: *TestResultArrayList) []TestResult {
    return self.items[0..self.len];
}

pub const TestRunner = struct {
    results: *TestResultArrayList,
    allocator: *Sand,
};

pub fn testRunnerInit(allocator: *Sand) TestRunner {
    var r_raw = alloc_mod.sandAlloc(allocator, @intCast(usize, 16), @intCast(usize, 4)) catch unreachable;
    var r_ptr = @ptrCast(*TestResultArrayList, r_raw);
    r_ptr.* = testResultArrayListInit(allocator);
    return TestRunner{
        .results = r_ptr,
        .allocator = allocator,
    };
}

pub fn testRunnerAddResult(self: *TestRunner, name: []const u8, passed: bool, message: []const u8) void {
    testResultArrayListAppend(self.results, TestResult{
        .name = name,
        .passed = passed,
        .message = message,
    });
}

pub fn testRunnerReport(self: *TestRunner) void {
    var results = testResultArrayListGetSlice(self.results);
    var i: usize = 0;
    while (i < results.len) {
        i += 1;
    }
    _ = results;
}

pub fn testRunnerAllPassed(self: *TestRunner) bool {
    var results = testResultArrayListGetSlice(self.results);
    var i: usize = 0;
    while (i < results.len) {
        if (!results[i].passed) return false;
        i += 1;
    }
    return true;
}

pub fn parseTestSource(arena: *Sand, source: []const u8, interner: *StringInterner, diag: *DiagnosticCollector, source_man: *SourceManager) u32 {
    var file_id = sm_mod.sourceManagerAddFile(source_man, "test.zig", source);
    var lexer = Lexer.init(source, file_id, interner, diag, arena);
    while (true) {
        var tok = lexer.nextToken();
        if (tok.kind == .eof) break;
    }
    _ = file_id;
    return @intCast(u32, 0);
}

pub fn assert_true(condition: bool, msg: []const u8) void {
    if (!condition) failAndPanic(msg);
}

pub fn assert_eq_u32(actual: u32, expected: u32, msg: []const u8) void {
    if (actual != expected) failAndPanic(msg);
}

pub fn assert_eq_i32(actual: i32, expected: i32, msg: []const u8) void {
    if (actual != expected) failAndPanic(msg);
}

pub fn assert_eq_u64(actual: u64, expected: u64, msg: []const u8) void {
    if (actual != expected) failAndPanic(msg);
}

pub fn assert_eq_str(actual: []const u8, expected: []const u8, msg: []const u8) void {
    if (actual.len != expected.len) failAndPanic(msg);
    var i: usize = 0;
    while (i < actual.len) {
        if (actual[i] != expected[i]) failAndPanic(msg);
        i += 1;
    }
}

fn failAndPanic(msg: []const u8) noreturn {
    @panic(msg);
}
