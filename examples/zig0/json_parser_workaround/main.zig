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
    while (i < level) {
        __bootstrap_print("  ");
        i += 1;
    }
}

fn printValue(val: json.JsonValue, level: usize) void {
    __bootstrap_print("DEBUG: val.tag=");
    __bootstrap_print_int(@enumToInt(val.tag));
    __bootstrap_print("\n");
    if (val.tag == json.JsonValueTag.Null) {
        __bootstrap_print("null");
    } else if (val.tag == json.JsonValueTag.Boolean) {
        __bootstrap_print("DEBUG: boolean=");
        if (val.data.Boolean) {
            __bootstrap_print("true");
        } else {
            __bootstrap_print("false");
        }
    } else if (val.tag == json.JsonValueTag.Number) {
        __bootstrap_print("<number>");
    } else if (val.tag == json.JsonValueTag.String) {
        const s = val.data.String;
        __bootstrap_print("\"");
        printSlice(s);
        __bootstrap_print("\"");
    } else if (val.tag == json.JsonValueTag.Array) {
        const arr = val.data.Array;
        __bootstrap_print("[");
        if (arr.len > 0) {
            __bootstrap_print("\n");
            var i: usize = 0;
            while (i < arr.len) {
                printIndent(level + 1);
                printValue(arr[i], level + 1);
                if (i < arr.len - 1) __bootstrap_print(",");
                __bootstrap_print("\n");
                i += 1;
            }
            printIndent(level);
        }
        __bootstrap_print("]");
    } else if (val.tag == json.JsonValueTag.Object) {
        const obj = val.data.Object;
        __bootstrap_print("{");
        if (obj.len > 0) {
            __bootstrap_print("\n");
            var i: usize = 0;
            while (i < obj.len) {
                printIndent(level + 1);
                __bootstrap_print("\"");
                printSlice(obj[i].key);
                __bootstrap_print("\": ");
                const next_val_ptr = obj[i].value;
                printValue(next_val_ptr.*, level + 1);
                if (i < obj.len - 1) __bootstrap_print(",");
                __bootstrap_print("\n");
                i += 1;
            }
            printIndent(level);
        }
        __bootstrap_print("}");
    }
}

pub fn main() void {
    const v: json.JsonValue = undefined;
    _ = v;
    const arena = &zig_default_arena;
    __bootstrap_print("Starting main\n");
    const content = file.readFile(arena, "test.json") catch |err| {
        __bootstrap_print("Error reading file: ");
        __bootstrap_print_int(@enumToInt(err));
        __bootstrap_print("\n");
        return;
    };
    __bootstrap_print("Parsed JSON successfully\n");
    const parsed = json.parseJson(arena, content) catch |err| {
        __bootstrap_print("Parse error: ");
        __bootstrap_print_int(@enumToInt(err));
        __bootstrap_print("\n");
        return;
    };
    printValue(parsed.*, 0);
    __bootstrap_print("\n");
}
