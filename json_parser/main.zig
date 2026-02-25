const file = @import("file.zig");
const json = @import("json.zig");

extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(val: i32) void;
extern var zig_default_arena: *void; // provided by runtime

pub fn main() void {
    const arena = &zig_default_arena;
    const path = @ptrCast([]const u8, "test.json");

    // stress test the compilation pipeline
    const content = file.readFile(arena, path) catch |err| {
        __bootstrap_print(@ptrCast([*]const u8, "Error reading file\n"));
        return;
    };

    const parsed = json.parseJson(arena, content) catch |err| {
        __bootstrap_print(@ptrCast([*]const u8, "Parse error\n"));
        return;
    };

    __bootstrap_print(@ptrCast([*]const u8, "JSON parsed successfully\n"));
}
