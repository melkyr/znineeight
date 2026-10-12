const Diagnostic = @import("../diagnostics.zig").Diagnostic;

pub fn insertionSort(items: []Diagnostic, cmp: fn (a: *const Diagnostic, b: *const Diagnostic) i32) void {
    var i: u32 = 1;
    while (i < @intCast(u32, items.len)) {
        var key = items[@intCast(usize, i)];
        var j: i32 = @intCast(i32, i);
        while (j > 0 and cmp(&items[@intCast(usize, j - 1)], &key) > 0) {
            items[@intCast(usize, j)] = items[@intCast(usize, j - 1)];
            j -= 1;
        }
        items[@intCast(usize, j)] = key;
        i += 1;
    }
}
