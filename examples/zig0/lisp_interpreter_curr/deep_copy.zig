const value_mod = @import("value.zig");
const sand_mod = @import("sand.zig");
const util = @import("util.zig");

pub fn deep_copy(v: *value_mod.Value, sand: *sand_mod.Sand) util.LispError!*value_mod.Value {
    switch (v.*) {
        .Nil => return try value_mod.alloc_nil(sand),
        .Int => |val| return try value_mod.alloc_int(val, sand),
        .Bool => |val| return try value_mod.alloc_bool(val, sand),
        .Symbol => |name| return try value_mod.alloc_symbol(name, sand),
        .Builtin => |f| return try value_mod.alloc_builtin(f, sand),
        .Cons => |data| {
            const car = try deep_copy(data.car, sand);
            const cdr = try deep_copy(data.cdr, sand);
            return try value_mod.alloc_cons(car, cdr, sand);
        },
    }
    return error.Unreachable;
}
