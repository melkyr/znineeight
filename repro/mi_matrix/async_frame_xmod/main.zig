// Frame-size gate for the conservative P2 rule (Fix F1 widened it): the
// authoritative size reserves a field for every AST node reachable in the
// body, so the size is an upper bound over P3's precise live-across set.
// `worker` has one named local (`y`) and no live-across temp, so under the
// widened rule its frame is header(step/ctx/state) + param `x` + one 4-byte
// slot per body AST node = 68. The exact value is pinned; a change here means
// the P2 reservation rule or `worker`'s body changed.
//
// RED (pre-widening): 20. GREEN (post-Fix-F1): 68.

fn worker(x: i32) i32 {
    var y: i32 = x;
    @asyncSuspend(null);
    y = y + 1;
    return y;
}

fn plain() i32 {
    return 7;
}

pub fn main() void {
    var got: u32 = @asyncFrameSize(worker);
    if (got != 68) {
        @panic("frame size mismatch");
    }
}
