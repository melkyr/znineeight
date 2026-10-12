const file = @import("file.zig");
const json = @import("json.zig");

extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(i: i32) void;
extern var zig_default_arena: *void;

fn printSlice(s: []const u8) void {
    __bootstrap_write(s.ptr, s.len);
}

extern fn __bootstrap_write(s: [*]const u8, len: usize) void;

fn printIndent(level: usize) void {
    var i: usize = 0;
    while (i < level) : (i += 1) {
        __bootstrap_print("  ");
    }
}

fn printValue(val: json.JsonValue, level: usize) void {
    switch (val) {
        .Null => {
             __bootstrap_print("null");
        },
        .Boolean => |b| {
            if (b) {
                __bootstrap_print("true");
            } else {
                __bootstrap_print("false");
            }
        },
        .Number => |n| {
            __bootstrap_print("<number>");
        },
        .String => |s| {
            __bootstrap_print("\"");
            printSlice(s);
            __bootstrap_print("\"");
        },
        .Array => |arr| {
            __bootstrap_print("[");
            if (arr.len > 0) {
                __bootstrap_print("\n");
                for (arr) |item, i| {
                    printIndent(level + 1);
                    printValue(item, level + 1);
                    if (i < arr.len - 1) __bootstrap_print(",");
                    __bootstrap_print("\n");
                }
                printIndent(level);
            }
            __bootstrap_print("]");
        },
        .Object => |obj| {
            __bootstrap_print("{");
            if (obj.len > 0) {
                __bootstrap_print("\n");
                for (obj) |item, i| {
                    printIndent(level + 1);
                    __bootstrap_print("\"");
                    printSlice(item.key);
                    __bootstrap_print("\": ");

                    // Optional unwrapping capture
                    if (item.value) |v| {
                        printValue(v.*, level + 1);
                    } else {
                        __bootstrap_print("null");
                    }

                    if (i < obj.len - 1) __bootstrap_print(",");
                    __bootstrap_print("\n");
                }
                printIndent(level);
            }
            __bootstrap_print("}");
        },
    }
}

pub fn main() void {
    const v: json.JsonValue = undefined;
    _ = v;
    const arena = &zig_default_arena;
    __bootstrap_print("Loading file...\n");

    // Use catch for error handling
    const content = file.readFile(arena, "test.json") catch |err| {
        __bootstrap_print("Error reading file: ");
        __bootstrap_print_int(@enumToInt(err));
        __bootstrap_print("\n");
        return;
    };

    __bootstrap_print("Parsing JSON...\n");
    const parsed = json.parseJson(arena, content) catch |err| {
        __bootstrap_print("Parse error: ");
        __bootstrap_print_int(@enumToInt(err));
        __bootstrap_print("\n");
        return;
    };

    __bootstrap_print("Result:\n");
    printValue(parsed.*, 0);
    __bootstrap_print("\nDone.\n");
}
