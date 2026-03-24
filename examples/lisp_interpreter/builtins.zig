const value_mod = @import("value.zig");
const util = @import("util.zig");

pub fn builtin_cons(args: []*value_mod.Value, arena: *value_mod.sand_mod.LispSand) anyerror!*value_mod.Value {
    if (args.len != 2) return error.WrongArity;
    return try value_mod.alloc_cons(args[0], args[1], arena);
}

pub fn builtin_car(args: []*value_mod.Value, arena: *value_mod.sand_mod.LispSand) anyerror!*value_mod.Value {
    if (args.len != 1) return error.WrongArity;
    if (args[0].tag == value_mod.ValueTag.Cons) {
        return args[0].data.Cons.car;
    }
    return error.NotACons;
}

pub fn builtin_cdr(args: []*value_mod.Value, arena: *value_mod.sand_mod.LispSand) anyerror!*value_mod.Value {
    if (args.len != 1) return error.WrongArity;
    if (args[0].tag == value_mod.ValueTag.Cons) {
        return args[0].data.Cons.cdr;
    }
    return error.NotACons;
}

pub fn builtin_add(args: []*value_mod.Value, arena: *value_mod.sand_mod.LispSand) anyerror!*value_mod.Value {
    var sum: i64 = 0;
    for (args) |arg| {
        if (arg.tag == value_mod.ValueTag.Int) {
            sum += arg.data.Int;
        } else {
            return error.NotAnInt;
        }
    }
    return try value_mod.alloc_int(sum, arena);
}

pub fn builtin_sub(args: []*value_mod.Value, arena: *value_mod.sand_mod.LispSand) anyerror!*value_mod.Value {
    if (args.len == 0) return error.WrongArity;
    var res: i64 = 0;
    if (args[0].tag == value_mod.ValueTag.Int) {
        res = args[0].data.Int;
    } else {
        return error.NotAnInt;
    }

    if (args.len == 1) {
        return try value_mod.alloc_int(-res, arena);
    }
    var i: usize = 1;
    while (i < args.len) {
        if (args[i].tag == value_mod.ValueTag.Int) {
            res -= args[i].data.Int;
        } else {
            return error.NotAnInt;
        }
        i += 1;
    }
    return try value_mod.alloc_int(res, arena);
}

pub fn builtin_mul(args: []*value_mod.Value, arena: *value_mod.sand_mod.LispSand) anyerror!*value_mod.Value {
    var res: i64 = 1;
    for (args) |arg| {
        if (arg.tag == value_mod.ValueTag.Int) {
            res *= arg.data.Int;
        } else {
            return error.NotAnInt;
        }
    }
    return try value_mod.alloc_int(res, arena);
}

pub fn builtin_div(args: []*value_mod.Value, arena: *value_mod.sand_mod.LispSand) anyerror!*value_mod.Value {
    if (args.len == 0) return error.WrongArity;
    var res: i64 = 0;
    if (args[0].tag == value_mod.ValueTag.Int) {
        res = args[0].data.Int;
    } else {
        return error.NotAnInt;
    }

    var i: usize = 1;
    while (i < args.len) {
        if (args[i].tag == value_mod.ValueTag.Int) {
            const v = args[i].data.Int;
            if (v == 0) return error.DivisionByZero;
            res /= v;
        } else {
            return error.NotAnInt;
        }
        i += 1;
    }
    return try value_mod.alloc_int(res, arena);
}

pub fn builtin_eq(args: []*value_mod.Value, arena: *value_mod.sand_mod.LispSand) anyerror!*value_mod.Value {
    if (args.len != 2) return error.WrongArity;
    const a = args[0];
    const b = args[1];
    var res = false;

    if (a.tag == value_mod.ValueTag.Int) {
        if (b.tag == value_mod.ValueTag.Int) {
            res = a.data.Int == b.data.Int;
        }
    } else if (a.tag == value_mod.ValueTag.Bool) {
        if (b.tag == value_mod.ValueTag.Bool) {
            res = a.data.Bool == b.data.Bool;
        }
    } else if (a.tag == value_mod.ValueTag.Symbol) {
        if (b.tag == value_mod.ValueTag.Symbol) {
            res = util.mem_eql(a.data.Symbol, b.data.Symbol);
        }
    } else if (a.tag == value_mod.ValueTag.Nil) {
        if (b.tag == value_mod.ValueTag.Nil) {
            res = true;
        }
    } else {
        res = a == b;
    }

    return try value_mod.alloc_bool(res, arena);
}

pub fn builtin_is_nil(args: []*value_mod.Value, arena: *value_mod.sand_mod.LispSand) anyerror!*value_mod.Value {
    if (args.len != 1) return error.WrongArity;
    var res = false;
    if (args[0].tag == value_mod.ValueTag.Nil) {
        res = true;
    } else if (args[0].tag == value_mod.ValueTag.Symbol) {
        res = util.mem_eql(args[0].data.Symbol, "nil");
    }
    return try value_mod.alloc_bool(res, arena);
}

pub fn builtin_lt(args: []*value_mod.Value, arena: *value_mod.sand_mod.LispSand) anyerror!*value_mod.Value {
    if (args.len != 2) return error.WrongArity;
    if (args[0].tag == value_mod.ValueTag.Int and args[1].tag == value_mod.ValueTag.Int) {
        return try value_mod.alloc_bool(args[0].data.Int < args[1].data.Int, arena);
    }
    return error.NotAnInt;
}

pub fn builtin_gt(args: []*value_mod.Value, arena: *value_mod.sand_mod.LispSand) anyerror!*value_mod.Value {
    if (args.len != 2) return error.WrongArity;
    if (args[0].tag == value_mod.ValueTag.Int and args[1].tag == value_mod.ValueTag.Int) {
        return try value_mod.alloc_bool(args[0].data.Int > args[1].data.Int, arena);
    }
    return error.NotAnInt;
}
