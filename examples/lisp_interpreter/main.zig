const arena_mod = @import("arena.zig");
const value_mod = @import("value.zig");
const token_mod = @import("token.zig");
const parser_mod = @import("parser.zig");
const env_mod = @import("env.zig");
const eval_mod = @import("eval.zig");
const builtins_mod = @import("builtins.zig");
const util = @import("util.zig");

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
    if (v.tag == value_mod.ValueTag.Nil) {
        print_str("nil");
    } else if (v.tag == value_mod.ValueTag.Int) {
        __bootstrap_print_int(@intCast(i32, v.data.Int));
    } else if (v.tag == value_mod.ValueTag.Bool) {
        print_str(if (v.data.Bool) "true" else "false");
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

fn read_line(buf: []u8) ![]u8 {
    var i: usize = 0;
    while (i < buf.len) {
        const c = getchar();
        if (c == -1 or c == '\n') break;
        buf[i] = @intCast(u8, c);
        i += 1;
    }
    return buf[0..i];
}

pub fn main() !void {
    var perm_buf: [1024 * 1024]u8 = undefined;
    var temp_buf: [1024 * 1024]u8 = undefined;

    var perm_arena = arena_mod.arena_init(&perm_buf);
    var temp_arena = arena_mod.arena_init(&temp_buf);

    var global_env: ?*env_mod.EnvNode = null;

    // Register builtins
    global_env = try env_mod.env_extend("cons", try value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_cons), &perm_arena), global_env, &perm_arena);
    global_env = try env_mod.env_extend("car", try value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_car), &perm_arena), global_env, &perm_arena);
    global_env = try env_mod.env_extend("cdr", try value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_cdr), &perm_arena), global_env, &perm_arena);
    global_env = try env_mod.env_extend("+", try value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_add), &perm_arena), global_env, &perm_arena);
    global_env = try env_mod.env_extend("-", try value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_sub), &perm_arena), global_env, &perm_arena);
    global_env = try env_mod.env_extend("*", try value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_mul), &perm_arena), global_env, &perm_arena);
    global_env = try env_mod.env_extend("/", try value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_div), &perm_arena), global_env, &perm_arena);
    global_env = try env_mod.env_extend("=", try value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_eq), &perm_arena), global_env, &perm_arena);
    global_env = try env_mod.env_extend("nil?", try value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_is_nil), &perm_arena), global_env, &perm_arena);
    global_env = try env_mod.env_extend("<", try value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_lt), &perm_arena), global_env, &perm_arena);
    global_env = try env_mod.env_extend(">", try value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_gt), &perm_arena), global_env, &perm_arena);

    var input_buf: [4096]u8 = undefined;
    while (true) {
        print_str("> ");
        const line = try read_line(&input_buf);
        if (line.len == 0) continue;

        var tokenizer = token_mod.Tokenizer{ .input = line, .pos = 0 };
        const expr = parser_mod.parse_expr(&tokenizer, &perm_arena, &temp_arena) catch |err| {
            print_str("Parse error\n");
            continue;
        };

        const result = eval_mod.eval(expr, &global_env, &temp_arena, &perm_arena) catch |err| {
            print_str("Eval error\n");
            continue;
        };

        print_value(result);
        print_str("\n");
        arena_mod.arena_reset(&temp_arena);
    }
}
