// d14_original_http2_eu — Phase 3.5 D14 exact original two-level shape.
//
// Reconstructed from `git show 022a59f2:sf/src/std_http2.zig` (parent of the
// `id_out` workaround): `submitUrl` performs the implicit await and returns the
// runtime id; `http2Get` tail-returns `submitUrl`. The 022a59f2 tree kept the
// two calls separate (submit-only), so this fixture adds the wait back with the
// public `h2.http2Wait` to recover the failing D14 shape.
//
// Compile-only: exercising a real suspension needs a live HTTP/2 peer. This
// fixture proves zig1 lowering/emission and the C build only.
const std = @import("std");
const h2 = @import("std_http2.zig");

fn submitUrl(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    try h2.http2Wait(c, id);
    return id;
}

fn http2Get(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    return submitUrl(c, id);
}

pub fn main() void {
    std.io.write("d14 original http2 eu compile-only\n");
}
