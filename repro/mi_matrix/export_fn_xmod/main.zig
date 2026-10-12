// export_fn_xmod — FEATURE-GAP RED fixture (export fn).
// Feature: `export fn` = source-named, externally-visible C symbol.
// RED today: kw_export has no parser handler -> clean FAIL (parse).
// GREEN (contract): runtime "81\n" AND emitted C contains a non-static
//   definition named `square` (symbol gate; source name, not temp-mangled).
const std = @import("std");

export fn square(n: i32) i32 {
    return n * n;
}

pub fn main() void {
    std.io.printInt(square(9));
    std.io.writeByte('\n');
}
