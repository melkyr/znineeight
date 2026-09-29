# tagged_tag_sugar_xmod — FX16-F A+ `.tag` contextual sugar positive pin

## What it tests
A direct `.tag` access on a tagged union (paren-transparent; pointer bases
auto-deref) used as a **comparison** operand or **switch condition** resolves
Z98 member shapes against the base union and compares/switches tag ordinals:
shorthand `.m`, same-module `Shape.m`, cross-module `lib.Shape.m`, alias
`lib.Alias.m`, member-on-left, all six comparison ops, payload-less and
payload-bearing members, `switch (s.tag)` shorthand/qualified/value forms, a
`|c|` capture (binds the u32 ordinal), nested switches, pointer reads (P1) and
the pointer `.tag` store (`p.tag = 1`, writes through), numeric controls
(`s.tag == 3`, `{3,0}` prongs, `@enumToInt`), copy control (`const t = s.tag;
t == 3`) and the adjacent plain-enum shorthand compare (`c == .Red`).

## Golden
`expected.txt` = `111111111100044403710153110111` (deterministic 3x,
`expected.rc` 0). Ordinals: Circle=0, Square=1, Empty=2, Line=3.

## Oracle
Zig 0.15.2 has **no `.tag` member** on unions. The Z98 golden is
Z98-semantics-defined: the equivalent Zig spelling is
`std.meta.activeTag(s)` (comparisons) and `switch (s)` (dispatch), and the
repo's oracle twin `activeTag`/`switch` program produces the identical byte
string. The A1 capture row (`switch (s.tag) { .Line => |c| }` binds the u32
ordinal) and the raw pointer tag store (`p2.tag = 1` without changing the
payload) are Z98-specific; the manual's migration block uses
`@as(Tag, u)`/`activeTag`/`switch (s)` instead.

## Fix
FX16-F (A+): a tag-access helper + one post-resolution comparison hook
(`semantic_analyzer.zig`), the switch condition context + capture bind, one
`lowerSwitchCaseItemValue` table check, P1 (pointer read deref), R1 (xmod
qualified relational init type) and the adjacent pointer-store emitter arm.
