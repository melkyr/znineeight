# tagged_payload_whole_reassign_xmod — FX16-F S2 positive control

Whole-union reassignment is the supported payload-mutation form:
`x = .{ .i = 5 }`, `x = .{ .box = ... }`, cross-module `lib.U{...}`, a
deref-whole-store `p.* = U{ .i = 21 }`, and payload reads (`x.i`, `x.box.w`,
`switch (x) { .box => |b| ... }`) all compile and run. Golden
`5 7 9 11 21 7` (deterministic 3x, rc 0). The rejected per-member stores are
pinned by `tagged_payload_store_reject_xmod`.
