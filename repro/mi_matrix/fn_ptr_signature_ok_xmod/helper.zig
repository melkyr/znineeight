// helper.zig — FX17-F positive-control fixture helper module.
//
// `right` has the matching `fn (*void) void` signature, so a cross-module
// function value assigned to a matching function-pointer type stays accepted.
pub fn right(data: *void) void {
    _ = data;
}

pub fn cb(data: *void) void {
    _ = data;
}
