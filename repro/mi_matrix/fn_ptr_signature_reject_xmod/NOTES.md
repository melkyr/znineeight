# fn_ptr_signature_reject_xmod — FX17-F reject census

One signature-mismatched function-pointer coercion per assignment/coercion
position; exactly one level-0 `error[3000]` each (`expected_error.txt`
`3000 23`), rc 2, 0 `.c`, classify GREEN. Wording is the site's existing
message plus the source/target kind notes (D1).

Positions (23 sites):

- var-decl (module): `const MConst` const initializer, `var MVar` var initializer;
- var-decl (local): `const f1`, `?fn` `const o1`, named-alias `const f3`,
  cross-module `const x1`, cross-module const `const X4`;
- assignment (local): `f2 = wrongPtr`;
- field init (struct literal): `Shape{ .draw_fn = wrongPtr }`,
  `?fn` `OptShape{ .draw_fn = wrongPtr }`, cross-module
  `Shape{ .draw_fn = lib.wrongPtr }`;
- field assignment: `s.draw_fn = wrongKind` (parameter kind), `wrongRet`
  (return type), `noArgs` (arity), `convCb` (callconv), `vararg` (variadic
  flag), `?fn` `o3.draw_fn`, reverse `s2.draw_fn = s.draw_fn`;
- call argument: `takes(wrongKind)` (direct value), `takes(fp)` (via a local
  pointer), `takesOpt(wrongPtr)` (`?fn`), `takes(lib.wrongPtr)` (cross-module);
- return: `fn getWrong() fn (*void) void { return wrongPtr; }`.

Before FX17-F the field-init/return/module-var/call-arg-via-var shapes were
silent (rc 0) and the local-decl/assign/field-assign shapes were only a
level-1 `warning[3000]`; gcc then warned `-Wincompatible-pointer-types` and
the mismatch ran with garbage. The matching forms are the positive control
`fn_ptr_signature_ok_xmod`.
