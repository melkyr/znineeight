// FD1 helper for print_nontuple_container_reject_xmod: a non-tuple container
// in a non-root module must reject with error[3065] at its own span too.
const std = @import("std");

pub fn logVar(v: i32) void {
    std.io.print("helper={}\n", v);
}
