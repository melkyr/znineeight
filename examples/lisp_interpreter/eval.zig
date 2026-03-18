const value_mod = @import("value.zig");
const env_mod = @import("env.zig");
const util = @import("util.zig");

pub fn eval(expr: *value_mod.Value, env: *?*env_mod.EnvNode, temp_arena: *value_mod.arena_mod.LispArena, perm_arena: *value_mod.arena_mod.LispArena) !*value_mod.Value {
    if (expr.tag == value_mod.ValueTag.Nil or expr.tag == value_mod.ValueTag.Int or expr.tag == value_mod.ValueTag.Bool or expr.tag == value_mod.ValueTag.Builtin) {
        return expr;
    }

    if (expr.tag == value_mod.ValueTag.Symbol) {
        const name = expr.data.Symbol;
        if (util.mem_eql(name, "nil")) return expr;
        if (util.mem_eql(name, "true")) return try value_mod.alloc_bool(true, temp_arena);
        if (util.mem_eql(name, "false")) return try value_mod.alloc_bool(false, temp_arena);
        return try env_mod.env_lookup(name, env.*);
    }

    if (expr.tag == value_mod.ValueTag.Cons) {
        const car = expr.data.Cons.car;
        const cdr = expr.data.Cons.cdr;

        if (car.tag == value_mod.ValueTag.Symbol) {
            const name = car.data.Symbol;
            if (util.mem_eql(name, "quote")) {
                if (cdr.tag != value_mod.ValueTag.Cons) return error.InvalidQuote;
                return cdr.data.Cons.car;
            }
            if (util.mem_eql(name, "if")) {
                if (cdr.tag != value_mod.ValueTag.Cons) return error.InvalidIf;
                const cond_expr = cdr.data.Cons.car;
                const rest = cdr.data.Cons.cdr;
                if (rest.tag != value_mod.ValueTag.Cons) return error.InvalidIf;
                const then_expr = rest.data.Cons.car;
                const else_rest = rest.data.Cons.cdr;

                const cond_val = try eval(cond_expr, env, temp_arena, perm_arena);
                var is_truthy = true;
                if (cond_val.tag == value_mod.ValueTag.Nil) {
                    is_truthy = false;
                } else if (cond_val.tag == value_mod.ValueTag.Bool) {
                    is_truthy = cond_val.data.Bool;
                } else if (cond_val.tag == value_mod.ValueTag.Symbol) {
                    if (util.mem_eql(cond_val.data.Symbol, "nil")) is_truthy = false;
                }

                if (is_truthy) {
                    return try eval(then_expr, env, temp_arena, perm_arena);
                } else if (else_rest.tag == value_mod.ValueTag.Cons) {
                    return try eval(else_rest.data.Cons.car, env, temp_arena, perm_arena);
                } else {
                    return try value_mod.alloc_nil(temp_arena);
                }
            }
            if (util.mem_eql(name, "define")) {
                if (cdr.tag != value_mod.ValueTag.Cons) return error.InvalidDefine;
                const sym_expr = cdr.data.Cons.car;
                if (sym_expr.tag != value_mod.ValueTag.Symbol) return error.InvalidDefine;
                const sym_name = sym_expr.data.Symbol;
                const val_rest = cdr.data.Cons.cdr;
                if (val_rest.tag != value_mod.ValueTag.Cons) return error.InvalidDefine;
                const val_expr = val_rest.data.Cons.car;

                const val = try eval(val_expr, env, temp_arena, perm_arena);
                const perm_val = try util.deep_copy(val, perm_arena);
                env.* = try env_mod.env_extend(sym_name, perm_val, env.*, perm_arena);
                return perm_val;
            }
            if (util.mem_eql(name, "lambda")) {
                if (cdr.tag != value_mod.ValueTag.Cons) return error.InvalidLambda;
                const params = cdr.data.Cons.car;
                const body_rest = cdr.data.Cons.cdr;
                if (body_rest.tag != value_mod.ValueTag.Cons) return error.InvalidLambda;
                const body = body_rest.data.Cons.car;

                const closure_tag = try value_mod.alloc_symbol("closure", perm_arena);
                const params_body = try value_mod.alloc_cons(params, body, perm_arena);
                const env_val = try env_to_value(env.*, perm_arena);
                const closure_data = try value_mod.alloc_cons(params_body, env_val, perm_arena);
                return try value_mod.alloc_cons(closure_tag, closure_data, perm_arena);
            }
        }

        const fun = try eval(car, env, temp_arena, perm_arena);

        var arg_count: usize = 0;
        var cur = cdr;
        while (cur.tag == value_mod.ValueTag.Cons) {
            arg_count += 1;
            cur = cur.data.Cons.cdr;
        }

        const args_mem = try value_mod.arena_mod.lisp_alloc(temp_arena, arg_count * @sizeOf(*value_mod.Value), @alignOf(*value_mod.Value));
        const args = @ptrCast([*]*value_mod.Value, args_mem)[0..arg_count];

        var i: usize = 0;
        cur = cdr;
        while (i < arg_count) {
            args[i] = try eval(cur.data.Cons.car, env, temp_arena, perm_arena);
            cur = cur.data.Cons.cdr;
            i += 1;
        }

        return try apply(fun, args, env, temp_arena, perm_arena);
    }

    return error.InvalidExpr;
}

fn env_to_value(env: ?*env_mod.EnvNode, arena: *value_mod.arena_mod.LispArena) !*value_mod.Value {
    if (env) |node| {
        const sym_val = try value_mod.alloc_symbol(node.symbol, arena);
        const pair = try value_mod.alloc_cons(sym_val, node.value, arena);
        var next_ptr: ?*env_mod.EnvNode = null;
        if (node.next != 0) {
            const next_any = @intToPtr(*void, node.next);
            next_ptr = @ptrCast(*env_mod.EnvNode, next_any);
        }
        const next = try env_to_value(next_ptr, arena);
        return try value_mod.alloc_cons(pair, next, arena);
    } else {
        return try value_mod.alloc_symbol("nil", arena);
    }
}

fn apply(fun: *value_mod.Value, args: []*value_mod.Value, env: *?*env_mod.EnvNode, temp_arena: *value_mod.arena_mod.LispArena, perm_arena: *value_mod.arena_mod.LispArena) !*value_mod.Value {
    if (fun.tag == value_mod.ValueTag.Builtin) {
        const f = @ptrCast(fn ([]*value_mod.Value, *value_mod.arena_mod.LispArena) !*value_mod.Value, fun.data.Builtin);
        return try f(args, temp_arena);
    }

    if (fun.tag == value_mod.ValueTag.Cons) {
        const car = fun.data.Cons.car;
        if (car.tag == value_mod.ValueTag.Symbol and util.mem_eql(car.data.Symbol, "closure")) {
            const closure_cdr = fun.data.Cons.cdr;
            const data_car = closure_cdr.data.Cons.car;
            const data_cdr = closure_cdr.data.Cons.cdr;
            const params = data_car.data.Cons.car;
            const body = data_car.data.Cons.cdr;
            const saved_env_val = data_cdr;

            var new_env = try value_to_env_real(saved_env_val, perm_arena);

            var cur_param = params;
            var i: usize = 0;
            while (i < args.len) {
                if (cur_param.tag != value_mod.ValueTag.Cons) return error.TooManyArgs;
                const param_sym = cur_param.data.Cons.car;
                if (param_sym.tag != value_mod.ValueTag.Symbol) return error.InvalidParams;
                new_env = try env_mod.env_extend(param_sym.data.Symbol, args[i], new_env, temp_arena);
                cur_param = cur_param.data.Cons.cdr;
                i += 1;
            }

            var too_few = false;
            if (cur_param.tag != value_mod.ValueTag.Nil) {
                if (cur_param.tag == value_mod.ValueTag.Symbol) {
                    if (!util.mem_eql(cur_param.data.Symbol, "nil")) too_few = true;
                } else {
                    too_few = true;
                }
            }
            if (too_few) return error.TooFewArgs;

            return try eval(body, &new_env, temp_arena, perm_arena);
        }
    }

    return error.NotCallable;
}

fn value_to_env_real(v: *value_mod.Value, arena: *value_mod.arena_mod.LispArena) !?*env_mod.EnvNode {
    if (v.tag == value_mod.ValueTag.Nil) return null;
    if (v.tag == value_mod.ValueTag.Symbol and util.mem_eql(v.data.Symbol, "nil")) return null;

    const pair = v.data.Cons.car.data.Cons;
    const sym = pair.car.data.Symbol;
    const val = pair.cdr;

    var node = try env_mod.env_extend(sym, val, try value_to_env_real(v.data.Cons.cdr, arena), arena);
    return node;
}
