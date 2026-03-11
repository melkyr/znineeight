const file = @import("file.zig");
const json = @import("json.zig");

extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(i: i32) void;
extern var zig_default_arena: *void;

fn printIndent(level: usize) void {
    var i: usize = 0;
    while (i < level) {
        __bootstrap_print(@ptrCast([*]const u8, "  "));
        i += 1;
    }
}

fn printValue(val: json.JsonValue, level: usize) void {
    switch (val) {
        .Null => { __bootstrap_print(@ptrCast([*]const u8, "null")); },
        .Boolean => |b| { if (b) __bootstrap_print(@ptrCast([*]const u8, "true")) else __bootstrap_print(@ptrCast([*]const u8, "false")); },
        .Number => |n| { __bootstrap_print(@ptrCast([*]const u8, "<number>")); },
        .String => |s| {
            __bootstrap_print(@ptrCast([*]const u8, "\""));
            __bootstrap_print(@ptrCast([*]const u8, s.ptr));
            __bootstrap_print(@ptrCast([*]const u8, "\""));
        },
        .Array => |arr| {
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
        },
        .Object => |obj| {
            __bootstrap_print(@ptrCast([*]const u8, "{"));
            if (obj.len > 0) {
                __bootstrap_print(@ptrCast([*]const u8, "\n"));
                var i: usize = 0;
                while (i < obj.len) {
                    printIndent(level + 1);
                    __bootstrap_print(@ptrCast([*]const u8, "\""));
                    __bootstrap_print(@ptrCast([*]const u8, obj[i].key.ptr));
                    __bootstrap_print(@ptrCast([*]const u8, "\": "));
                    const val_ptr = obj[i].value;
                    printValue(val_ptr.*, level + 1);
                    if (i < obj.len - 1) { __bootstrap_print(@ptrCast([*]const u8, ",")); }
                    __bootstrap_print(@ptrCast([*]const u8, "\n"));
                    i += 1;
                }
                printIndent(level);
            }
            __bootstrap_print(@ptrCast([*]const u8, "}"));
        },
    }
}

pub fn main() void {
    const arena = zig_default_arena;
    const content = file.readFile(arena, "test.json") catch |err| {
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
