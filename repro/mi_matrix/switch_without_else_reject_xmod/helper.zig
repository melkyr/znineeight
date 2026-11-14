// FA-a helper module for switch_without_else_reject_xmod: the no-`else`
// switch shape in a non-root module must be rejected too (error[3068]).
pub fn pick(x: i32) i32 {
    return switch (x) {
        1 => 10,
        2 => 20,
    };
}
