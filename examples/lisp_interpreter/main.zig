const sand_mod = @import("sand.zig");
const value_mod = @import("value.zig");
const token_mod = @import("token.zig");
const parser_mod = @import("parser.zig");
const env_mod = @import("env.zig");
const eval_mod = @import("eval.zig");
const builtins_mod = @import("builtins.zig");
const util = @import("util.zig");

extern fn __bootstrap_print(s: [*]const c_char) void;
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
    if (v.tag == value_mod.ValueTag.Nil) {
        print_str("nil");
    } else if (v.tag == value_mod.ValueTag.Int) {
        __bootstrap_print_int(@intCast(i32, v.data.Int));
    } else if (v.tag == value_mod.ValueTag.Bool) {
        if (v.data.Bool) {
            print_str("true");
        } else {
            print_str("false");
        }
    } else if (v.tag == value_mod.ValueTag.Symbol) {
        print_str(v.data.Symbol);
    } else if (v.tag == value_mod.ValueTag.Builtin) {
        print_str("<builtin>");
    } else if (v.tag == value_mod.ValueTag.Cons) {
        if (v.data.Cons.car.tag == value_mod.ValueTag.Symbol and util.mem_eql(v.data.Cons.car.data.Symbol, "closure")) {
            print_str("<closure>");
            return;
        }
        print_str("(");
        print_list(v);
        print_str(")");
    }
}

fn print_list(v: *value_mod.Value) void {
    print_value(v.data.Cons.car);
    const cdr = v.data.Cons.cdr;
    if (cdr.tag == value_mod.ValueTag.Nil) {
        // end of list
    } else if (cdr.tag == value_mod.ValueTag.Symbol and util.mem_eql(cdr.data.Symbol, "nil")) {
        // end of list
    } else if (cdr.tag == value_mod.ValueTag.Cons) {
        print_str(" ");
        print_list(cdr);
    } else {
        print_str(" . ");
        print_value(cdr);
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

    var perm_sand = sand_mod.lisp_sand_init(perm_buf[0..1048576]);
    var temp_sand = sand_mod.lisp_sand_init(temp_buf[0..1048576]);

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
        const expr = parser_mod.parse_expr(&tokenizer, &perm_sand, &temp_sand) catch continue;

        const result = eval_mod.eval(expr, &global_env, &temp_sand, &perm_sand) catch continue;

        print_value(result);
        print_str("\n");
        sand_mod.lisp_sand_reset(&temp_sand);
    }
}
