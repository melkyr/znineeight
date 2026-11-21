// compile with: ./zig0 -o /tmp/repro.c tests/nasty_z0_bugs/bug01_string_literal_slice.zig
// then: gcc -std=c89 -I/tmp/repro -c /tmp/repro/bug01_string_literal_slice.c -o /tmp/repro.o 2>&1
// Expected: C89 error "incompatible type for argument" on 2nd+ call
// Reproduces within sf/src/lexer.zig: lexerTestDiagnostics() - 2x lexerInit("literal")
// after 3 prior function calls (sourceManagerInit, stringInternerInit, diagnosticCollectorInit)

extern fn stderr_write(s: []const u8) void;

fn helper() u8 {
    return @intCast(u8, 42);
}

pub fn main() void {
    // Key: prior calls before string literals trigger the bug
    var x = helper();
    stderr_write("hello");
    x += helper();
    stderr_write("world");
    x += helper();
    stderr_write("and more");
    _ = x;
}
