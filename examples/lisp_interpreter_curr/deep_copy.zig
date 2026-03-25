const value_mod = @import("value.zig");
const sand_mod = @import("sand.zig");
const util = @import("util.zig");

pub fn deep_copy(v: *value_mod.Value, sand: *sand_mod.Sand) util.LispError!*value_mod.Value {
    if (v.tag == value_mod.ValueTag.Nil) {
        return try value_mod.alloc_nil(sand);
    } else if (v.tag == value_mod.ValueTag.Int) {
        return try value_mod.alloc_int(v.data.Int, sand);
    } else if (v.tag == value_mod.ValueTag.Bool) {
        return try value_mod.alloc_bool(v.data.Bool, sand);
    } else if (v.tag == value_mod.ValueTag.Symbol) {
        return try value_mod.alloc_symbol(v.data.Symbol, sand);
    } else if (v.tag == value_mod.ValueTag.Builtin) {
        return try value_mod.alloc_builtin(v.data.Builtin, sand);
    } else if (v.tag == value_mod.ValueTag.Cons) {
        const car = try deep_copy(v.data.Cons.car, sand);
        const cdr = try deep_copy(v.data.Cons.cdr, sand);
        return try value_mod.alloc_cons(car, cdr, sand);
    } else {
        return error.Unreachable;
    }
}
