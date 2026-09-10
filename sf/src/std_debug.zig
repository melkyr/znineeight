// std_debug.zig — Z98 logging + assertion helpers (STDLIB §3.4).
//
// Output routes ONLY through the @stdoutWrite / @putChar builtins (no cstdio,
// no externs, no C-runtime dependence). `panic` is a PRINTED abort followed by
// a non-returning trap: `@panic`/`unreachable` LOWER TO NO-OPS in user programs
// on this compiler (STDLIB Task-1 RED probe §5), so they MUST NOT be used here.
//
//   log(msg)        writes msg bytes verbatim
//   logInt(tag, n)  writes tag, ':', ' ', the signed decimal n, '\n'
//   assert(cond)    on false writes "assertion failed\n" then traps
//   panic(msg)      writes "panic: ", msg, '\n' then traps
//
// The trap path (while-true in a noreturn fn) HANGS by design — it is Win9x
// clean (no CRT) and cannot be a GREEN fixture run; GREEN fixtures exercise
// only passing asserts / log / logInt. The failing path is proven separately
// by a scratch probe run under a timeout.

pub fn log(msg: []const u8) void {
    @stdoutWrite(msg.ptr, msg.len);
}

pub fn logInt(tag: []const u8, n: i32) void {
    // Mirror std_io.printInt's digit decomposition (same buffer/reverse path).
    var tmp: [12]u8 = undefined;
    var len: usize = 0;
    var is_neg = false;
    var v: u32 = 0;
    if (n < 0) {
        is_neg = true;
        v = @intCast(u32, 0 - @intCast(i64, n));
    } else {
        v = @intCast(u32, n);
    }
    if (v == 0) {
        tmp[0] = '0';
        len = 1;
    } else {
        while (v > 0) {
            tmp[len] = '0' + @intCast(u8, v % 10);
            len += 1;
            v = v / 10;
        }
    }
    var out: [12]u8 = undefined;
    var pos: usize = 0;
    if (is_neg) {
        out[pos] = '-';
        pos += 1;
    }
    var k: usize = 0;
    while (k < len) : (k += 1) {
        out[pos] = tmp[len - 1 - k];
        pos += 1;
    }
    @stdoutWrite(tag.ptr, tag.len);
    @putChar(':');
    @putChar(' ');
    @stdoutWrite(@ptrCast([*]const u8, &out[0]), pos);
    @putChar('\n');
}

pub fn assert(cond: bool) void {
    if (!cond) {
        var m: []const u8 = "assertion failed";
        @stdoutWrite(m.ptr, m.len);
        @putChar('\n');
        trap();
    }
}

pub fn panic(msg: []const u8) noreturn {
    var p: []const u8 = "panic: ";
    @stdoutWrite(p.ptr, p.len);
    @stdoutWrite(msg.ptr, msg.len);
    @putChar('\n');
    trap();
}

// Printed-abort terminator: a non-returning trap usable on the Win9x target
// with no C-runtime or PAL dependency. Callers must not expect it to return.
fn trap() noreturn {
    while (true) {}
}
