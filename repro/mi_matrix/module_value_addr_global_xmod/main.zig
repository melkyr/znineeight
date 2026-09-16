// module_value_addr_global_xmod — `&mid.leaf.counter` (address of a nested
// module global). This is declared residual gap #5.
//
// The l-value ADDRESS path `lowerLValueAddr` (`sf/src/lower.zig:1360`;
// field_access arm `:1399-1448`) has no module-base handling. For
// `&mid.leaf.counter` the base `mid.leaf` is a nested module alias, so
// `resolvedTypeTableGet` yields a `module_type`, the struct/union field lookup
// misses, and `iceAddrOfLValueUnsupported` (`:1341`) fires. The same ICE fires
// for a 1-level DIRECT import `&leaf.counter` — the gap is the missing
// address-of-a-module-global path, NOT nesting. Same-module `&g` already works
// (its `lowerLValueAddr` ident arm lowers the global via `lowerExpr` ->
// `load_global`, then `addr_of`).
//
// RED today (fixed point 43d41bfb903d56c153ebf653131aef6d): dump rc=3, 0 `.c`,
//   warning[3023]: module used as value expression
//   error[3043]: internal: unsupported address-of l-value (node N)
// (corpus classifier ICE: `error[3043]` is in the ICE regex).
//
// Expected GREEN contract (Task 2b-F): `p.* == 5`; after `p.* = 11` a value read
// of `mid.leaf.counter` sees 11; dump rc=0, 5 `.c`, gcc -m32 -std=c89 clean,
// link+run rc=0, no stdout. Fix locus: `lowerLValueAddr`'s field_access arm
// (`sf/src/lower.zig:1399`) — resolve the module base (reuse `resolveModuleBase`,
// `:2400`), then emit `load_global` for the member global followed by `addr_of`.
// No new `addr_of_global` LIR op is needed: the emitter aliases a `load_global`
// result temp to the global's C name, so `addr_of` on it renders `&zG_...` —
// exactly what the existing same-module `&g` path emits. See report Q5.
//
// GREEN (Task 2b-F, fixed point 0da3f1391075e3e77c54b626d5550e3b): dump rc=0,
// 5 `.c`, gcc -m32 -std=c89 clean, link+run rc=0, no stdout. `lowerLValueAddr`'s
// field_access arm now detects a module base via `resolveModuleBase`, looks up
// the member `SymbolKind.global`, and emits `load_global` + `addr_of`. Emitted
// evidence (`main`): `zT_2 = &zG_9CACDE23_counter;`.
const mid = @import("mid.zig");

pub fn main() void {
    var p: *i32 = &mid.leaf.counter;
    if (p.* != 5) {
        @panic("module_value_addr_global_xmod: nested global address read mismatch");
    }
    p.* = 11;
    if (mid.leaf.counter != 11) {
        @panic("module_value_addr_global_xmod: nested global address store mismatch");
    }
}
