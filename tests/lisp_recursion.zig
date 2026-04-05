const value_mod = @import("../examples/lisp_interpreter_curr/value.zig");
const eval_mod = @import("../examples/lisp_interpreter_curr/eval.zig");
const env_mod = @import("../examples/lisp_interpreter_curr/env.zig");
const sand_mod = @import("../examples/lisp_interpreter_curr/sand.zig");
const token_mod = @import("../examples/lisp_interpreter_curr/token.zig");
const parser_mod = @import("../examples/lisp_interpreter_curr/parser.zig");
const builtins_mod = @import("../examples/lisp_interpreter_curr/builtins.zig");
const util = @import("../examples/lisp_interpreter_curr/util.zig");

extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(i: i32) void;

pub fn main() void {
    var perm_buf_u64: [131072]u64 = undefined;
    var temp_buf_u64: [131072]u64 = undefined;

    const perm_buf = @ptrCast([*]u8, &perm_buf_u64)[0..1048576];
    const temp_buf = @ptrCast([*]u8, &temp_buf_u64)[0..1048576];

    var perm_sand = sand_mod.sand_init(perm_buf);
    var temp_sand = sand_mod.sand_init(temp_buf);

    var global_env: ?*env_mod.EnvNode = null;
    global_env = (env_mod.env_extend("=", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_eq), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("*", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_mul), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);
    global_env = (env_mod.env_extend("-", (value_mod.alloc_builtin(@ptrCast(*void, builtins_mod.builtin_sub), &perm_sand) catch unreachable), global_env, &perm_sand) catch unreachable);

    const source = "(define fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (fact 5)";
    var tokenizer = token_mod.Tokenizer{ .input = source, .pos = @intCast(usize, 0) };

    // Parse define
    const expr1 = parser_mod.parse_expr(&tokenizer, &perm_sand, &temp_sand) catch unreachable;
    _ = eval_mod.eval(expr1, &global_env, &temp_sand, &perm_sand) catch unreachable;
    sand_mod.sand_reset(&temp_sand);

    // Parse (fact 5)
    const expr2 = parser_mod.parse_expr(&tokenizer, &perm_sand, &temp_sand) catch unreachable;
    const result = eval_mod.eval(expr2, &global_env, &temp_sand, &perm_sand) catch unreachable;

    switch (result.*) {
        .Int => |v| {
            if (v == 120) {
                __bootstrap_print("Lisp Recursion Test PASSED\n");
            } else {
                __bootstrap_print("Lisp Recursion Test FAILED: expected 120, got ");
                __bootstrap_print_int(@intCast(i32, v));
                __bootstrap_print("\n");
            }
        },
        else => __bootstrap_print("Lisp Recursion Test FAILED: expected Int result\n"),
    }
}
