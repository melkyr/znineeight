pub fn writeByte(c: u8) void {
    @putChar(c);
}

pub fn write(data: []const u8) void {
    @stdoutWrite(data.ptr, data.len);
}

pub fn writeStr(s: [*]const c_char) void {
    var len: usize = 0;
    while (s[len] != 0) : (len += 1) {}
    @stdoutWrite(@ptrCast([*]const u8, s), len);
}

pub fn print(s: [*]const c_char, ...) void {
    writeStr(s);
}

pub fn printInt(n: i32) void {
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
    @stdoutWrite(@ptrCast([*]const u8, &out[0]), pos);
}

pub fn readByte() u8 {
    return @getChar();
}

pub fn sleepMs(ms: u32) void {
    @sleepMs(ms);
}

// --- File I/O (STDLIB §3.5, AMENDMENT 1) -----------------------------------
// Wraps the extended PAL file surface (zig_pal.c). No cstdio: the four
// pal_file_* symbols are declared here directly (extern "c") because the
// canonical lib install does not carry pal.zig; they resolve at link time
// against sf/src/include/zig_pal.c (linked into every program).
extern "c" fn pal_file_open(path: [*]const u8, flags: i32) usize;
extern "c" fn pal_file_write(fd: usize, buf: [*]const u8, len: u32) i32;
extern "c" fn pal_file_read(fd: usize, buf: [*]u8, len: u32) i32;
extern "c" fn pal_file_close(fd: usize) i32;

const INVALID_FD: usize = @intCast(usize, 0xFFFFFFFF);

// Mode encoding passed to pal_file_open; MUST match zig_pal.c PAL_FILE_OPEN_*.
const FILE_OPEN_WRITE: i32 = 0;
const FILE_OPEN_READ: i32 = 1;

// Returns null on open failure. (Z98 currently cannot read a re-exported
// module's pub const via `std.io.INVALID_FD`, so the error channel is the
// optional itself rather than a sentinel constant. The parameter is named
// `write_mode` — not `write` — because a parameter named `write` collides
// with this module's `pub fn write` in the compiler's name resolution.)
pub fn fileOpen(path: []const u8, write_mode: bool) ?usize {
    var c_path: [512]u8 = undefined;
    var i: usize = 0;
    while (i < path.len and i < 511) {
        c_path[i] = path[i];
        i += 1;
    }
    if (i >= 511) return null;
    c_path[i] = 0;
    var fd: usize = undefined;
    if (write_mode) {
        fd = pal_file_open(&c_path[0], FILE_OPEN_WRITE);
    } else {
        fd = pal_file_open(&c_path[0], FILE_OPEN_READ);
    }
    if (fd == INVALID_FD) return null;
    return fd;
}

pub fn fileWrite(fd: usize, data: []const u8) void {
    _ = pal_file_write(fd, data.ptr, @intCast(u32, data.len));
}

// Read up to buf.len bytes; returns bytes read (0 at EOF, also 0 on error —
// v1 has no separate read-error channel; fileOpen is where failure is caught).
pub fn fileRead(fd: usize, buf: []u8) usize {
    var got = pal_file_read(fd, buf.ptr, @intCast(u32, buf.len));
    if (got < 0) return 0;
    return @intCast(usize, got);
}

pub fn fileClose(fd: usize) void {
    _ = pal_file_close(fd);
}

