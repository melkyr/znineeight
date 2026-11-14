// const_size_local_xmod — variant (e): a FUNCTION-LOCAL `const` whose
// initializer is an arithmetic expression of module consts, used as the size of
// a function-local array: `const N = A * B; var x: [N]u8`.
//
// GREEN (Task 2c-F, fixed point 960575b70302c78a19cf6bc0cc129df5): a
// function-local `const` scope (`LocalConstScope`) is threaded into
// `TypeResolveEnv` from both resolution entry points
// (`front_resolution.resolveStmtTypes` and the sema var-decl arm), and
// `evalConstU32Full`'s `ident_expr` arm consults it before the module symbol
// tables; the `binary` case then folds `N = A * B` to 16. This fixture was RED
// at the Task-2b-F fixed point 0da3f1391075e3e77c54b626d5550e3b: a
// function-local `const` is parsed as a local `var_decl`, is never registered
// in the module symbol tables that `evalConstU32Full` searched, and the first
// use reported `error[20]: identifier 'x' is not declared or imported in this
// module` (dump rc=2, 0 `.c`).
//
// GREEN contract: `N` folds to 16; `x.len == 16`; dump rc=0, 4 `.c`, gcc
// -m32 -std=c89 clean, link+run rc=0, no stdout.
const A: usize = 4;
const B: usize = 4;

pub fn main() void {
    const N = A * B;
    var x: [N]u8 = undefined;
    if (x.len != 16) {
        @panic("const_size_local_xmod: array size mismatch");
    }
}
