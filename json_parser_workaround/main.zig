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

// WORKAROUND: Pass by pointer and manual field copy to avoid 64-bit ABI layout mismatches
// when running on a 64-bit host. The bootstrap compiler assumes 32-bit.
fn printValue(val_arg: json.JsonValue, level: usize) void {
    // Copy locally to ensure we use the layout the compiler expects
    const tag = val_arg.tag;
    const data = val_arg.data;
    var val: json.JsonValue = undefined;
    val.tag = tag;
    val.data = data;

    if (val.tag == json.JsonValueTag.Null) {
        __bootstrap_print("null");
    } else if (val.tag == json.JsonValueTag.Boolean) {
        if (val.data.boolean) {
            __bootstrap_print("true");
        } else {
            __bootstrap_print("false");
        }
    } else if (val.tag == json.JsonValueTag.Number) {
        // Simple placeholder for numbers as f64 printing is not in runtime
        __bootstrap_print("<number>");
    } else if (val.tag == json.JsonValueTag.String) {
        const s = val.data.string;
        __bootstrap_print("\"");
        printSlice(s);
        __bootstrap_print("\"");
    } else if (val.tag == json.JsonValueTag.Array) {
        const arr = val.data.array;
        __bootstrap_print("[");
        if (arr.len > 0) {
            __bootstrap_print("\n");
            var i: usize = 0;
            while (i < arr.len) {
                printIndent(level + 1);

                // WORKAROUND: manual copy from array element
                const v = arr[i];
                var v_copy: json.JsonValue = undefined;
                v_copy.tag = v.tag;
                v_copy.data = v.data;

                printValue(v_copy, level + 1);
                if (i < arr.len - 1) __bootstrap_print(",");
                __bootstrap_print("\n");
                i += 1;
            }
            printIndent(level);
        }
        __bootstrap_print("]");
    } else if (val.tag == json.JsonValueTag.Object) {
        const obj = val.data.object;
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
                // WORKAROUND: manual field-by-field copy to avoid pointer deref layout issues on 64-bit
                const tag_val = next_val_ptr.tag;
                const data_val = next_val_ptr.data;
                var next_val: json.JsonValue = undefined;
                next_val.tag = tag_val;
                next_val.data = data_val;

                printValue(next_val, level + 1);

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
    const arena = &zig_default_arena;
    const content = file.readFile(arena, "test.json") catch |err| {
        __bootstrap_print("Error reading file: ");
        __bootstrap_print_int(@enumToInt(err));
        __bootstrap_print("\n");
        return;
    };

    const parsed_res = json.parseJson(arena, content) catch |err| {
        __bootstrap_print("Parse error: ");
        __bootstrap_print_int(@enumToInt(err));
        __bootstrap_print("\n");
        return;
    };

    // WORKAROUND: Root copy
    const root_tag = parsed_res.tag;
    const root_data = parsed_res.data;
    var root_val: json.JsonValue = undefined;
    root_val.tag = root_tag;
    root_val.data = root_data;

    printValue(root_val, 0);
    __bootstrap_print("\n");
}
