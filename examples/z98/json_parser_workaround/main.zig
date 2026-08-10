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
    while (i < level) {
        std.io.print("  ");
        i += 1;
    }
}

fn printValue(val: json.JsonValue, level: usize) void {
    std.io.print("DEBUG: val.tag=");
    std.io.printInt(@enumToInt(val.tag));
    std.io.print("\n");
    if (val.tag == json.JsonValueTag.Null) {
        std.io.print("null");
    } else if (val.tag == json.JsonValueTag.Boolean) {
        std.io.print("DEBUG: boolean=");
        if (val.data.Boolean) {
            std.io.print("true");
        } else {
            std.io.print("false");
        }
    } else if (val.tag == json.JsonValueTag.Number) {
        std.io.print("<number>");
    } else if (val.tag == json.JsonValueTag.String) {
        const s = val.data.String;
        std.io.print("\"");
        printSlice(s);
        std.io.print("\"");
    } else if (val.tag == json.JsonValueTag.Array) {
        const arr = val.data.Array;
        std.io.print("[");
        if (arr.len > 0) {
            std.io.print("\n");
            var i: usize = 0;
            while (i < arr.len) {
                printIndent(level + 1);
                printValue(arr[i], level + 1);
                if (i < arr.len - 1) std.io.print(",");
                std.io.print("\n");
                i += 1;
            }
            printIndent(level);
        }
        std.io.print("]");
    } else if (val.tag == json.JsonValueTag.Object) {
        const obj = val.data.Object;
        std.io.print("{");
        if (obj.len > 0) {
            std.io.print("\n");
            var i: usize = 0;
            while (i < obj.len) {
                printIndent(level + 1);
                std.io.print("\"");
                printSlice(obj[i].key);
                std.io.print("\": ");
                const next_val_ptr = obj[i].value;
                printValue(next_val_ptr.*, level + 1);
                if (i < obj.len - 1) std.io.print(",");
                std.io.print("\n");
                i += 1;
            }
            printIndent(level);
        }
        std.io.print("}");
    }
}

pub fn main() void {
    const v: json.JsonValue = undefined;
    _ = v;
    const arena = &zig_default_arena;
    std.io.print("Starting main\n");
    const content = file.readFile(arena, "test.json") catch |err| {
        std.io.print("Error reading file: ");
        std.io.printInt(@enumToInt(err));
        std.io.print("\n");
        return;
    };
    std.io.print("Parsed JSON successfully\n");
    const parsed = json.parseJson(arena, content) catch |err| {
        std.io.print("Parse error: ");
        std.io.printInt(@enumToInt(err));
        std.io.print("\n");
        return;
    };
    printValue(parsed.*, 0);
    std.io.print("\n");
}
