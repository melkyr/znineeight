# copied_tag_compare_reject_xmod — FX16-F A4 reject (error[3076])

`const t = s.tag;` is a plain `u32` copy; a bare enum literal beside it has no
enum context. Before FX16-F each shape typed the comparison `void` and lowered
the literal to its name-id (silently false). A4 makes exactly this shape a
clean level-0 `error[3076]` (span on the literal, one per site, 0 `.c`, rc 2;
classify FAIL, the FX12/FX13 reject-class precedent). `s.tag == .m` (the A+
sugar shape) and typed-enum compares (`c == .Red`) are deliberately NOT in this
class; see the standalone mirror `repro/copied_tag_compare_reject.z98`.
