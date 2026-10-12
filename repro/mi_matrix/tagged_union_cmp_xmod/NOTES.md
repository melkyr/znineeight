# tagged_union_cmp_xmod — DUMP FAIL / compiler crash (cross-module tagged-union `==` SEGV)  [R2, 2026-08-08]

## What it tests
A cross-module tagged-union member comparison in an `==` expression. `lib.zig`
defines `pub const Shape = union(enum) { Circle: i32, Square: i32, Triangle: i32 }`.
`main.zig` imports it and compares a function parameter against a member:
`if (s == lib_mod.Shape.Circle)`. Faithful trigger of the I3 separate finding
(I3 report `I-missing-fwd-report.md`: "A cross-module tagged-union literal in `==`
additionally SEGVs the compiler (`typeRegistryGetStructFields` via the generic
field-access path)"). Same-module control (`s == Shape.Circle` declared inside
lib.zig) does NOT crash zig1 (it emits C, though gcc-invalid — see below).

## The compiler gap
The compiler **crashes (SEGV)** on a valid-to-parse cross-module tagged-union
member `==`. This is a compiler crash — NOT a graceful `error[3000]`/`error[3020]`
diagnostic and NOT a silent TYPE_VOID degradation (which is what plain-enum
cross-module member access does). Crash occurs during **phase_LIRLowering**:
`lowerExprImpl` walks the `s == lib_mod.Shape.Circle` comparison's RHS (the
generic field-access path) and calls `typeRegistryGetStructFields` on a tagged-
union type that has no struct-fields entry in the importing module — null
dereference. Classified **DUMP FAIL / compiler crash** (0 `.c` emitted, no
diagnostic). This is NOT a corpus FAIL by the gcc-exit classifier: a SEGV may be
reported as rc≥128 (non-ASan) or an ASan DEADLYSIGNAL abort (this build, rc=1),
so the corpus classifier may or may not bucket it as CRASH — documented honestly.

## Measured result (2026-08-08, sf/build/out_release/zig1)
- `zig1 --dump-c89 --output-dir DIR repro/mi_matrix/tagged_union_cmp_xmod/main.zig`
  → **rc=1**, 0 `.c` emitted.
- stderr: `AddressSanitizer:DEADLYSIGNAL` → `ERROR: AddressSanitizer: SEGV on
  unknown address 0x00000000`, frame 0 = `typeRegistryGetStructFields`
  (sf/build/out_release/zig1+0x23fa80), frame 1 = `lowerExprImpl`
  (zig1+0x142888), via `phase_LIRLowering` (zig1+0x19d2a5). (ASan build
  converts the SIGSEGV to a DEADLYSIGNAL abort, hence rc=1; a non-ASan build
  would exit 139.)
- NOTE on extern-fn placement: the brief's verbatim `main.zig` declares
  `extern fn __bootstrap_print_int` INSIDE `pub fn main()`. With that placement
  zig1 fails EARLIER with `error[3020]: internal error: unhandled node kind in
  type resolution` at main.zig:1:28 (the in-body fn_decl reaches
  `semanticAnalyzerResolveExpr`'s unhandled-kinds branch) — masking the SEGV.
  Per the established repro convention (file-scope `extern fn`, e.g.
  `repro/mi_matrix/switch_char_single/main.zig`), the committed `main.zig`
  declares it at file scope, which reaches the intended SEGV. The 3020 IS a
  separate pre-existing frontend quirk (in-body fn_decl), not this defect.
- Attribution: removing the `==` (Variant C: same cross-module union param +
  init, no comparison) compiles clean (rc=0, C emitted) — the SEGV is caused by
  the cross-module tagged-union member `==` specifically.

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy does NOT compile clean — it **rejects** the `==`
with a clean type error:
`/tmp/main.zig:5:11: error: type mismatch` /
`hint: invalid operands for comparison operator '==': 'union Shape' and
'comptime_int'` (rc=1, no crash). zig0 rejects this exact `union == member`
form even SAME-module (verified) — it never crashes, it rejects gracefully.
So the oracle's reference behavior is a GRACEFUL REJECTION, not a successful
compile: the post-fix expectation per the oracle is that zig1 must NOT SEGV —
it should either reject the `==` cleanly like zig0 or (if union `==` is to be
supported) emit valid C. NOTE: the brief's Step-3 expectation ("compiles clean
rc=0") is NOT met by measurement; the oracle rejects with a type-mismatch
diagnostic. This is a discrepancy the I6 investigation + operator ruling must
adjudicate (fix target: graceful rejection vs working compile).
Also flagged: zig1's same-module `s == Shape.Circle` path (which does not crash)
emits gcc-invalid C (`zT_2 = s == zT_1;` — binary `==` on two `Shape` structs:
`error: invalid operands to binary == (have 'zT_4380DDC6_Shape' and
'zT_4380DDC6_Shape')`) — the same-module emission path is itself broken, so the
I3 assumption that "same-module tagged-union `==` works" holds only as
"does not crash", not "emits valid C". F6 may need to address both.

## Expected classification
DUMP FAIL / compiler crash (SEGV), 0 `.c` emitted. Not a green-guard (the
compiler does not reject gracefully — it segfaults). Under the corpus
gcc-exit classifier this is a CRASH (rc=1 ASan DEADLYSIGNAL / rc=139 raw), a
distinct bucket from FAIL/ICE/OK. Post-fix per the oracle reference the
program should at minimum compile without crashing; expected final state is
either OK (valid `==` emission, needs same-module union-`==` emission fix too)
or a green-guard (clean rejection mirroring zig0), per the I6/F6 ruling.
