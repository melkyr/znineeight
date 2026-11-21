// std_fmt.zig — the `print` formatting primitives, in Z98 (Task 1 of the
// z98-print-formatting plan; spec docs/superpowers/specs/2026-09-22-z98-print-formatting-design.md §4).
//
// The compiler keeps format-string parsing, per-argument static-type dispatch
// and validation (`lowerPrintFmt` + `getPrintFnName`); the formatting BODIES
// live here. Whenever a `print` is lowered the compiler auto-imports this
// module and emits a mangled cross-module call into `std.fmt` (the user needs
// no new import; `std.io.print` stays the entry point).
//
// The byte output goes through the SAME PAL primitives the retired C
// `std_print_*` bodies used (`pal_print_stdout` + `pal_i64_to_str` /
// `pal_u64_to_str` / `pal_f64_to_str`), so the observable formatting behavior
// of every route that existed before the seam move is byte-identical
// (including write ordering: `pal_print_stdout` is the unbuffered `write(1)`
// on POSIX, while the `@stdoutWrite` builtin emits buffered `fwrite`).
//
// What this module does NOT carry (all landed elsewhere): the width/signedness
// dispatch (Task 2, `printFnSourceName` in c89_emit.zig), the negative signed
// `{x}` form below ('-' + hex magnitude, oracle ruling R6), the integral-float
// fix (`pal_f64_to_str`), and the Task-4/5/6 generated per-type printers,
// enum/error-set name tables and pointer/hex-float helpers.

extern "c" fn pal_print_stdout(msg: [*]const u8, len: usize) void;
extern "c" fn pal_i64_to_str(val: i64, buf: [*]u8, bufsize: i32) i32;
extern "c" fn pal_u64_to_str(val: u64, buf: [*]u8, bufsize: i32) i32;
extern "c" fn pal_f64_to_str(val: f64, buf: [*]u8, bufsize: i32) i32;

fn writeBytes(ptr: [*]const u8, len: usize) void {
    if (len > 0) pal_print_stdout(ptr, len);
}

fn writeLit(s: []const u8) void {
    if (s.len > 0) pal_print_stdout(s.ptr, s.len);
}

pub fn printI32(v: i32) void {
    var buf: [16]u8 = undefined;
    var n = pal_i64_to_str(@intCast(i64, v), @ptrCast([*]u8, &buf[0]), @intCast(i32, 16));
    if (n > 0) writeBytes(@ptrCast([*]const u8, &buf[0]), @intCast(usize, n));
}

pub fn printU32(v: u32) void {
    var buf: [16]u8 = undefined;
    var n = pal_u64_to_str(@intCast(u64, v), @ptrCast([*]u8, &buf[0]), @intCast(i32, 16));
    if (n > 0) writeBytes(@ptrCast([*]const u8, &buf[0]), @intCast(usize, n));
}

pub fn printI64(v: i64) void {
    var buf: [24]u8 = undefined;
    var n = pal_i64_to_str(v, @ptrCast([*]u8, &buf[0]), @intCast(i32, 24));
    if (n > 0) writeBytes(@ptrCast([*]const u8, &buf[0]), @intCast(usize, n));
}

pub fn printU64(v: u64) void {
    var buf: [24]u8 = undefined;
    var n = pal_u64_to_str(v, @ptrCast([*]u8, &buf[0]), @intCast(i32, 24));
    if (n > 0) writeBytes(@ptrCast([*]const u8, &buf[0]), @intCast(usize, n));
}

pub fn printF64(v: f64) void {
    var buf: [32]u8 = undefined;
    var n = pal_f64_to_str(v, @ptrCast([*]u8, &buf[0]), @intCast(i32, 32));
    if (n > 0) writeBytes(@ptrCast([*]const u8, &buf[0]), @intCast(usize, n));
}

pub fn printBool(v: bool) void {
    if (v) {
        var t: []const u8 = "true";
        writeLit(t);
    } else {
        var f: []const u8 = "false";
        writeLit(f);
    }
}

pub fn printChar(c: u8) void {
    var cb: [1]u8 = undefined;
    cb[0] = c;
    pal_print_stdout(@ptrCast([*]const u8, &cb[0]), 1);
}

pub fn printStr(ptr: [*]const u8, len: usize) void {
    writeBytes(ptr, len);
}

// Hex digits, unsigned; the C bodies wrote the reversed remainder modulo 16.
fn writeHexDigitsU32(v: u32) void {
    if (v == 0) {
        var z: []const u8 = "0";
        writeLit(z);
        return;
    }
    var hex_digits: []const u8 = "0123456789abcdef";
    var tmp: [16]u8 = undefined;
    var tpos: usize = 0;
    var x = v;
    while (x > 0) {
        tmp[tpos] = hex_digits[@intCast(usize, x & @intCast(u32, 15))];
        tpos += 1;
        x = x >> 4;
    }
    var buf: [16]u8 = undefined;
    var pos: usize = 0;
    while (tpos > 0) {
        tpos -= 1;
        buf[pos] = tmp[tpos];
        pos += 1;
    }
    writeBytes(@ptrCast([*]const u8, &buf[0]), pos);
}

fn writeHexDigitsU64(v: u64) void {
    if (v == 0) {
        var z: []const u8 = "0";
        writeLit(z);
        return;
    }
    var hex_digits: []const u8 = "0123456789abcdef";
    var tmp: [24]u8 = undefined;
    var tpos: usize = 0;
    var x = v;
    while (x > 0) {
        tmp[tpos] = hex_digits[@intCast(usize, x & @intCast(u64, 15))];
        tpos += 1;
        x = x >> 4;
    }
    var buf: [24]u8 = undefined;
    var pos: usize = 0;
    while (tpos > 0) {
        tpos -= 1;
        buf[pos] = tmp[tpos];
        pos += 1;
    }
    writeBytes(@ptrCast([*]const u8, &buf[0]), pos);
}

pub fn printHexU32(v: u32) void {
    writeHexDigitsU32(v);
}

// Zig 0.15.2 `{x}` on a negative signed value prints '-' followed by the HEX
// MAGNITUDE (`-10` -> `-a`, `-549755813888` -> `-8000000000`) — NOT the two's
// complement and NOT signed decimal. Frozen table A12 records that oracle
// evidence (`p_ints ix=-8000000000`); the magnitude is computed in unsigned
// arithmetic so INT_MIN is handled.
pub fn printHexI32(v: i32) void {
    var mag: u32 = @bitCast(u32, v);
    if (v < 0) {
        var minus: [1]u8 = undefined;
        minus[0] = @intCast(u8, '-');
        pal_print_stdout(@ptrCast([*]const u8, &minus[0]), 1);
        mag = (~mag) +% 1;
    }
    writeHexDigitsU32(mag);
}

pub fn printHexU64(v: u64) void {
    writeHexDigitsU64(v);
}

pub fn printHexI64(v: i64) void {
    var mag: u64 = @bitCast(u64, v);
    if (v < 0) {
        var minus: [1]u8 = undefined;
        minus[0] = @intCast(u8, '-');
        pal_print_stdout(@ptrCast([*]const u8, &minus[0]), 1);
        mag = (~mag) +% 1;
    }
    writeHexDigitsU64(mag);
}
