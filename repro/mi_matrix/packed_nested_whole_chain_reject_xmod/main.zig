// packed_nested_whole_chain_reject_xmod — FX15-F residual reject fixture.
//
// A-full supports whole-value moves of nested packed sub-containers per leaf,
// EXCEPT a whole-sub-container store whose access chain crosses a byte-aligned
// (natural) container field below the packed edge (`first_packed + 1 < depth`):
// there is no addressable-lvalue model for that bit slice. The ruled behavior
// is the existing single clean level-0 `error[3000]` (rc 2, 0 `.c`), never a
// silent mis-emit. The symmetric whole-value READ of the same chain works
// (packed chain reads accumulate one offset and are supported).
const std = @import("std");
const Inner = packed struct { x: u2, y: u3 };
const Mid = packed struct { inner: Inner, z: u1 };
const Outer = packed struct { first: u2, mid: Mid, tail: u1 };
const S = struct { o: Outer };

pub fn main() i32 {
    var s: S = undefined;
    var v: Inner = .{ .x = 2, .y = 7 };
    s.o.mid.inner = v;
    std.io.print("{} {}\n", .{ s.o.mid.inner.x, s.o.mid.inner.y });
    return 0;
}
