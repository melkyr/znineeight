const file = @import("file.zig");
const json = @import("json.zig");

extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_write(s: [*]const u8, len: usize) void;
extern fn __bootstrap_print_int(i: i32) void;
extern var zig_default_arena: *void;

fn printIndent(level: usize) void {
    var i: usize = 0;
    while (i < level) {
        const space: [*]const u8 = "  ";
        __bootstrap_print(space);
        i += 1;
    }
}

fn printValue(val: json.JsonValue, level: usize) void {
    if (val.tag == json.JsonValueTag.Null) {
        const null_ptr: [*]const u8 = "null";
        __bootstrap_print(null_ptr);
    } else if (val.tag == json.JsonValueTag.Boolean) {
        if (val.data.boolean) {
            const true_ptr: [*]const u8 = "true";
            __bootstrap_print(true_ptr);
        } else {
            const false_ptr: [*]const u8 = "false";
            __bootstrap_print(false_ptr);
        }
    } else if (val.tag == json.JsonValueTag.Number) {
        const num_ptr: [*]const u8 = "<number>";
        __bootstrap_print(num_ptr);
    } else if (val.tag == json.JsonValueTag.String) {
        const quote_ptr: [*]const u8 = "\"";
        __bootstrap_print(quote_ptr);
        __bootstrap_write(val.data.string.ptr, val.data.string.len);
        __bootstrap_print(quote_ptr);
    } else if (val.tag == json.JsonValueTag.Array) {
        const lbr_ptr: [*]const u8 = "[";
        __bootstrap_print(lbr_ptr);
        const arr = val.data.array;
        if (arr.len > 0) {
            const nl_ptr: [*]const u8 = "\n";
            __bootstrap_print(nl_ptr);
            var i: usize = 0;
            while (i < arr.len) {
                printIndent(level + 1);
                printValue(arr[i], level + 1);
                if (i < arr.len - 1) {
                    const comma_ptr: [*]const u8 = ",";
                    __bootstrap_print(comma_ptr);
                }
                const nl2_ptr: [*]const u8 = "\n";
                __bootstrap_print(nl2_ptr);
                i += 1;
            }
            printIndent(level);
        }
        const rbr_ptr: [*]const u8 = "]";
        __bootstrap_print(rbr_ptr);
    } else if (val.tag == json.JsonValueTag.Object) {
        const lbr_ptr: [*]const u8 = "{";
        __bootstrap_print(lbr_ptr);
        const obj = val.data.object;
        if (obj.len > 0) {
            const nl_ptr: [*]const u8 = "\n";
            __bootstrap_print(nl_ptr);
            var i: usize = 0;
            while (i < obj.len) {
                printIndent(level + 1);
                const quote_ptr: [*]const u8 = "\"";
                __bootstrap_print(quote_ptr);
                __bootstrap_write(obj[i].key.ptr, obj[i].key.len);
                const sep_ptr: [*]const u8 = "\": ";
                __bootstrap_print(sep_ptr);

                const inner_ptr = obj[i].value;
                printValue(inner_ptr.*, level + 1);

                if (i < obj.len - 1) {
                    const comma_ptr: [*]const u8 = ",";
                    __bootstrap_print(comma_ptr);
                }
                const nl2_ptr: [*]const u8 = "\n";
                __bootstrap_print(nl2_ptr);
                i += 1;
            }
            printIndent(level);
        }
        const rbr_ptr: [*]const u8 = "}";
        __bootstrap_print(rbr_ptr);
    }
}

pub fn main() void {
    const arena_ptr = zig_default_arena;
    const content = file.readFile(arena_ptr, "test.json") catch |err| {
        const err_msg: [*]const u8 = "Error reading file: ";
        __bootstrap_print(err_msg);
        __bootstrap_print_int(@enumToInt(err));
        const nl_ptr: [*]const u8 = "\n";
        __bootstrap_print(nl_ptr);
        return;
    };
    const parsed = json.parseJson(arena_ptr, content) catch |err| {
        const parse_msg: [*]const u8 = "Parse error: ";
        __bootstrap_print(parse_msg);
        __bootstrap_print_int(@enumToInt(err));
        const nl_ptr: [*]const u8 = "\n";
        __bootstrap_print(nl_ptr);
        return;
    };
    printValue(parsed, 0);
    const nl2_ptr: [*]const u8 = "\n";
    __bootstrap_print(nl2_ptr);
}
