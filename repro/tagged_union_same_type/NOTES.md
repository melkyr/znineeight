# tagged_union_same_type — GREEN (documented NON-ISSUE: same-type variants are runtime-correct by aliasing)

## Form
Tagged union with two variants of the SAME payload type, constructed with the second, read via switch:
```zig
const U = union(enum) { A: i32, B: i32 };
var u: U = U{ .B = 7 };
switch (u) { .A => |a| r = a + 100, .B => |b| r = b }
```

## Expected
`7` (the `.B` prong; the `.A` prong would give 107).

## Empirical result on HEAD `fefb46a2` (Task 6, 2026-07-09)
**GREEN — prints `7`.** dump rc=0, gcc 0 errors, run rc=0.

## Why this is a NON-ISSUE (not a bug), despite the emitter resolving payload variants by TYPE
The Task 2/3 emitter resolves a tagged-union payload variant by matching the src/result temp's `type_id`
against the variant field types — so two variants with the SAME type both resolve to the FIRST match (`A`).
Emitted C:
```c
zT_2 = 7;
zT_1.tag = zT_3;              /* tag = B's index (1) — CORRECT variant discriminant */
zT_1.payload.A._0 = zT_2;    /* written to A._0 (first-match name) */
...
/* .B prong read: */ b = u.payload.A._0;   /* reads A._0 — the SAME union bytes */
```
This is runtime-correct because:
1. **The tag is ALWAYS set to the true variant index** (`.B`), so `switch` selects the correct prong
   (`.B`, giving 7 — NOT `.A` giving 107).
2. `A._0` and `B._0` are the SAME `i32` at the SAME offset in the C `union payload` — they alias.
3. Read and write use the SAME first-match rule, so the bytes written by construction are exactly the bytes
   read back.
The variant NAME chosen in the emitted C (`A` vs `B`) is cosmetic; the bytes and the tag are correct.

Additionally, the READ path (`load_field`, `c89_emit.zig`) has had this identical first-match behavior all
along, so Task 3's write-side fix merely mirrors it — no new risk introduced.

## Scope / corpus impact
Neither real target has a same-type collision: lisp `Value` = all distinct types; mud `Command` has one
payload variant. This repro is kept as a GREEN GUARD documenting the (harmless) behavior.

## Cross-links
- Task 6 (`.opencode/plans/2026-07-08-tagged-union-payload-store.md`): verify-first, no fix needed.
- Task 2 contract report `.superpowers/sdd/tagged-union-task-2-report.md` §4 (known symmetric limitation).
