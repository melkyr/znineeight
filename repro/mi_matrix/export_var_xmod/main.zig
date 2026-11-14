// export_var_xmod — FEATURE-GAP RED fixture (export var).
// Feature: `export var` = source-named external storage symbol.
// RED today: parse FAIL.
// GREEN (contract): runtime "3\n" AND emitted C exposes non-static `counter`.
const std = @import("std");

export var counter: i32 = 0;

fn bump() void {
    counter += 1;
}

pub fn main() void {
    bump();
    bump();
    bump();
    std.io.printInt(counter);
    std.io.writeByte('\n');
}
