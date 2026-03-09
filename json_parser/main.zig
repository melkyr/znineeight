// main.zig
const file = @import("file.zig");
const json = @import("json.zig");

extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(i: i32) void;
extern var zig_default_arena: void;

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
    } else if (val.tag == json.JsonValueTag.Boolean) {
        if (val.data.boolean) {
            __bootstrap_print(@ptrCast([*]const u8, "true"));
        } else {
            __bootstrap_print(@ptrCast([*]const u8, "false"));
        }
    } else if (val.tag == json.JsonValueTag.Number) {
        __bootstrap_print(@ptrCast([*]const u8, "<number>"));
    } else if (val.tag == json.JsonValueTag.String) {
        const s: []const u8 = val.data.string;
        __bootstrap_print(@ptrCast([*]const u8, "\""));
        __bootstrap_print(s.ptr); // Warning: not null terminated in Zig, but __bootstrap_print uses fputs
        __bootstrap_print(@ptrCast([*]const u8, "\""));
    } else if (val.tag == json.JsonValueTag.Array) {
        __bootstrap_print(@ptrCast([*]const u8, "["));
        const arr = val.data.array;
        if (arr.len > 0) {
            __bootstrap_print(@ptrCast([*]const u8, "\n"));
            var i: usize = 0;
            while (i < arr.len) {
                printIndent(level + 1);
                printValue(arr[i], level + 1);
                if (i < arr.len - 1) {
                    __bootstrap_print(@ptrCast([*]const u8, ","));
                }
                __bootstrap_print(@ptrCast([*]const u8, "\n"));
                i += 1;
            }
            printIndent(level);
        }
        __bootstrap_print(@ptrCast([*]const u8, "]"));
    } else if (val.tag == json.JsonValueTag.Object) {
        __bootstrap_print(@ptrCast([*]const u8, "{"));
        const obj = val.data.object;
        if (obj.len > 0) {
            __bootstrap_print(@ptrCast([*]const u8, "\n"));
            var i: usize = 0;
            while (i < obj.len) {
                printIndent(level + 1);
                const key_s: []const u8 = obj[i].key;
                __bootstrap_print(@ptrCast([*]const u8, "\""));
                __bootstrap_print(key_s.ptr);
                __bootstrap_print(@ptrCast([*]const u8, "\": "));
                printValue(obj[i].value.*, level + 1);
                if (i < obj.len - 1) {
                    __bootstrap_print(@ptrCast([*]const u8, ","));
                }
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
    const content = file.readFile(arena, "../test.json") catch |err| {
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
