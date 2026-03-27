const value_mod = @import("value.zig");
const sand_mod = @import("sand.zig");

pub fn mem_eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) {
        if (a[i] != b[i]) return false;
        i += 1;
    }
    return true;
}

pub fn parse_int(s: []const u8) !i64 {
    var val: i64 = 0;
    var i: usize = 0;
    var negative = false;
    if (s.len > 0 and s[0] == '-') {
        negative = true;
        i += 1;
    }
    while (i < s.len) {
        const c = s[i];
        if (c < '0' or c > '9') return error.InvalidDigit;
        val = val * 10 + @intCast(i64, c - '0');
        i += 1;
    }
    return if (negative) -val else val;
}

pub fn boat_copy(v: *value_mod.Value, perm_sand: *sand_mod.LispSand) !*value_mod.Value {
    if (v.tag == value_mod.ValueTag.Cons) {
        const new_car = try boat_copy(v.data.Cons.car, perm_sand);
        const new_cdr = try boat_copy(v.data.Cons.cdr, perm_sand);
        return try value_mod.alloc_cons(new_car, new_cdr, perm_sand);
    } else {
        // Self-evaluating or already interned
        const new_v = try value_mod.alloc_value(perm_sand);
        new_v.* = v.*;
        return new_v;
    }
}

pub fn deep_copy(v: *value_mod.Value, perm_sand: *sand_mod.LispSand) !*value_mod.Value {
    return try boat_copy(v, perm_sand);
}
