const value_mod = @import("value.zig");
const env_mod = @import("env.zig");
const util = @import("util.zig");
const sand_mod = @import("sand.zig");
const deep_copy_mod = @import("deep_copy.zig");

pub fn eval(expr: *value_mod.Value, env: *?*env_mod.EnvNode, temp_sand: *sand_mod.Sand, perm_sand: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (expr.tag == value_mod.ValueTag.Nil or expr.tag == value_mod.ValueTag.Int or expr.tag == value_mod.ValueTag.Bool or expr.tag == value_mod.ValueTag.Builtin) {
        return expr;
    } else if (expr.tag == value_mod.ValueTag.Symbol) {
        const name = expr.data.Symbol;
        if (util.mem_eql(name, "nil")) return expr;
        if (util.mem_eql(name, "true")) return try value_mod.alloc_bool(true, temp_sand);
        if (util.mem_eql(name, "false")) return try value_mod.alloc_bool(false, temp_sand);
        return try env_mod.env_lookup(name, env.*);
    } else if (expr.tag == value_mod.ValueTag.Cons) {
        const car = expr.data.Cons.car;
        const cdr = expr.data.Cons.cdr;

        if (car.tag == value_mod.ValueTag.Symbol) {
            const name = car.data.Symbol;
            if (util.mem_eql(name, "quote")) {
                if (cdr.tag == value_mod.ValueTag.Cons) {
                    return cdr.data.Cons.car;
                } else {
                    return error.InvalidQuote;
                }
            }
            if (util.mem_eql(name, "if")) {
                if (cdr.tag == value_mod.ValueTag.Cons) {
                    const cond_expr = cdr.data.Cons.car;
                    const rest = cdr.data.Cons.cdr;
                    if (rest.tag == value_mod.ValueTag.Cons) {
                        const then_expr = rest.data.Cons.car;
                        const else_rest = rest.data.Cons.cdr;

                        const cond_val = try eval(cond_expr, env, temp_sand, perm_sand);
                        var is_truthy = true;
                        if (cond_val.tag == value_mod.ValueTag.Nil) {
                            is_truthy = false;
                        } else if (cond_val.tag == value_mod.ValueTag.Bool) {
                            is_truthy = cond_val.data.Bool;
                        } else if (cond_val.tag == value_mod.ValueTag.Symbol) {
                            if (util.mem_eql(cond_val.data.Symbol, "nil")) is_truthy = false;
                        }

                        if (is_truthy) {
                            return try eval(then_expr, env, temp_sand, perm_sand);
                        } else {
                            if (else_rest.tag == value_mod.ValueTag.Cons) {
                                return try eval(else_rest.data.Cons.car, env, temp_sand, perm_sand);
                            } else {
                                return try value_mod.alloc_nil(temp_sand);
                            }
                        }
                    } else {
                        return error.InvalidIf;
                    }
                } else {
                    return error.InvalidIf;
                }
            }
            if (util.mem_eql(name, "define")) {
                if (cdr.tag == value_mod.ValueTag.Cons) {
                    const sym_expr = cdr.data.Cons.car;
                    if (sym_expr.tag == value_mod.ValueTag.Symbol) {
                        const sym_name = sym_expr.data.Symbol;
                        const val_rest = cdr.data.Cons.cdr;
                        if (val_rest.tag == value_mod.ValueTag.Cons) {
                            const val_expr = val_rest.data.Cons.car;
                            const val = try eval(val_expr, env, temp_sand, perm_sand);
                            const perm_val = try deep_copy_mod.deep_copy(val, perm_sand);
                            env.* = try env_mod.env_extend(sym_name, perm_val, env.*, perm_sand);
                            return perm_val;
                        } else {
                            return error.InvalidDefine;
                        }
                    } else {
                        return error.InvalidDefine;
                    }
                } else {
                    return error.InvalidDefine;
                }
            }
            if (util.mem_eql(name, "lambda")) {
                if (cdr.tag == value_mod.ValueTag.Cons) {
                    const params = cdr.data.Cons.car;
                    const body_rest = cdr.data.Cons.cdr;
                    if (body_rest.tag == value_mod.ValueTag.Cons) {
                        const body = body_rest.data.Cons.car;
                        const closure_tag = try value_mod.alloc_symbol("closure", perm_sand);
                        const params_body = try value_mod.alloc_cons(params, body, perm_sand);
                        const env_val = try env_to_value(env.*, perm_sand);
                        const closure_data = try value_mod.alloc_cons(params_body, env_val, perm_sand);
                        return try value_mod.alloc_cons(closure_tag, closure_data, perm_sand);
                    } else {
                        return error.InvalidLambda;
                    }
                } else {
                    return error.InvalidLambda;
                }
            }
        }

        const fun = try eval(car, env, temp_sand, perm_sand);

        var arg_count: usize = 0;
        var cur = cdr;
        while (true) {
            if (cur.tag == value_mod.ValueTag.Cons) {
                arg_count += 1;
                cur = cur.data.Cons.cdr;
            } else {
                break;
            }
        }

        const args_mem = try sand_mod.sand_alloc(temp_sand, arg_count * @sizeOf(*value_mod.Value), @alignOf(*value_mod.Value));
        const args = @ptrCast([*]*value_mod.Value, args_mem)[0..arg_count];

        var i: usize = 0;
        cur = cdr;
        while (i < arg_count) {
            if (cur.tag == value_mod.ValueTag.Cons) {
                args[i] = try eval(cur.data.Cons.car, env, temp_sand, perm_sand);
                cur = cur.data.Cons.cdr;
            } else {
                // unreachable
            }
            i += 1;
        }

        return try apply(fun, args, env, temp_sand, perm_sand);
    } else {
        return error.InvalidExpr;
    }
}

fn env_to_value(env: ?*env_mod.EnvNode, sand: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (env) |node| {
        const sym_val = try value_mod.alloc_symbol(node.symbol, sand);
        const pair = try value_mod.alloc_cons(sym_val, node.value, sand);
        const next = try env_to_value(node.next, sand);
        return try value_mod.alloc_cons(pair, next, sand);
    } else {
        return try value_mod.alloc_symbol("nil", sand);
    }
}

fn apply(fun: *value_mod.Value, args: []*value_mod.Value, env: *?*env_mod.EnvNode, temp_sand: *sand_mod.Sand, perm_sand: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (fun.tag == value_mod.ValueTag.Builtin) {
        const f = @ptrCast(fn ([]*value_mod.Value, *sand_mod.Sand) util.LispError!*value_mod.Value, fun.data.Builtin);
        return try f(args, temp_sand);
    } else if (fun.tag == value_mod.ValueTag.Cons) {
        const car = fun.data.Cons.car;
        if (car.tag == value_mod.ValueTag.Symbol) {
            const s = car.data.Symbol;
            if (util.mem_eql(s, "closure")) {
                const closure_cdr = fun.data.Cons.cdr;
                if (closure_cdr.tag == value_mod.ValueTag.Cons) {
                    const data_car = closure_cdr.data.Cons.car;
                    const data_cdr = closure_cdr.data.Cons.cdr;
                    if (data_car.tag == value_mod.ValueTag.Cons) {
                        const params = data_car.data.Cons.car;
                        const body = data_car.data.Cons.cdr;
                        const saved_env_val = data_cdr;

                        var new_env = try value_to_env_real(saved_env_val, perm_sand);

                        var cur_param = params;
                        var i: usize = 0;
                        while (i < args.len) {
                            if (cur_param.tag == value_mod.ValueTag.Cons) {
                                const param_sym = cur_param.data.Cons.car;
                                if (param_sym.tag == value_mod.ValueTag.Symbol) {
                                    const p_name = param_sym.data.Symbol;
                                    new_env = try env_mod.env_extend(p_name, args[i], new_env, temp_sand);
                                } else {
                                    return error.InvalidParams;
                                }
                                cur_param = cur_param.data.Cons.cdr;
                            } else {
                                return error.TooManyArgs;
                            }
                            i += 1;
                        }

                        var too_few = false;
                        if (cur_param.tag == value_mod.ValueTag.Nil) {
                            // ok
                        } else if (cur_param.tag == value_mod.ValueTag.Symbol) {
                            if (!util.mem_eql(cur_param.data.Symbol, "nil")) too_few = true;
                        } else {
                            too_few = true;
                        }
                        if (too_few) return error.TooFewArgs;

                        return try eval(body, &new_env, temp_sand, perm_sand);
                    } else {
                        return error.InvalidClosure;
                    }
                } else {
                    return error.InvalidClosure;
                }
            }
        }
    }

    return error.NotCallable;
}

fn value_to_env_real(v: *value_mod.Value, sand: *sand_mod.Sand) util.LispError!?*env_mod.EnvNode {
    if (v.tag == value_mod.ValueTag.Nil) {
        return null;
    } else if (v.tag == value_mod.ValueTag.Symbol) {
        if (util.mem_eql(v.data.Symbol, "nil")) return null;
        return error.InvalidEnv;
    } else if (v.tag == value_mod.ValueTag.Cons) {
        const pair = v.data.Cons.car;
        if (pair.tag == value_mod.ValueTag.Cons) {
            const sym_val = pair.data.Cons.car;
            const val = pair.data.Cons.cdr;
            if (sym_val.tag == value_mod.ValueTag.Symbol) {
                return try env_mod.env_extend(sym_val.data.Symbol, val, try value_to_env_real(v.data.Cons.cdr, sand), sand);
            } else {
                return error.InvalidEnv;
            }
        } else {
            return error.InvalidEnv;
        }
    } else {
        return error.InvalidEnv;
    }
}
