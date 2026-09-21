// intwidth_cast_xmod — INTWIDTH `@intCast` contract, RE-PINNED by Task 11S.
//
// SUPERSEDED (Task 11S, AMENDMENT 14 / operator ruling 2026-09-21): the
// INTWIDTH design originally specified that a narrowing comptime `@intCast`
// truncates/masks to the destination width (`@intCast(u3, 255)` -> 7,
// `@intCast(u8, 256)` -> 0). AMENDMENT 14 supersedes that: `@intCast` is
// range-checked (matching official Zig and `Language_Spec_Z98.md` §1.2), so an
// out-of-range comptime cast is a clean `error[3000]` reject. The truncate/mask
// behavior is covered by `intwidth_wrap_xmod`'s arithmetic wrap (`u3 7+1 -> 0`).
//
// Contract (post-11S): dump rc=2, 0 `.c`, `error[3000]` — the canonical
// classifier's GREEN clean-reject bucket. In-range narrow/widen casts stay
// accepted (`stdlib_intcast_range_xmod`, `intwidth_sign_extend_xmod`).
var t: u3 = @intCast(u3, 255);
var c: u8 = @intCast(u8, 256);

pub fn main() void {
    _ = t;
    _ = c;
}
