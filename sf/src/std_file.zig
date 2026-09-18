// std_file.zig — Z98 std lib L3: binary-safe file I/O. Owns the OS handle.
//
// Contract (blueprint §3 L3): alloc readAll only | errors FileError | coroutine
// no (see §4). OS specifics live in the std-side PAL std_file_pal.zig (R8); the
// compiler PAL (pal.zig / zig_pal.c) is never touched, and the compiler-PAL
// `pal_file_*` surface (std_io.zig) is neither used nor extended. Per-OS C
// prototypes come from the authorized std_os_prelude.h plus the portable
// <fcntl.h>/<stdio.h>.
//
// Win32 opens through CreateFileA, never fopen; size uses GetFileSizeEx, not
// ftell; read returns 0 at EOF, not an error; write may return fewer bytes, so
// writeAll loops. POSIX uses open/read/write/lseek/fsync/close/unlink/rename.
// On the pinned i386 target off_t is 32-bit, so seek rejects offsets outside
// the i32 range rather than silently truncating.

const arena_mod = @import("std_arena.zig");
const pal = @import("std_file_pal.zig");

@cInclude("<std_os_prelude.h>");
@cInclude("<fcntl.h>");
@cInclude("<stdio.h>");

// One error set per module (R2). OutOfMemory is readAll's arena error (R1).
pub const FileError = error{ OpenFailed, ReadFailed, WriteFailed, SeekFailed, SizeFailed, FlushFailed, RemoveFailed, RenameFailed, OutOfMemory };

pub const Mode = enum { Read, Write, Append, ReadWrite };
pub const SeekWhence = enum { Set, Cur, End };

// The blueprint §3 L3 File: the opaque OS handle (HANDLE on win32, fd on POSIX,
// stored as *void), the last size query, and the owning arena.
pub const File = struct {
    handle: *void,
    size_cache: i64,
    arena: *arena_mod.Arena,
};

// Longest supported path (NUL-terminated into a stack buffer before every OS
// call). Matches the POSIX PATH_MAX floor and exceeds win32 MAX_PATH.
const PATH_BUF: usize = 4096;

// POSIX open(2) flags (linux x86 numeric values; deliberately not the fcntl.h
// macros, so the emitted C is independent of the host header).
const O_RDONLY: i32 = 0;
const O_WRONLY: i32 = 1;
const O_RDWR: i32 = 2;
const O_CREAT: i32 = 64;
const O_TRUNC: i32 = 512;
const O_APPEND: i32 = 1024;
const POSIX_MODE_0644: i32 = 420;

// win32 CreateFileA constants (winnt.h values).
const GENERIC_READ: u32 = 2147483648;
const GENERIC_WRITE: u32 = 1073741824;
const GENERIC_READWRITE: u32 = 3221225472;
const FILE_SHARE_READ: u32 = 1;
const OPEN_EXISTING: u32 = 3;
const CREATE_ALWAYS: u32 = 2;
const OPEN_ALWAYS: u32 = 4;
const FILE_ATTRIBUTE_NORMAL: u32 = 128;
const INVALID_HANDLE_VALUE_U: usize = 4294967295;
const INVALID_FILE_ATTRIBUTES_U: u32 = 4294967295;

// SEEK_SET / SEEK_CUR / SEEK_END (identical on both targets).
const SEEK_SET_I32: i32 = 0;
const SEEK_CUR_I32: i32 = 1;
const SEEK_END_I32: i32 = 2;

// The null `void*` for the optional out-params (security attributes, overlapped,
// template file). Z98 `null` is optional-only; the same construction std_net /
// std_time use.
fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

// Copy `path` into `out` and NUL-terminate. Returns false when it does not fit
// (the caller maps that to its own failure error). No allocation.
fn cstr(path: []const u8, out: []u8) bool {
    if (path.len >= out.len) return false;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        out[i] = path[i];
    }
    out[path.len] = 0;
    return true;
}

// --- handle-level core (no File wrapper; writeAll has no arena) -------------

fn openHandle(path: []const u8, mode: Mode) FileError!*void {
    var cbuf: [PATH_BUF]u8 = undefined;
    if (!cstr(path, cbuf[0..])) return error.OpenFailed;
    if (@isWindows()) {
        var access: u32 = GENERIC_READ;
        var disp: u32 = OPEN_EXISTING;
        if (mode == Mode.Write) { access = GENERIC_WRITE; disp = CREATE_ALWAYS; }
        if (mode == Mode.Append) { access = GENERIC_WRITE; disp = OPEN_ALWAYS; }
        if (mode == Mode.ReadWrite) { access = GENERIC_READWRITE; disp = OPEN_ALWAYS; }
        const h = pal.CreateFileA(@ptrCast([*]const u8, &cbuf[0]), access, FILE_SHARE_READ, nullVoid(), disp, FILE_ATTRIBUTE_NORMAL, nullVoid());
        if (@ptrToInt(h) == INVALID_HANDLE_VALUE_U) return error.OpenFailed;
        if (mode == Mode.Append) {
            _ = seekHandle(h, @intCast(i64, 0), SEEK_END_I32) catch {
                closeHandle(h);
                return error.OpenFailed;
            };
        }
        return h;
    } else {
        var flags: i32 = O_RDONLY;
        if (mode == Mode.Write) { flags = O_WRONLY | O_CREAT | O_TRUNC; }
        if (mode == Mode.Append) { flags = O_WRONLY | O_CREAT | O_APPEND; }
        if (mode == Mode.ReadWrite) { flags = O_RDWR | O_CREAT; }
        const fd = pal.open(@ptrCast([*]const u8, &cbuf[0]), flags, POSIX_MODE_0644);
        if (fd < 0) return error.OpenFailed;
        return @intToPtr(*void, @intCast(usize, fd));
    }
}

fn closeHandle(h: *void) void {
    if (@isWindows()) {
        _ = pal.CloseHandle(h);
    } else {
        _ = pal.close(@intCast(i32, @ptrToInt(h)));
    }
}

fn readHandle(h: *void, buf: []u8) FileError!usize {
    if (buf.len == 0) return 0;
    if (@isWindows()) {
        var got: u32 = 0;
        if (pal.ReadFile(h, buf.ptr, @intCast(u32, buf.len), &got, nullVoid()) == 0) return error.ReadFailed;
        return @intCast(usize, got);
    } else {
        const n = pal.read(@intCast(i32, @ptrToInt(h)), buf.ptr, @intCast(u32, buf.len));
        if (n < 0) return error.ReadFailed;
        return @intCast(usize, n);
    }
}

fn writeHandle(h: *void, buf: []const u8) FileError!usize {
    if (buf.len == 0) return 0;
    if (@isWindows()) {
        var put: u32 = 0;
        if (pal.WriteFile(h, buf.ptr, @intCast(u32, buf.len), &put, nullVoid()) == 0) return error.WriteFailed;
        return @intCast(usize, put);
    } else {
        const n = pal.write(@intCast(i32, @ptrToInt(h)), buf.ptr, @intCast(u32, buf.len));
        if (n < 0) return error.WriteFailed;
        return @intCast(usize, n);
    }
}

fn seekHandle(h: *void, offset: i64, whence: i32) FileError!i64 {
    if (@isWindows()) {
        var np: i64 = 0;
        if (pal.SetFilePointerEx(h, offset, &np, @intCast(u32, whence)) == 0) return error.SeekFailed;
        return np;
    } else {
        // off_t is 32-bit: reject offsets that would truncate under @intCast.
        if (offset < @intCast(i64, 0) - @intCast(i64, 2147483648)) return error.SeekFailed;
        if (offset > @intCast(i64, 2147483647)) return error.SeekFailed;
        const r = pal.lseek(@intCast(i32, @ptrToInt(h)), @intCast(i32, offset), whence);
        if (r < 0) return error.SeekFailed;
        return @intCast(i64, r);
    }
}

fn sizeHandle(h: *void) FileError!i64 {
    if (@isWindows()) {
        var sz: i64 = 0;
        if (pal.GetFileSizeEx(h, &sz) == 0) return error.SizeFailed;
        return sz;
    } else {
        const fd = @intCast(i32, @ptrToInt(h));
        const cur = pal.lseek(fd, @intCast(i32, 0), SEEK_CUR_I32);
        if (cur < 0) return error.SizeFailed;
        const end = pal.lseek(fd, @intCast(i32, 0), SEEK_END_I32);
        if (end < 0) return error.SizeFailed;
        _ = pal.lseek(fd, cur, SEEK_SET_I32);
        return @intCast(i64, end);
    }
}

fn flushHandle(h: *void) FileError!void {
    if (@isWindows()) {
        if (pal.FlushFileBuffers(h) == 0) return error.FlushFailed;
    } else {
        if (pal.fsync(@intCast(i32, @ptrToInt(h))) != 0) return error.FlushFailed;
    }
}

// --- blueprint §3 L3 public surface ----------------------------------------

pub fn open(arena: *arena_mod.Arena, path: []const u8, mode: Mode) FileError!File {
    var h = try openHandle(path, mode);
    return File{ .handle = h, .size_cache = @intCast(i64, -1), .arena = arena };
}

pub fn close(f: *File) void {
    closeHandle(f.handle);
}

pub fn read(f: *File, buf: []u8) FileError!usize {
    return readHandle(f.handle, buf);
}

pub fn write(f: *File, buf: []const u8) FileError!usize {
    return writeHandle(f.handle, buf);
}

pub fn seek(f: *File, offset: i64, whence: SeekWhence) FileError!i64 {
    var w: i32 = SEEK_SET_I32;
    if (whence == SeekWhence.Cur) w = SEEK_CUR_I32;
    if (whence == SeekWhence.End) w = SEEK_END_I32;
    return seekHandle(f.handle, offset, w);
}

pub fn size(f: *File) FileError!i64 {
    const s = try sizeHandle(f.handle);
    f.size_cache = s;
    return s;
}

pub fn flush(f: *File) FileError!void {
    return flushHandle(f.handle);
}

pub fn exists(path: []const u8) bool {
    var cbuf: [PATH_BUF]u8 = undefined;
    if (!cstr(path, cbuf[0..])) return false;
    if (@isWindows()) {
        return pal.GetFileAttributesA(@ptrCast([*]const u8, &cbuf[0])) != INVALID_FILE_ATTRIBUTES_U;
    } else {
        return pal.access(@ptrCast([*]const u8, &cbuf[0]), @intCast(i32, 0)) == 0;
    }
}

pub fn remove(path: []const u8) FileError!void {
    var cbuf: [PATH_BUF]u8 = undefined;
    if (!cstr(path, cbuf[0..])) return error.RemoveFailed;
    if (@isWindows()) {
        if (pal.DeleteFileA(@ptrCast([*]const u8, &cbuf[0])) == 0) return error.RemoveFailed;
    } else {
        if (pal.unlink(@ptrCast([*]const u8, &cbuf[0])) != 0) return error.RemoveFailed;
    }
}

pub fn rename(old_path: []const u8, new_path: []const u8) FileError!void {
    var obuf: [PATH_BUF]u8 = undefined;
    var nbuf: [PATH_BUF]u8 = undefined;
    if (!cstr(old_path, obuf[0..])) return error.RenameFailed;
    if (!cstr(new_path, nbuf[0..])) return error.RenameFailed;
    if (@isWindows()) {
        if (pal.MoveFileA(@ptrCast([*]const u8, &obuf[0]), @ptrCast([*]const u8, &nbuf[0])) == 0) return error.RenameFailed;
    } else {
        if (pal.rename(@ptrCast([*]const u8, &obuf[0]), @ptrCast([*]const u8, &nbuf[0])) != 0) return error.RenameFailed;
    }
}

pub fn readAll(arena: *arena_mod.Arena, path: []const u8) FileError![]u8 {
    var f = try open(arena, path, Mode.Read);
    const sz = size(&f) catch {
        close(&f);
        return error.SizeFailed;
    };
    if (sz < 0) {
        close(&f);
        return error.SizeFailed;
    }
    const n: usize = @intCast(usize, sz);
    const raw: [*]u8 = arena_mod.alloc(arena, n) catch {
        close(&f);
        return error.OutOfMemory;
    };
    var got: usize = 0;
    while (got < n) {
        const r = read(&f, raw[got..n]) catch {
            close(&f);
            return error.ReadFailed;
        };
        if (r == 0) break;
        got += r;
    }
    close(&f);
    return raw[0..got];
}

pub fn writeAll(path: []const u8, data: []const u8) FileError!void {
    var h = try openHandle(path, Mode.Write);
    var off: usize = 0;
    while (off < data.len) {
        const w = writeHandle(h, data[off..data.len]) catch {
            closeHandle(h);
            return error.WriteFailed;
        };
        if (w == 0) {
            closeHandle(h);
            return error.WriteFailed;
        }
        off += w;
    }
    flushHandle(h) catch {
        closeHandle(h);
        return error.FlushFailed;
    };
    closeHandle(h);
}
