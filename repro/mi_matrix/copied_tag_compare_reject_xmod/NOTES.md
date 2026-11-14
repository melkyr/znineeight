# copied_tag_compare_reject_xmod — FX16-F A4 reject (error[3076])

`const t = s.tag;` is a plain `u32` copy; a bare enum literal beside it has no
enum context. Before FX16-F each shape typed the comparison `void` and lowered
the literal to its name-id (silently false). A4 makes exactly this shape a
clean level-0 `error[3076]` (span on the literal, one per site, 0 `.c`, rc 2;
classify FAIL, the FX12/FX13 reject-class precedent). `s.tag == .m` (the A+
sugar shape) and typed-enum compares (`c == .Red`) are deliberately NOT in this
class; see the standalone mirror `repro/copied_tag_compare_reject.z98`.

**Fix round 1 (M1 pin).** The typed-binding form `var b: bool = t == .m` (the
last site above) rejects with the same level-0 `error[3076]` and additionally
co-fires the pre-existing `warning[3000] type mismatch in variable declaration
-- initialization type may not be compatible with declared type` (notes
`source: void` / `target: bool`), because the A4-rejected comparison still
returns `void`. The reject itself stays clean (rc 2 / 0 `.c`, classify FAIL);
the census is `3076 7`. This is the documented diagnostic shape, not a
behavior change.
