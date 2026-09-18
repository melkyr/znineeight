// std_stdin.zig — Z98 std lib L3: line-based input from process stdin.
//
// Contract (blueprint §3 L3): alloc readAll only | errors OutOfMemory, Io |
// coroutine no (see §4). OS specifics live in the std-side PAL
// std_stdin_pal.zig (R8); the compiler PAL (pal.zig / zig_pal.c) is never
// touched. The stdin handle is wrapped in a std_file.File and read through
// std_file, so the win32 HANDLE / POSIX fd logic is shared with std_file and
// the compiler-PAL `pal_file_*` surface stays untouched.
//
// readLine reads one byte at a time so it never consumes past the line's
// terminator (no internal buffer, no allocation); the only module state is the
// one-byte boundary CR carry described below. readAll grows a single arena
// buffer by doubling.

const file_mod = @import("std_file.zig");
const arena_mod = @import("std_arena.zig");
const pal = @import("std_stdin_pal.zig");

@cInclude("<std_os_prelude.h>");

// One error set per module (R2). Only readAll allocates (R1), so OutOfMemory
// is readAll's arena error; Io is a read failure from either reader (readLine
// and readAll both propagate it).
pub const StdinError = error{OutOfMemory, Io};

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
// fields) and keeps std_stdin stateless: the fd/HANDLE is the whole state. Any
// read failure is mapped to the module's error.Io — std_file's ReadFailed is
// not part of StdinError (the std_net mapErr pattern), so the declared set is
// exactly what readLine/readAll can return.
fn readStdin(buf: []u8) StdinError!usize {
    var f = file_mod.File{ .handle = stdinHandle(), .size_cache = @intCast(i64, -1), .arena = nullArena() };
    return file_mod.read(&f, buf) catch return error.Io;
}

// The pending boundary byte: '\r' when a CR landed as the last byte of a full
// buffer and its \n may be the next unread byte. Module-level `undefined` (BSS
// zero) keeps the module out of runtime-init root seeding (see
// std_os.saved_argc); readLine is otherwise stateless.
var pending_cr: u8 = undefined;

// Read one line into buf, stripping the terminating \n (and the \r of \r\n).
// Returns a slice INTO buf; no allocation. null at EOF with no partial line.
// When the line is longer than buf, a full buf is returned and the remainder
// of the line stays in the stream for the next call.
//
// Precondition: buf.len > 0 (a zero-length buffer traps).
pub fn readLine(buf: []u8) StdinError!?[]u8 {
    if (buf.len == 0) @panic("std.stdin.readLine: zero-length buffer");
    var n: usize = 0;
    var saw_any: bool = false;
    var saw_nl: bool = false;

    // Resolve a CR carried over from a full buffer at the previous boundary.
    // Read the next byte: '\n' closes the CRLF (the previous call already
    // returned that line's text, so this is not a new empty line); any other
    // byte makes the CR a literal first byte of this line.
    if (pending_cr == '\r') {
        pending_cr = 0;
        var one: [1]u8 = undefined;
        const r = try readStdin(one[0..1]);
        if (r == 0) {
            // EOF immediately after the boundary CR: the CR was a literal
            // final byte, exposed as its own line.
            buf[0] = '\r';
            return buf[0..1];
        }
        if (one[0] != '\n') {
            buf[n] = '\r';
            n += 1;
            saw_any = true;
            if (n < buf.len) {
                buf[n] = one[0];
                n += 1;
            }
        }
    }

    while (n < buf.len) {
        var one: [1]u8 = undefined;
        const r = try readStdin(one[0..1]);
        if (r == 0) break;
        saw_any = true;
        if (one[0] == '\n') {
            saw_nl = true;
            break;
        }
        buf[n] = one[0];
        n += 1;
    }
    // Strip the \r of a \r\n terminator.
    if (saw_nl and n > 0 and buf[n - 1] == '\r') n -= 1;
    // A \r landing exactly at the buffer boundary (and not followed by an
    // in-buffer \n): carry it so the next call consumes the following \n as the
    // same terminator. This avoids leaking the \r into the line and avoids a
    // spurious empty line on the next call. Requires room to carry (n > 1).
    if (!saw_nl and n == buf.len and n > 1 and buf[n - 1] == '\r') {
        pending_cr = '\r';
        n -= 1;
    }
    if (!saw_any) return null;
    return buf[0..n];
}

// Read all of stdin into one arena allocation (grown by doubling). The errors
// are OutOfMemory and Io; a read failure propagates as error.Io.
pub fn readAll(arena: *arena_mod.Arena) StdinError![]u8 {
    var cap: usize = READ_CHUNK;
    var buf: [*]u8 = arena_mod.alloc(arena, cap) catch return error.OutOfMemory;
    var len: usize = 0;
    while (true) {
        if (len == cap) {
            // Probe for EOF BEFORE the grow step, so an input of exactly
            // READ_CHUNK bytes does not allocate a second buffer. A full buffer
            // is never misreported as EOF and the probed byte is not lost.
            var one: [1]u8 = undefined;
            const pr = try readStdin(one[0..1]);
            if (pr == 0) break;
            const ncap: usize = cap * 2;
            const nbuf: [*]u8 = arena_mod.alloc(arena, ncap) catch return error.OutOfMemory;
            var i: usize = 0;
            while (i < len) : (i += 1) nbuf[i] = buf[i];
            buf = nbuf;
            cap = ncap;
            buf[len] = one[0];
            len += 1;
        } else {
            const r = try readStdin(buf[len..cap]);
            if (r == 0) break;
            len += r;
        }
    }
    return buf[0..len];
}
