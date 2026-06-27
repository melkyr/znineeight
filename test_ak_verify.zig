const ast_mod = @import("ast.zig");
const AK = ast_mod.AstKind;

fn main() u8 {
    var r: u8 = @enumToInt(AK.shift_left);
    r = @enumToInt(AK.shift_right);
    r = @enumToInt(AK.bool_and);
    r = @enumToInt(AK.bool_or);
    r = @enumToInt(AK.cmp_eq);
    r = @enumToInt(AK.cmp_ne);
    r = @enumToInt(AK.cmp_lt);
    r = @enumToInt(AK.cmp_le);
    r = @enumToInt(AK.cmp_gt);
    r = @enumToInt(AK.cmp_ge);
    return r;
}
