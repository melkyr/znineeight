# tagged_payload_store_reject_xmod — FX16-F S2 reject census

One offending statement per site; exactly one level-0 `error[3000]` each
(`expected_error.txt` `3000 9`), rc 2, 0 `.c`, classify GREEN:

- store sites (6): local `x.i = 5`, nested `b.box = .{...}`, global `g.i = 5`,
  pointer param `p.i = 5`, compound `y.i += 5`, cross-module `z.i = 5`;
- address-of sites (3): nested leaf `b.box.w = 7`, `&y.i`, cross-module
  `z.box.w = 7`.

Wording (sibling-consistent with the packed-store guards):
`cannot store to a tagged-union payload member; assign the whole union instead
(e.g. x = .{ .i = 5 })` and the address twin
`cannot take the address of a tagged-union payload member; assign the whole
union instead (e.g. x = .{ .i = 5 })`.

Before FX16-F these were `error[3043]` ICEs (rc 3). The supported form is the
whole-union reassignment (positive control
`tagged_payload_whole_reassign_xmod`).
