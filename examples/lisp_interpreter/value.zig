const sand_mod = @import("sand.zig");

pub const ValueTag = enum {
    Nil,
    Int,
    Bool,
    Symbol,
    Cons,
    Builtin,
};

pub const ConsData = struct {
    car: *Value,
    cdr: *Value,
};

pub const ValueData = union {
    Int: i64,
    Bool: bool,
    Symbol: []const u8,
    Cons: ConsData,
    Builtin: *void,
};

pub const Value = struct {
    tag: ValueTag,
    data: ValueData,
};

pub fn alloc_value(arena: *sand_mod.LispSand) anyerror!*Value {
    const mem = try sand_mod.lisp_sand_alloc(arena, @sizeOf(Value), @alignOf(Value));
    return @ptrCast(*Value, mem);
}

pub fn alloc_cons(car: *Value, cdr: *Value, arena: *sand_mod.LispSand) anyerror!*Value {
    const v = try alloc_value(arena);
    v.tag = ValueTag.Cons;
    v.data.Cons.car = car;
    v.data.Cons.cdr = cdr;
    return v;
}

pub fn alloc_int(val: i64, arena: *sand_mod.LispSand) anyerror!*Value {
    const v = try alloc_value(arena);
    v.tag = ValueTag.Int;
    v.data.Int = val;
    return v;
}

pub fn alloc_bool(val: bool, arena: *sand_mod.LispSand) anyerror!*Value {
    const v = try alloc_value(arena);
    v.tag = ValueTag.Bool;
    v.data.Bool = val;
    return v;
}

pub fn alloc_symbol(name: []const u8, arena: *sand_mod.LispSand) anyerror!*Value {
    const v = try alloc_value(arena);
    v.tag = ValueTag.Symbol;
    v.data.Symbol = name;
    return v;
}

pub fn alloc_nil(arena: *sand_mod.LispSand) anyerror!*Value {
    const v = try alloc_value(arena);
    v.tag = ValueTag.Nil;
    return v;
}

pub fn alloc_builtin(f: *void, arena: *sand_mod.LispSand) anyerror!*Value {
    const v = try alloc_value(arena);
    v.tag = ValueTag.Builtin;
    v.data.Builtin = f;
    return v;
}
