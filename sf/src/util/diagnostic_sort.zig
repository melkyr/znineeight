const Diagnostic = @import("../diagnostics.zig").Diagnostic;

fn compareDiag(a: *const Diagnostic, b: *const Diagnostic) i32 {
    if (a.file_id != b.file_id) {
        return @intCast(i32, a.file_id) - @intCast(i32, b.file_id);
    }
    if (a.span_start != b.span_start) {
        return @intCast(i32, a.span_start) - @intCast(i32, b.span_start);
    }
    if (a.level != b.level) {
        return @intCast(i32, a.level) - @intCast(i32, b.level);
    }
    return 0;
}

pub fn sortDiagnostics(diags: []Diagnostic) void {
    var i: usize = 1;
    while (i < diags.len) {
        var key = diags[i];
        var j: i32 = @intCast(i32, i);
        while (j > 0 and compareDiag(&diags[@intCast(usize, j - 1)], &key) > 0) {
            diags[@intCast(usize, j)] = diags[@intCast(usize, j - 1)];
            j -= 1;
        }
        diags[@intCast(usize, j)] = key;
        i += 1;
    }
}
