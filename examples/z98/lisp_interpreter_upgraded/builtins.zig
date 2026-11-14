const value_mod = @import("value.zig");
const util = @import("util.zig");
const sand_mod = @import("sand.zig");

const std = @import("std");
const env_mod = @import("env.zig");

const DemoOuter = struct {
    tag: u8,
    payload: u32,
};

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
    if (args[0].* == .Nil) {
        res = true;
    } else switch (args[0].*) {
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

pub fn builtin_layout(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 0) return error.WrongArity;
    std.io.printInt(@intCast(i32, @offsetOf(env_mod.EnvNode, "value")));
    std.io.print(" ");
    std.io.printInt(@intCast(i32, @bitSizeOf(bool)));
    std.io.print(" ");
    std.io.printInt(@intCast(i32, @bitSizeOf(i64)));
    std.io.print("\n");
    return try value_mod.alloc_nil(arena);
}

pub fn builtin_address(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 1) return error.WrongArity;
    const a = @intFromPtr(args[0]);
    return try value_mod.alloc_int(@intCast(i64, a), arena);
}

pub fn builtin_phys_eq(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 2) return error.WrongArity;
    const a = args[0];
    const b = args[1];
    var res = false;
    switch (a.*) {
        .Int => |av| { switch (b.*) { .Int => |bv| res = av == bv, else => {} } },
        .Bool => |av| { switch (b.*) { .Bool => |bv| res = av == bv, else => {} } },
        .Symbol => |av| { switch (b.*) { .Symbol => |bv| res = util.mem_eql(av, bv), else => {} } },
        .Nil => { switch (b.*) { .Nil => res = true, else => {} } },
        else => { res = a == b; },
    }
    return try value_mod.alloc_bool(res, arena);
}

pub fn builtin_ptr_check(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 1) return error.WrongArity;
    const a = @intFromPtr(args[0]);
    var p: *value_mod.Value = @ptrFromInt(a);
    const ok = p == args[0];
    return try value_mod.alloc_bool(ok, arena);
}

pub fn builtin_container_of(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 0) return error.WrongArity;
    var o = DemoOuter{ .tag = @intCast(u8, 7), .payload = @intCast(u32, 99) };
    const parent = @fieldParentPtr(DemoOuter, "payload", &o.payload);
    return try value_mod.alloc_bool(parent == &o, arena);
}

pub fn builtin_bitcast(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 0) return error.WrongArity;
    const u: u64 = 0xFFFFFFFFFFFFFFFF;
    const s = @bitCast(i64, u);
    return try value_mod.alloc_int(s, arena);
}

pub fn builtin_allocs(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 0) return error.WrongArity;
    return try value_mod.alloc_int(@intCast(i64, value_mod.alloc_count), arena);
}

pub fn builtin_classify(args: []*value_mod.Value, arena: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (args.len != 1) return error.WrongArity;
    switch (args[0].*) {
        .Symbol => |s| {
            var lower: i32 = 0;
            var upper: i32 = 0;
            var digit: i32 = 0;
            var i: usize = 0;
            while (i < s.len) : (i += 1) {
                switch (s[i]) {
                    'a'...'z' => lower += 1,
                    'A'...'Z' => upper += 1,
                    '0'...'9' => digit += 1,
                    else => {},
                }
            }
            std.io.printInt(lower);
            std.io.print(" ");
            std.io.printInt(upper);
            std.io.print(" ");
            std.io.printInt(digit);
            std.io.print("\n");
            return try value_mod.alloc_nil(arena);
        },
        else => return error.NotAnInt,
    }
}
