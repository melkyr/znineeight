// std_stdin.zig — Z98 std lib L3: line-based input from process stdin.
//
// Contract (blueprint §3 L3): alloc readAll only | errors OutOfMemory |
// coroutine no (see §4). OS specifics live in the std-side PAL
// std_stdin_pal.zig (R8); the compiler PAL (pal.zig / zig_pal.c) is never
// touched. The stdin handle is wrapped in a std_file.File and read through
// std_file, so the win32 HANDLE / POSIX fd logic is shared with std_file and
// the compiler-PAL `pal_file_*` surface stays untouched.
//
// readLine reads one byte at a time so it never consumes past the line's
// terminator (no internal buffer, no allocation); readAll grows a single
// arena buffer by doubling.

const file_mod = @import("std_file.zig");
const arena_mod = @import("std_arena.zig");
const pal = @import("std_stdin_pal.zig");

@cInclude("<std_os_prelude.h>");

// One error set per module (R2). Only readAll allocates (R1), so OutOfMemory is
// the module's only error. readLine has no error return: a read failure is
// surfaced as EOF (null), the same as a clean end of input.
pub const StdinError = error{OutOfMemory};

// win32 STD_INPUT_HANDLE == (DWORD)-10.
const STD_INPUT_HANDLE: i32 = -10;

// readAll's initial buffer; it doubles while the arena can satisfy the growth.
const READ_CHUNK: usize = 4096;

// The null *Arena for the non-allocating readLine path. std_file.File carries
// an arena field, but read() never dereferences it, and readLine must not
// require the caller to pass one. The same @intToPtr construction std_file /
// std_net use for their optional out-params.
fn nullArena() *arena_mod.Arena {
    return @intToPtr(*arena_mod.Arena, 0);
}

// The process stdin handle: POSIX fd 0, or win32 GetStdHandle(STD_INPUT_HANDLE).
fn stdinHandle() *void {
    if (@isWindows()) return pal.GetStdHandle(STD_INPUT_HANDLE);
    return @intToPtr(*void, 0);
}

// One read through std_file's handle path. A fresh File is cheap (three
// fields) and keeps std_stdin stateless: the fd/HANDLE is the whole state.
fn readStdin(buf: []u8) file_mod.FileError!usize {
    var f = file_mod.File{ .handle = stdinHandle(), .size_cache = @intCast(i64, -1), .arena = nullArena() };
    return file_mod.read(&f, buf);
}

// Read one line into buf, stripping the terminating \n (and the \r of \r\n).
// Returns a slice INTO buf; no allocation. null at EOF with no partial line.
// When the line is longer than buf, a full buf is returned and the remainder
// of the line stays in the stream for the next call.
pub fn readLine(buf: []u8) ?[]u8 {
    var n: usize = 0;
    var saw_any: bool = false;
    var saw_nl: bool = false;
    while (n < buf.len) {
        var one: [1]u8 = undefined;
        const r = readStdin(one[0..1]) catch return null;
        if (r == 0) break;
        saw_any = true;
        if (one[0] == '\n') {
            saw_nl = true;
            break;
        }
        buf[n] = one[0];
        n += 1;
    }
    // Strip the \r of a \r\n terminator. A \r landing exactly at the buffer
    // boundary is not stripped here (its \n is still in the stream); the next
    // call returns the empty remainder.
    if (saw_nl and n > 0 and buf[n - 1] == '\r') n -= 1;
    if (!saw_any) return null;
    return buf[0..n];
}

// Read all of stdin into one arena allocation (grown by doubling). The only
// error is OutOfMemory; a read failure is treated as end of input.
pub fn readAll(arena: *arena_mod.Arena) StdinError![]u8 {
    var cap: usize = READ_CHUNK;
    var buf: [*]u8 = arena_mod.alloc(arena, cap) catch return error.OutOfMemory;
    var len: usize = 0;
    while (true) {
        if (len == cap) {
            const ncap: usize = cap * 2;
            const nbuf: [*]u8 = arena_mod.alloc(arena, ncap) catch return error.OutOfMemory;
            var i: usize = 0;
            while (i < len) : (i += 1) nbuf[i] = buf[i];
            buf = nbuf;
            cap = ncap;
        }
        const r = readStdin(buf[len..cap]) catch break;
        if (r == 0) break;
        len += r;
    }
    return buf[0..len];
}
