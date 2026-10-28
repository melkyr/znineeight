// Off-corpus mutable-for fixture (Task 3 Step 1a). Excluded from the corpus
// universe by the `known_excluded` guard in scripts/corpus/list_corpus_dirs.sh.
fn take(p: *u32) void {
    p.* = p.* + 1;
}

fn fill(s: []u32) void {
    for (s) |*x| {
        take(x);
        x.* = 1;
    }
}

pub fn main() void {
    var buf: [3]u32 = .{ 0, 0, 0 };
    fill(buf[0..]);
}
