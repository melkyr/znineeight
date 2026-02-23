const file = @import("file.zig");
const json = @import("json.zig");

const JsonValue = json.JsonValue;
const JsonValueTag = json.JsonValueTag;

extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(val: i32) void;
extern var zig_default_arena: *void;

fn printIndent(level: usize) void {
    var i: usize = 0;
    while (i < level) {
        __bootstrap_print("  ");
        i += 1;
    }
}

fn printValue(val: JsonValue, level: usize) void {
    const tag = val.tag;
    if (tag == JsonValueTag.Null) {
        __bootstrap_print("null");
    } else if (tag == JsonValueTag.Boolean) {
        if (val.data.boolean) { __bootstrap_print("true"); } else { __bootstrap_print("false"); }
    } else if (tag == JsonValueTag.Number) {
        __bootstrap_print("number");
    } else if (tag == JsonValueTag.String) {
        __bootstrap_print("\"");
        __bootstrap_print(@ptrCast([*]const u8, val.data.string));
        __bootstrap_print("\"");
    } else if (tag == JsonValueTag.Array) {
        const arr = val.data.array;
        __bootstrap_print("[");
        if (arr.len > 0) {
            __bootstrap_print("\n");
            var i: usize = 0;
            while (i < arr.len) {
                printIndent(level + 1);
                printValue(arr[i], level + 1);
                if (i < arr.len - 1) { __bootstrap_print(","); }
                __bootstrap_print("\n");
                i += 1;
            }
            printIndent(level);
        }
        __bootstrap_print("]");
    } else if (tag == JsonValueTag.Object) {
        const obj = val.data.object;
        __bootstrap_print("{");
        if (obj.len > 0) {
            __bootstrap_print("\n");
            var i: usize = 0;
            while (i < obj.len) {
                printIndent(level + 1);
                __bootstrap_print("\"");
                __bootstrap_print(@ptrCast([*]const u8, obj[i].key));
                __bootstrap_print("\": ");
                printValue(obj[i].value.*, level + 1);
                if (i < obj.len - 1) { __bootstrap_print(","); }
                __bootstrap_print("\n");
                i += 1;
            }
            printIndent(level);
        }
        __bootstrap_print("}");
    }
}

pub fn main() void {
    const arena = &zig_default_arena;
    const content = file.readFile(arena, "test.json") catch |err| {
        __bootstrap_print("Error reading file\n");
        return;
    };

    const parsed = json.parseJson(arena, content) catch |err| {
        __bootstrap_print("Parse error\n");
        return;
    };

    printValue(parsed, 0);
    __bootstrap_print("\n");
}
