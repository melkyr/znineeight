// const_size_local_xmod — variant (e): a FUNCTION-LOCAL `const` whose
// initializer is an arithmetic expression of module consts, used as the size of
// a function-local array: `const N = A * B; var x: [N]u8`.
//
// Operator ruling (2026-09-16): variant (e) is IN SCOPE for Task 2c-F. It is a
// superset of the module-const-arithmetic gap: even a literal function-local
// `const N = 16; var x: [N]u8` fails today, because `evalConstU32Full`'s
// `ident_expr` arm resolves identifiers via `symbolLookupAllModules`
// (`sf/src/type_resolver.zig:815`) — MODULE symbol tables only. A function-local
// `const` is parsed as a local `var_decl` and is never registered there.
//
// RED today (Task 2b-F fixed point 0da3f1391075e3e77c54b626d5550e3b):
//   error[20]: identifier 'x' is not declared or imported in this module
// (dump rc=2, 0 `.c`; corpus classifier FAIL).
//
// Expected GREEN contract (Task 2c-F): the enclosing function's local-const
// scope is threaded into `TypeResolveEnv`; `N` folds to 16; `x.len == 16`; dump
// rc=0, 4 `.c`, gcc -m32 -std=c89 clean, link+run rc=0, no stdout.
//
// Fix locus: thread the function-local const scope into `TypeResolveEnv`
// (`sf/src/type_resolver.zig:26-33`, which today carries only
// `store/typereg/symbol_reg/interner/module_id`) and consult it from
// `evalConstU32Full`'s `ident_expr` arm; plus the `binary` case. See report Q5.
const A: usize = 4;
const B: usize = 4;

pub fn main() void {
    const N = A * B;
    var x: [N]u8 = undefined;
    if (x.len != 16) {
        @panic("const_size_local_xmod: array size mismatch");
    }
}
