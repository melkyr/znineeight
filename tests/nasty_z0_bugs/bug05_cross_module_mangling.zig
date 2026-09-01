// Cross-module name mangling: bare import vs qualified module call.
// Run: ./zig0 -o /tmp/repro.c tests/nasty_z0_bugs/bug05_cross_module_mangling.zig
// Expected: linker error for stringInternerIntern with wrong prefix.

const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;

// BROKEN: bare import → wrong module hash prefix in generated code
// const stringInternerIntern = @import("string_interner.zig").stringInternerIntern;

// WORKING: qualified module call → correct prefix
pub fn doSomething(interner: *StringInterner, text: []const u8) void {
    _ = interner_mod.stringInternerIntern(interner, text);
}

pub const Sand = struct {
    start: [*]u8,
    pos: usize,
    end: usize,
    peak: usize,
};

pub fn main() void {}
