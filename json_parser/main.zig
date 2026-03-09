const file = @import("file.zig");
const json = @import("json.zig");

extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(val: i32) void;
extern var zig_default_arena: *void;

fn printIndent(level: usize) void {
    var i: usize = 0;
    while (i < level) {
        __bootstrap_print(@ptrCast([*]const u8, "  "));
        i += 1;
    }
}

fn printValue(val: json.JsonValue, level: usize) void {
    const tag = val.tag;
    if (tag == json.JsonValueTag.Null) {
        __bootstrap_print(@ptrCast([*]const u8, "null"));
    } else if (tag == json.JsonValueTag.Boolean) {
        if (val.data.Boolean) {
            __bootstrap_print(@ptrCast([*]const u8, "true"));
        } else {
            __bootstrap_print(@ptrCast([*]const u8, "false"));
        }
    } else if (tag == json.JsonValueTag.Number) {
        __bootstrap_print(@ptrCast([*]const u8, "number"));
    } else if (tag == json.JsonValueTag.String) {
        __bootstrap_print(@ptrCast([*]const u8, "\""));
        __bootstrap_print(@ptrCast([*]const u8, val.data.String.ptr));
        __bootstrap_print(@ptrCast([*]const u8, "\""));
    } else if (tag == json.JsonValueTag.Array) {
        const arr = val.data.Array;
        __bootstrap_print(@ptrCast([*]const u8, "["));
        if (arr.len > 0) {
            __bootstrap_print(@ptrCast([*]const u8, "\n"));
            var i: usize = 0;
            while (i < arr.len) {
                printIndent(level + 1);
                printValue(arr[i], level + 1);
                if (i < arr.len - 1) { __bootstrap_print(@ptrCast([*]const u8, ",")); }
                __bootstrap_print(@ptrCast([*]const u8, "\n"));
                i += 1;
            }
            printIndent(level);
        }
        __bootstrap_print(@ptrCast([*]const u8, "]"));
    } else if (tag == json.JsonValueTag.Object) {
        const obj = val.data.Object;
        __bootstrap_print(@ptrCast([*]const u8, "{"));
        if (obj.len > 0) {
            __bootstrap_print(@ptrCast([*]const u8, "\n"));
            var i: usize = 0;
            while (i < obj.len) {
                printIndent(level + 1);
                __bootstrap_print(@ptrCast([*]const u8, "\""));
                __bootstrap_print(@ptrCast([*]const u8, obj[i].key.ptr));
                __bootstrap_print(@ptrCast([*]const u8, "\": "));
                printValue(obj[i].value.*, level + 1);
                if (i < obj.len - 1) { __bootstrap_print(@ptrCast([*]const u8, ",")); }
                __bootstrap_print(@ptrCast([*]const u8, "\n"));
                i += 1;
            }
            printIndent(level);
        }
        __bootstrap_print(@ptrCast([*]const u8, "}"));
    }
}

pub fn main() void {
    const arena = &zig_default_arena;
    const path: []const u8 = "test.json";

    const content = file.readFile(arena, path) catch |err| {
        __bootstrap_print(@ptrCast([*]const u8, "Error reading file: "));
        __bootstrap_print_int(@enumToInt(err));
        __bootstrap_print(@ptrCast([*]const u8, "\n"));
        return;
    };

    const parsed = json.parseJson(arena, content) catch |err| {
        __bootstrap_print(@ptrCast([*]const u8, "Parse error: "));
        __bootstrap_print_int(@enumToInt(err));
        __bootstrap_print(@ptrCast([*]const u8, "\n"));
        return;
    };

    printValue(parsed, 0);
    __bootstrap_print(@ptrCast([*]const u8, "\n"));
}
