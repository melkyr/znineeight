const file = @import("file.zig");
const json = @import("json.zig");

extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(val: i32) void;
extern var zig_default_arena: *void; // provided by runtime

fn printIndent(level: usize) void {
    var i: usize = 0;
    while (i < level) {
        __bootstrap_print(@ptrCast([*]const u8, "  "));
        i += 1;
    }
}

fn printValue(val: json.JsonValue, level: usize) void {
    if (val.tag == json.JsonValueTag.Null) {
        __bootstrap_print(@ptrCast([*]const u8, "null"));
    } else if (val.tag == json.JsonValueTag.BoolValue) {
        if (val.data.BoolValue) {
            __bootstrap_print(@ptrCast([*]const u8, "true"));
        } else {
            __bootstrap_print(@ptrCast([*]const u8, "false"));
        }
    } else if (val.tag == json.JsonValueTag.Number) {
        __bootstrap_print(@ptrCast([*]const u8, "[number]"));
    } else if (val.tag == json.JsonValueTag.StringValue) {
        __bootstrap_print(@ptrCast([*]const u8, "\""));
        __bootstrap_print(@ptrCast([*]const u8, "[string]"));
        __bootstrap_print(@ptrCast([*]const u8, "\""));
    } else if (val.tag == json.JsonValueTag.ArrayValue) {
        __bootstrap_print(@ptrCast([*]const u8, "[\n"));
        const arr = val.data.ArrayValue;
        var i: usize = 0;
        while (i < arr.len) {
            printIndent(level + 1);
            printValue(arr[i], level + 1);
            if (i < arr.len - 1) { __bootstrap_print(@ptrCast([*]const u8, ",")); }
            __bootstrap_print(@ptrCast([*]const u8, "\n"));
            i += 1;
        }
        printIndent(level);
        __bootstrap_print(@ptrCast([*]const u8, "]"));
    } else if (val.tag == json.JsonValueTag.ObjectValue) {
        __bootstrap_print(@ptrCast([*]const u8, "{\n"));
        const obj = val.data.ObjectValue;
        var i: usize = 0;
        while (i < obj.len) {
            printIndent(level + 1);
            __bootstrap_print(@ptrCast([*]const u8, "\""));
            __bootstrap_print(@ptrCast([*]const u8, "[key]"));
            __bootstrap_print(@ptrCast([*]const u8, "\": "));
            printValue(obj[i].value.*, level + 1);
            if (i < obj.len - 1) { __bootstrap_print(@ptrCast([*]const u8, ",")); }
            __bootstrap_print(@ptrCast([*]const u8, "\n"));
            i += 1;
        }
        printIndent(level);
        __bootstrap_print(@ptrCast([*]const u8, "}"));
    }
}

pub fn main() void {
    const arena = &zig_default_arena;
    const path: []const u8 = "test.json";

    const content = file.readFile(arena, path) catch |err| {
        __bootstrap_print(@ptrCast([*]const u8, "Error reading file\n"));
        return;
    };

    const parsed = json.parseJson(arena, content) catch |err| {
        __bootstrap_print(@ptrCast([*]const u8, "Parse error: "));
        __bootstrap_print_int(@enumToInt(err));
        __bootstrap_print(@ptrCast([*]const u8, "\n"));
        return;
    };

    __bootstrap_print(@ptrCast([*]const u8, "JSON parsed successfully:\n"));
    printValue(parsed, 0);
    __bootstrap_print(@ptrCast([*]const u8, "\n"));
}
