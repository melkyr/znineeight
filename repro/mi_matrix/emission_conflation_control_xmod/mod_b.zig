const mod_a = @import("mod_a.zig");
const Kind = mod_a.Kind;
const Type = mod_a.Type;
const CoercionKind = mod_a.CoercionKind;

pub fn ifExpr() i32 {
    return if (true)
        { var ck: Type = mod_a.makeType(); @intCast(i32, ck.id); }
    else
        { var ck: CoercionKind = mod_a.makeCoercion(); @intCast(i32, @enumToInt(ck)); };
}

pub fn switchExpr(k: Kind) i32 {
    return switch (k) {
        .a => { var ck: Type = mod_a.makeType(); @intCast(i32, ck.id); },
        .b => { var ck: CoercionKind = mod_a.makeCoercion(); @intCast(i32, @enumToInt(ck)); },
        else => 0,
    };
}
