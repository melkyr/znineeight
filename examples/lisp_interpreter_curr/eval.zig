const value_mod = @import("value.zig");
const env_mod = @import("env.zig");
const util = @import("util.zig");
const sand_mod = @import("sand.zig");
const deep_copy_mod = @import("deep_copy.zig");

pub fn eval(expr: *value_mod.Value, env: *?*env_mod.EnvNode, temp_sand: *sand_mod.Sand, perm_sand: *sand_mod.Sand) util.LispError!*value_mod.Value {
    switch (expr.*) {
        .Nil, .Int, .Bool, .Builtin => return expr,
        .Symbol => |name| {
            if (util.mem_eql(name, "nil")) return expr;
            if (util.mem_eql(name, "true")) return try value_mod.alloc_bool(true, temp_sand);
            if (util.mem_eql(name, "false")) return try value_mod.alloc_bool(false, temp_sand);
            return try env_mod.env_lookup(name, env.*);
        },
        .Cons => |data| {
            const car = data.car;
            const cdr = data.cdr;

            switch (car.*) {
                .Symbol => |name| {
                    if (util.mem_eql(name, "quote")) {
                        switch (cdr.*) {
                            .Cons => |c_data| return c_data.car,
                            else => return error.InvalidQuote,
                        }
                    }
                    if (util.mem_eql(name, "if")) {
                        switch (cdr.*) {
                            .Cons => |c_data| {
                                const cond_expr = c_data.car;
                                const rest = c_data.cdr;
                                switch (rest.*) {
                                    .Cons => |r_data| {
                                        const then_expr = r_data.car;
                                        const else_rest = r_data.cdr;

                                        const cond_val = try eval(cond_expr, env, temp_sand, perm_sand);
                                        var is_truthy = true;
                                        switch (cond_val.*) {
                                            .Nil => is_truthy = false,
                                            .Bool => |b| is_truthy = b,
                                            .Symbol => |s| {
                                                if (util.mem_eql(s, "nil")) is_truthy = false;
                                            },
                                            else => {},
                                        }

                                        if (is_truthy) {
                                            return try eval(then_expr, env, temp_sand, perm_sand);
                                        } else {
                                            switch (else_rest.*) {
                                                .Cons => |e_data| return try eval(e_data.car, env, temp_sand, perm_sand),
                                                else => return try value_mod.alloc_nil(temp_sand),
                                            }
                                        }
                                    },
                                    else => return error.InvalidIf,
                                }
                            },
                            else => return error.InvalidIf,
                        }
                    }
                    if (util.mem_eql(name, "define")) {
                        switch (cdr.*) {
                            .Cons => |c_data| {
                                const sym_expr = c_data.car;
                                switch (sym_expr.*) {
                                    .Symbol => |sym_name| {
                                        const val_rest = c_data.cdr;
                                        switch (val_rest.*) {
                                            .Cons => |v_data| {
                                                const val_expr = v_data.car;

                                                var slot: *value_mod.Value = undefined;
                                                if (env_mod.env_find_node(sym_name, env.*)) |node| {
                                                    slot = node.value;
                                                } else {
                                                    slot = try value_mod.alloc_nil(perm_sand);
                                                    env.* = try env_mod.env_extend(sym_name, slot, env.*, perm_sand);
                                                }

                                                const val = try eval(val_expr, env, temp_sand, perm_sand);
                                                const perm_val = if (util.points_to_arena(val, temp_sand.start, temp_sand.pos))
                                                    try deep_copy_mod.deep_copy(val, perm_sand)
                                                else
                                                    val;

                                                slot.* = perm_val.*;
                                                return slot;
                                            },
                                            else => return error.InvalidDefine,
                                        }
                                    },
                                    else => return error.InvalidDefine,
                                }
                            },
                            else => return error.InvalidDefine,
                        }
                    }
                    if (util.mem_eql(name, "lambda")) {
                        switch (cdr.*) {
                            .Cons => |c_data| {
                                const params = c_data.car;
                                const body_rest = c_data.cdr;
                                switch (body_rest.*) {
                                    .Cons => |b_data| {
                                        const body = b_data.car;

                                        const perm_params = try deep_copy_mod.deep_copy(params, perm_sand);
                                        const perm_body = try deep_copy_mod.deep_copy(body, perm_sand);

                                        const closure_tag = try value_mod.alloc_symbol("closure", perm_sand);
                                        const params_body = try value_mod.alloc_cons(perm_params, perm_body, perm_sand);
                                        const env_val = try env_to_value(env.*, temp_sand, perm_sand);
                                        const closure_data = try value_mod.alloc_cons(params_body, env_val, perm_sand);
                                        return try value_mod.alloc_cons(closure_tag, closure_data, perm_sand);
                                    },
                                    else => return error.InvalidLambda,
                                }
                            },
                            else => return error.InvalidLambda,
                        }
                    }
                },
                else => {},
            }

            const fun = try eval(car, env, temp_sand, perm_sand);

            var arg_count: usize = 0;
            var cur = cdr;
            while (true) {
                switch (cur.*) {
                    .Cons => |c| {
                        arg_count += 1;
                        cur = c.cdr;
                    },
                    else => break,
                }
            }

            const args_mem = try sand_mod.sand_alloc(temp_sand, arg_count * @sizeOf(*value_mod.Value), @alignOf(*value_mod.Value));
            const args = @ptrCast([*]*value_mod.Value, args_mem)[0..arg_count];

            var i: usize = 0;
            cur = cdr;
            while (i < arg_count) {
                switch (cur.*) {
                    .Cons => |c| {
                        args[i] = try eval(c.car, env, temp_sand, perm_sand);
                        cur = c.cdr;
                    },
                    else => unreachable,
                }
                i += 1;
            }

            return try apply(fun, args, env, temp_sand, perm_sand);
        },
        else => return error.InvalidExpr,
    }
}

fn env_to_value(env: ?*env_mod.EnvNode, temp_sand: *sand_mod.Sand, perm_sand: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (env) |node| {
        const sym_val = try value_mod.alloc_symbol(node.symbol, perm_sand);

        const val = if (util.points_to_arena(node.value, temp_sand.start, temp_sand.pos))
            try deep_copy_mod.deep_copy(node.value, perm_sand)
        else
            node.value;

        const pair = try value_mod.alloc_cons(sym_val, val, perm_sand);
        const next = try env_to_value(node.next, temp_sand, perm_sand);
        return try value_mod.alloc_cons(pair, next, perm_sand);
    } else {
        return try value_mod.alloc_symbol("nil", perm_sand);
    }
}

fn apply(fun: *value_mod.Value, args: []*value_mod.Value, env: *?*env_mod.EnvNode, temp_sand: *sand_mod.Sand, perm_sand: *sand_mod.Sand) util.LispError!*value_mod.Value {
    switch (fun.*) {
        .Builtin => |f_ptr| {
            const f = @ptrCast(fn ([]*value_mod.Value, *sand_mod.Sand) util.LispError!*value_mod.Value, f_ptr);
            return try f(args, temp_sand);
        },
        .Cons => |data| {
            const car = data.car;
            switch (car.*) {
                .Symbol => |s| {
                    if (util.mem_eql(s, "closure")) {
                        const closure_cdr = data.cdr;
                        switch (closure_cdr.*) {
                            .Cons => |c_data| {
                                const data_car = c_data.car;
                                const data_cdr = c_data.cdr;
                                switch (data_car.*) {
                                    .Cons => |dc_data| {
                                        const params = dc_data.car;
                                        const body = dc_data.cdr;
                                        const saved_env_val = data_cdr;

                                        var new_env = try value_to_env_real(saved_env_val, temp_sand);

                                        var cur_param = params;
                                        var i: usize = 0;
                                        while (i < args.len) {
                                            switch (cur_param.*) {
                                                .Cons => |cp_data| {
                                                    const param_sym = cp_data.car;
                                                    switch (param_sym.*) {
                                                        .Symbol => |p_name| {
                                                            new_env = try env_mod.env_extend(p_name, args[i], new_env, temp_sand);
                                                        },
                                                        else => return error.InvalidParams,
                                                    }
                                                    cur_param = cp_data.cdr;
                                                },
                                                else => return error.TooManyArgs,
                                            }
                                            i += 1;
                                        }

                                        var too_few = false;
                                        switch (cur_param.*) {
                                            .Nil => {},
                                            .Symbol => |sn| {
                                                if (!util.mem_eql(sn, "nil")) too_few = true;
                                            },
                                            else => too_few = true,
                                        }
                                        if (too_few) return error.TooFewArgs;

                                        return try eval(body, &new_env, temp_sand, perm_sand);
                                    },
                                    else => return error.InvalidClosure,
                                }
                            },
                            else => return error.InvalidClosure,
                        }
                    }
                },
                else => {},
            }
        },
        else => {},
    }

    return error.NotCallable;
}

fn value_to_env_real(v: *value_mod.Value, sand: *sand_mod.Sand) util.LispError!?*env_mod.EnvNode {
    switch (v.*) {
        .Nil => return null,
        .Symbol => |s| {
            if (util.mem_eql(s, "nil")) return null;
            return error.InvalidEnv;
        },
        .Cons => |data| {
            const pair = data.car;
            switch (pair.*) {
                .Cons => |p_data| {
                    const sym_val = p_data.car;
                    const val = p_data.cdr;
                    switch (sym_val.*) {
                        .Symbol => |name| {
                            return try env_mod.env_extend(name, val, try value_to_env_real(data.cdr, sand), sand);
                        },
                        else => return error.InvalidEnv,
                    }
                },
                else => return error.InvalidEnv,
            }
        },
        else => return error.InvalidEnv,
    }
}
