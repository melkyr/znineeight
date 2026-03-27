const dict = @import("dict.zig");

extern fn getchar() i32;
extern fn putchar(c: i32) i32;

pub fn readByte() i32 {
    return getchar();
}

pub fn writeByte(b: u8) void {
    _ = putchar(@intCast(i32, b));
}

/// Writes a 12-bit code as decimal space-separated for simplicity in this demo.
/// A real LZW would write bits, but decimal is easier to inspect.
pub fn writeCode(code: i32) void {
    if (code == 0) {
        writeByte('0');
    } else {
        var buf: [10]u8 = undefined;
        var i: usize = 0;
        var n = code;
        while (n > 0) {
            buf[i] = @intCast(u8, @intCast(i32, '0') + (n % 10));
            n /= 10;
            i += 1;
        }
        while (i > 0) {
            i -= 1;
            writeByte(buf[i]);
        }
    }
    writeByte(' ');
}

/// Reads a space-separated decimal code.
pub fn readCode() i32 {
    var code: i32 = 0;
    var found = false;
    while (true) {
        const c = getchar();
        if (c == -1) {
            if (found) return code;
            return -1;
        }
        const ch = @intCast(u8, c);
        if (ch >= '0' and ch <= '9') {
            code = code * 10 + @intCast(i32, ch - '0');
            found = true;
        } else if (found) {
            return code;
        }
    }
    return -1;
}

pub fn printStr(s: [*]const u8) void {
    var i: usize = 0;
    while (s[i] != 0) {
        writeByte(s[i]);
        i += 1;
    }
}

pub fn printErr(msg: [*]const u8) void {
    printStr("Error: ");
    printStr(msg);
    writeByte('\n');
}
