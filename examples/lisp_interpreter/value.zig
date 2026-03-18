const arena_mod = @import("arena.zig");

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

pub fn alloc_value(arena: *arena_mod.LispArena) !*Value {
    const mem = try arena_mod.lisp_alloc(arena, @sizeOf(Value), @alignOf(Value));
    return @ptrCast(*Value, mem);
}

pub fn alloc_cons(car: *Value, cdr: *Value, arena: *arena_mod.LispArena) !*Value {
    const v = try alloc_value(arena);
    v.tag = ValueTag.Cons;
    v.data.Cons.car = car;
    v.data.Cons.cdr = cdr;
    return v;
}

pub fn alloc_int(val: i64, arena: *arena_mod.LispArena) !*Value {
    const v = try alloc_value(arena);
    v.tag = ValueTag.Int;
    v.data.Int = val;
    return v;
}

pub fn alloc_bool(val: bool, arena: *arena_mod.LispArena) !*Value {
    const v = try alloc_value(arena);
    v.tag = ValueTag.Bool;
    v.data.Bool = val;
    return v;
}

pub fn alloc_symbol(name: []const u8, arena: *arena_mod.LispArena) !*Value {
    const v = try alloc_value(arena);
    v.tag = ValueTag.Symbol;
    v.data.Symbol = name;
    return v;
}

pub fn alloc_nil(arena: *arena_mod.LispArena) !*Value {
    const v = try alloc_value(arena);
    v.tag = ValueTag.Nil;
    return v;
}

pub fn alloc_builtin(f: *void, arena: *arena_mod.LispArena) !*Value {
    const v = try alloc_value(arena);
    v.tag = ValueTag.Builtin;
    v.data.Builtin = f;
    return v;
}
