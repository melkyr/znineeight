# fn_ptr_signature_ok_xmod — FX17-F positive control

Every legal function-pointer coercion stays accepted and runtime-correct after
the FX17-F signature enforcement. Golden stdout `12` (single line),
deterministic 3x, rc 0.

Covered legal forms:

- exact-match local declaration, struct-literal field initializer, field
  assignment and named alias (`DrawFn`);
- a matching `extern "stdcall"` target type (initialized `undefined`; the real
  `extern "stdcall"` function-value match is compiled in the standalone
  positive `repro/fn_ptr_signature_ok.z98`, which is dump-only because an
  extern value has no emitted C definition);
- `?fn` null and value;
- explicit `@ptrCast` to a mismatched signature stays legal;
- `@ptrToInt`/`@intToPtr` round trip;
- `undefined` -> function pointer;
- function-pointer-returning function (`getOp`);
- cross-module same-signature value -> local / field / call argument;
- the `*const fn` double-pointer spelling (D4 residual): it keeps its
  pre-existing level-1 `warning[3000]` and is intentionally NOT enforced.

`acc` accumulates every observation and is printed once; the two no-op helper
calls (`lib.cb`) contribute 0. Observation order and contributions:
`f +1`, `s.draw_fn +1`, `fa +1`, `sc` via `@ptrCast(wrongSig) +4`,
`ip` (`addTwo`) `+2`, `g +1`, `xf +0` (no-op), `xs.draw_fn +0` (no-op),
`takes +1`, `takesOpt(null) +0`, `takesOpt(o2) +1` = `12`.
