// sig_negative.zig — SIG-1 negative signature contracts.
//
// Contract (analyzer tests/analyzers runner): exactly one diagnostic per
// negative shape — ERR_2010 (void parameter), ERR_2011 (incomplete base nested
// in `?`), ERR_2012 (anytype parameter), WARN_7010 (named return larger than
// 64 bytes). `Incomplete` and `Big` are seeded by the fixture harness registry
// because the analyzer-only pipeline has no sema type resolution.
fn void_param(p: void) void {
    _ = p;
}

fn anytype_param(p: anytype) void {
    _ = p;
}

fn incomplete_param(p: ?Incomplete) void {
    _ = p;
}

fn big_return() Big {
    return undefined;
}

pub fn main() void {
}
