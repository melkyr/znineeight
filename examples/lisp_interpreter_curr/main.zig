const sand_mod = @import("sand.zig");
const value_mod = @import("value.zig");
const token_mod = @import("token.zig");
const parser_mod = @import("parser.zig");
const env_mod = @import("env.zig");
const eval_mod = @import("eval.zig");
const builtins_mod = @import("builtins.zig");
const util = @import("util.zig");
const deep_copy_mod = @import("deep_copy.zig");

extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(i: i32) void;
extern fn getchar() i32;

fn print_str(s: []const u8) void {
    var i: usize = 0;
    while (i < s.len) {
        var buf: [2]u8 = undefined;
        buf[0] = s[i];
        buf[1] = 0;
        __bootstrap_print(&buf[0]);
        i += 1;
    }
}

fn print_value(v: *value_mod.Value) void {
    switch (v.*) {
        .Nil => print_str("nil"),
        .Int => |val| __bootstrap_print_int(@intCast(i32, val)),
        .Bool => |val| {
            if (val) {
                print_str("true");
            } else {
                print_str("false");
            }
        },
        .Symbol => |name| print_str(name),
        .Builtin => |_| print_str("<builtin>"),
        .Cons => |data| {
            const car = data.car;
            switch (car.*) {
                .Symbol => |s| {
                    if (util.mem_eql(s, "closure")) {
                        print_str("<closure>");
                        return;
                    }
                },
                else => {},
            }
            print_str("(");
            print_list(v);
            print_str(")");
        },
    }
}

fn print_list(v: *value_mod.Value) void {
    switch (v.*) {
        .Cons => |data| {
            print_value(data.car);
            const cdr = data.cdr;
            switch (cdr.*) {
                .Nil => {},
                .Symbol => |s| {
                    if (util.mem_eql(s, "nil")) return;
                    print_str(" . ");
                    print_str(s);
                },
                .Cons => {
                    print_str(" ");
                    print_list(cdr);
                },
                else => {
                    print_str(" . ");
                    print_value(cdr);
                },
            }
        },
        else => {},
    }
}

fn read_line(buf: []u8) i32 {
    var i: usize = 0;
    while (i < buf.len) {
        const c = getchar();
        const ic = @intCast(i32, c);
        if (ic == -1) {
            if (i == 0) return -1;
            break;
        }
        if (ic == 10) break;
        buf[i] = @intCast(u8, ic);
        i += 1;
    }
    return @intCast(i32, i);
}

pub fn main() void {
    var perm_buf: [1048576]u8 = undefined;
    var temp_buf: [1048576]u8 = undefined;

    var perm_sand = sand_mod.sand_init(perm_buf[0..1048576]);
    var temp_sand = sand_mod.sand_init(temp_buf[0..1048576]);

    var global_env: ?*env_mod.EnvNode = null;

    // Register builtins
    global_env = (env_mod.env_extend("cons", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_cons), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("car", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_car), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("cdr", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_cdr), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("+", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_add), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("-", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_sub), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("*", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_mul), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("/", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_div), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("=", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_eq), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("nil?", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_is_nil), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("<", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_lt), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend(">", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_gt), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);

    var input_buf: [4096]u8 = undefined;
    while (true) {
        print_str("> ");
        const len = read_line(&input_buf);
        if (len < 0) break;
        if (len == 0) continue;
        const line = input_buf[0..@intCast(usize, len)];

        var tokenizer = token_mod.Tokenizer{ .input = line, .pos = @intCast(usize, 0) };
        const expr = parser_mod.parse_expr(&tokenizer, &perm_sand, &temp_sand) catch |err| {
            print_str("Parse error\n");
            continue;
        };

        const result = eval_mod.eval(expr, &global_env, &temp_sand, &perm_sand) catch |err| {
            print_str("Eval error\n");
            continue;
        };

        print_value(result);
        print_str("\n");
        sand_mod.sand_reset(&temp_sand);
    }
}
