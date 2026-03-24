const sand_mod = @import("sand.zig");
const util = @import("util.zig");

pub const Value = union(enum) {
    Nil: void,
    Int: i64,
    Bool: bool,
    Symbol: []const u8,
    Cons: struct {
        car: *Value,
        cdr: *Value,
    },
    Builtin: *void,
};

pub fn alloc_value(arena: *sand_mod.Sand) util.LispError!*Value {
    const mem = try sand_mod.sand_alloc(arena, @sizeOf(Value), @alignOf(Value));
    return @ptrCast(*Value, mem);
}

pub fn alloc_cons(car: *Value, cdr: *Value, arena: *sand_mod.Sand) util.LispError!*Value {
    const v = try alloc_value(arena);
    v.* = Value{ .Cons = .{ .car = car, .cdr = cdr } };
    return v;
}

pub fn alloc_int(val: i64, arena: *sand_mod.Sand) util.LispError!*Value {
    const v = try alloc_value(arena);
    v.* = Value{ .Int = val };
    return v;
}

pub fn alloc_bool(val: bool, arena: *sand_mod.Sand) util.LispError!*Value {
    const v = try alloc_value(arena);
    v.* = Value{ .Bool = val };
    return v;
}

pub fn alloc_symbol(name: []const u8, arena: *sand_mod.Sand) util.LispError!*Value {
    const v = try alloc_value(arena);
    v.* = Value{ .Symbol = name };
    return v;
}

pub fn alloc_nil(arena: *sand_mod.Sand) util.LispError!*Value {
    const v = try alloc_value(arena);
    v.* = Value{ .Nil = {} };
    return v;
}

pub fn alloc_builtin(f: *void, arena: *sand_mod.Sand) util.LispError!*Value {
    const v = try alloc_value(arena);
    v.* = Value{ .Builtin = f };
    return v;
}
