const file = @import("file.zig");
const json = @import("json.zig");

const std = @import("std.zig");

@cInclude("zig_runtime.h");
@cInclude("<stdio.h>");
@cInclude("<stdlib.h>");

extern var zig_default_arena: *void;

fn printSlice(s: []const u8) void {
    std.io.write(s);
}

fn printIndent(level: usize) void {
    var i: usize = 0;
    while (i < level) : (i += 1) {
        std.io.print("  ");
    }
}

fn printValue(val: json.JsonValue, level: usize) void {
    switch (val) {
        .Null => {
             std.io.print("null");
        },
        .Boolean => |b| {
            if (b) {
                std.io.print("true");
            } else {
                std.io.print("false");
            }
        },
        .Number => |n| {
            std.io.print("<number>");
        },
        .String => |s| {
            std.io.print("\"");
            printSlice(s);
            std.io.print("\"");
        },
        .Array => |arr| {
            std.io.print("[");
            if (arr.len > 0) {
                std.io.print("\n");
                for (arr) |item, i| {
                    printIndent(level + 1);
                    printValue(item, level + 1);
                    if (i < arr.len - 1) std.io.print(",");
                    std.io.print("\n");
                }
                printIndent(level);
            }
            std.io.print("]");
        },
        .Object => |obj| {
            std.io.print("{");
            if (obj.len > 0) {
                std.io.print("\n");
                for (obj) |item, i| {
                    printIndent(level + 1);
                    std.io.print("\"");
                    printSlice(item.key);
                    std.io.print("\": ");

                    // Optional unwrapping capture
                    if (item.value) |v| {
                        printValue(v.*, level + 1);
                    } else {
                        std.io.print("null");
                    }

                    if (i < obj.len - 1) std.io.print(",");
                    std.io.print("\n");
                }
                printIndent(level);
            }
            std.io.print("}");
        },
    }
}

pub fn main() void {
    const v: json.JsonValue = undefined;
    _ = v;
    const arena = &zig_default_arena;
    std.io.print("Loading file...\n");

    // Use catch for error handling
    const content = file.readFile(arena, "test.json") catch |err| {
        std.io.print("Error reading file: ");
        std.io.printInt(@enumToInt(err));
        std.io.print("\n");
        return;
    };

    std.io.print("Parsing JSON...\n");
    const parsed = json.parseJson(arena, content) catch |err| {
        std.io.print("Parse error: ");
        std.io.printInt(@enumToInt(err));
        std.io.print("\n");
        return;
    };

    std.io.print("Result:\n");
    printValue(parsed.*, 0);
    std.io.print("\nDone.\n");
}
