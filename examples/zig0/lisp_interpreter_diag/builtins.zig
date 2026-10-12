const value_mod = @import("value.zig");
const util = @import("util.zig");
const sand_mod = @import("sand.zig");

pub fn builtin_cons(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 2) return error.WrongArity;
    return try value_mod.alloc_cons(args[0], args[1], arena);
}

pub fn builtin_car(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 1) return error.WrongArity;
    switch (args[0].*) {
        .Cons => |data| return data.car,
        else => return error.NotACons,
    }
}

pub fn builtin_cdr(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 1) return error.WrongArity;
    switch (args[0].*) {
        .Cons => |data| return data.cdr,
        else => return error.NotACons,
    }
}

pub fn builtin_add(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    var sum: i64 = 0;
    for (args) |arg| {
        switch (arg.*) {
            .Int => |val| sum += val,
            else => return error.NotAnInt,
        }
    }
    return try value_mod.alloc_int(sum, arena);
}

pub fn builtin_sub(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len == 0) return error.WrongArity;
    var res: i64 = 0;
    switch (args[0].*) {
        .Int => |val| res = val,
        else => return error.NotAnInt,
    }

    if (args.len == 1) {
        return try value_mod.alloc_int(-res, arena);
    }
    var i: usize = 1;
    while (i < args.len) {
        switch (args[i].*) {
            .Int => |val| res -= val,
            else => return error.NotAnInt,
        }
        i += 1;
    }
    return try value_mod.alloc_int(res, arena);
}

pub fn builtin_mul(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    var res: i64 = 1;
    for (args) |arg| {
        switch (arg.*) {
            .Int => |val| res *= val,
            else => return error.NotAnInt,
        }
    }
    return try value_mod.alloc_int(res, arena);
}

pub fn builtin_div(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len == 0) return error.WrongArity;
    var res: i64 = 0;
    switch (args[0].*) {
        .Int => |val| res = val,
        else => return error.NotAnInt,
    }

    var i: usize = 1;
    while (i < args.len) {
        switch (args[i].*) {
            .Int => |val| {
                if (val == 0) return error.DivisionByZero;
                res /= val;
            },
            else => return error.NotAnInt,
        }
        i += 1;
    }
    return try value_mod.alloc_int(res, arena);
}

pub fn builtin_eq(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 2) return error.WrongArity;
    const a = args[0];
    const b = args[1];
    var res = false;

    switch (a.*) {
        .Int => |av| {
            switch (b.*) {
                .Int => |bv| res = av == bv,
                else => {},
            }
        },
        .Bool => |av| {
            switch (b.*) {
                .Bool => |bv| res = av == bv,
                else => {},
            }
        },
        .Symbol => |av| {
            switch (b.*) {
                .Symbol => |bv| res = util.mem_eql(av, bv),
                else => {},
            }
        },
        .Nil => {
            switch (b.*) {
                .Nil => res = true,
                else => {},
            }
        },
        else => {
            res = a == b;
        },
    }

    return try value_mod.alloc_bool(res, arena);
}

pub fn builtin_is_nil(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 1) return error.WrongArity;
    var res = false;
    switch (args[0].*) {
        .Nil => res = true,
        .Symbol => |s| res = util.mem_eql(s, "nil"),
        else => {},
    }
    return try value_mod.alloc_bool(res, arena);
}

pub fn builtin_lt(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 2) return error.WrongArity;
    switch (args[0].*) {
        .Int => |av| {
            switch (args[1].*) {
                .Int => |bv| return try value_mod.alloc_bool(av < bv, arena),
                else => {},
            }
        },
        else => {},
    }
    return error.NotAnInt;
}

pub fn builtin_gt(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 2) return error.WrongArity;
    switch (args[0].*) {
        .Int => |av| {
            switch (args[1].*) {
                .Int => |bv| return try value_mod.alloc_bool(av > bv, arena),
                else => {},
            }
        },
        else => {},
    }
    return error.NotAnInt;
}
