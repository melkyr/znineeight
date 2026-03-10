const file = @import("file.zig");
const json = @import("json.zig");

extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(i: i32) void;
extern var zig_default_arena: *void;

fn printIndent(level: usize) void {
    var i: usize = 0;
    while (i < level) {
        const space: []const u8 = "  ";
        __bootstrap_print(space.ptr);
        i += 1;
    }
}

fn printValue(val: json.JsonValue, level: usize) void {
    if (val.tag == json.JsonValueTag.Null) {
        const s: []const u8 = "null";
        __bootstrap_print(s.ptr);
    } else if (val.tag == json.JsonValueTag.Boolean) {
        if (val.data.boolean) {
            const s: []const u8 = "true";
            __bootstrap_print(s.ptr);
        } else {
            const s: []const u8 = "false";
            __bootstrap_print(s.ptr);
        }
    } else if (val.tag == json.JsonValueTag.Number) {
        const s: []const u8 = "<number>";
        __bootstrap_print(s.ptr);
    } else if (val.tag == json.JsonValueTag.String) {
        const s: []const u8 = val.data.string;
        const quote: []const u8 = "\"";
        __bootstrap_print(quote.ptr);
        var i: usize = 0;
        while (i < s.len) {
            var buf: [2]u8 = undefined;
            buf[0] = s[i];
            buf[1] = 0;
            __bootstrap_print(&buf[0]);
            i += 1;
        }
        __bootstrap_print(quote.ptr);
    } else if (val.tag == json.JsonValueTag.Array) {
        const lbr: []const u8 = "[";
        __bootstrap_print(lbr.ptr);
        const arr = val.data.array;
        if (arr.len > 0) {
            const nl: []const u8 = "\n";
            __bootstrap_print(nl.ptr);
            var i: usize = 0;
            while (i < arr.len) {
                printIndent(level + 1);
                printValue(arr[i], level + 1);
                if (i < arr.len - 1) {
                    const comma: []const u8 = ",";
                    __bootstrap_print(comma.ptr);
                }
                __bootstrap_print(nl.ptr);
                i += 1;
            }
            printIndent(level);
        }
        const rbr: []const u8 = "]";
        __bootstrap_print(rbr.ptr);
    } else if (val.tag == json.JsonValueTag.Object) {
        const lbr: []const u8 = "{";
        __bootstrap_print(lbr.ptr);
        const obj = val.data.object;
        if (obj.len > 0) {
            const nl: []const u8 = "\n";
            __bootstrap_print(nl.ptr);
            var i: usize = 0;
            while (i < obj.len) {
                printIndent(level + 1);
                const key_s: []const u8 = obj[i].key;
                const quote: []const u8 = "\"";
                __bootstrap_print(quote.ptr);

                var j: usize = 0;
                while (j < key_s.len) {
                    var buf: [2]u8 = undefined;
                    buf[0] = key_s[j];
                    buf[1] = 0;
                    __bootstrap_print(&buf[0]);
                    j += 1;
                }

                const sep: []const u8 = "\": ";
                __bootstrap_print(sep.ptr);

                // Dereference pointer to JsonValue
                const inner_val_ptr = obj[i].value;
                const inner_val = inner_val_ptr.*;
                printValue(inner_val, level + 1);

                if (i < obj.len - 1) {
                    const comma: []const u8 = ",";
                    __bootstrap_print(comma.ptr);
                }
                __bootstrap_print(nl.ptr);
                i += 1;
            }
            printIndent(level);
        }
        const rbr: []const u8 = "}";
        __bootstrap_print(rbr.ptr);
    }
}

pub fn main() void {
    const arena = zig_default_arena;
    const content = file.readFile(arena, "test.json") catch |err| {
        const msg: []const u8 = "Error reading file: ";
        __bootstrap_print(msg.ptr);
        __bootstrap_print_int(@enumToInt(err));
        const nl: []const u8 = "\n";
        __bootstrap_print(nl.ptr);
        return;
    };
    const parsed = json.parseJson(arena, content) catch |err| {
        const msg: []const u8 = "Parse error: ";
        __bootstrap_print(msg.ptr);
        __bootstrap_print_int(@enumToInt(err));
        const nl: []const u8 = "\n";
        __bootstrap_print(nl.ptr);
        return;
    };
    printValue(parsed, 0);
    const nl: []const u8 = "\n";
    __bootstrap_print(nl.ptr);
}
