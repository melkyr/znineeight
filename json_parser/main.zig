const file = @import("file.zig");
const json = @import("json.zig");

extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(i: i32) void;
extern var zig_default_arena: *void;

fn printIndent(level: usize) void {
    var i: usize = 0;
    while (i < level) {
        __bootstrap_print("  ".ptr);
        i += 1;
    }
}

fn printValue(val: json.JsonValue, level: usize) void {
    switch (val) {
        .Null => __bootstrap_print("null".ptr),
        .Boolean => |b| {
            if (b) __bootstrap_print("true".ptr) else __bootstrap_print("false".ptr);
        },
        .Number => |n| {
            __bootstrap_print("<number>".ptr);
        },
        .String => |s| {
            __bootstrap_print("\"".ptr);
            __bootstrap_print(s.ptr);
            __bootstrap_print("\"".ptr);
        },
        .Array => |arr| {
            __bootstrap_print("[".ptr);
            if (arr.len > 0) {
                __bootstrap_print("\n".ptr);
                var i: usize = 0;
                while (i < arr.len) {
                    printIndent(level + 1);
                    printValue(arr[i], level + 1);
                    if (i < arr.len - 1) __bootstrap_print(",".ptr);
                    __bootstrap_print("\n".ptr);
                    i += 1;
                }
                printIndent(level);
            }
            __bootstrap_print("]".ptr);
        },
        .Object => |obj| {
            __bootstrap_print("{".ptr);
            if (obj.len > 0) {
                __bootstrap_print("\n".ptr);
                var i: usize = 0;
                while (i < obj.len) {
                    printIndent(level + 1);
                    __bootstrap_print("\"".ptr);
                    __bootstrap_print(obj[i].key.ptr);
                    __bootstrap_print("\": ".ptr);
                    printValue(obj[i].value, level + 1);
                    if (i < obj.len - 1) __bootstrap_print(",".ptr);
                    __bootstrap_print("\n".ptr);
                    i += 1;
                }
                printIndent(level);
            }
            __bootstrap_print("}".ptr);
        },
    }
}

pub fn main() void {
    const arena_ptr = zig_default_arena;
    const content = file.readFile(arena_ptr, "test.json") catch |err| {
        __bootstrap_print("Error reading file: ".ptr);
        __bootstrap_print_int(@enumToInt(err));
        __bootstrap_print("\n".ptr);
        return;
    };
    const parsed = json.parseJson(arena_ptr, content) catch |err| {
        __bootstrap_print("Parse error: ".ptr);
        __bootstrap_print_int(@enumToInt(err));
        __bootstrap_print("\n".ptr);
        return;
    };
    printValue(parsed, 0);
    __bootstrap_print("\n".ptr);
}
