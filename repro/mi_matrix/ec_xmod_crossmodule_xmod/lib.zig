// ec_xmod_crossmodule_xmod — extra-children index-side spill, cross-module.
// Both modules contribute extra-children-bearing nodes: module_root decls,
// fn_call args, block statements, struct_decl fields, struct_init field inits.
// Contract: GREEN — dump rc=0, gcc-clean, self-contained link, run rc=0,
// stdout md5 stable x3.
pub const Pair = struct {
    x: i32,
    y: i32,
};

pub fn sum3(a: i32, b: i32, c: i32) i32 {
    return a + b + c;
}

pub fn makePair(a: i32, b: i32) Pair {
    return Pair{ .x = a, .y = b };
}

pub fn pairSum(p: Pair) i32 {
    return p.x + p.y;
}
