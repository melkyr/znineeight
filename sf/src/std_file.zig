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
// writeAll loops. POSIX uses open/read/write/fsync/close/unlink/rename plus the
// _llseek syscall for 64-bit seeking. The pinned i386 target has a 32-bit
// off_t, so the POSIX side seeks via _llseek (with O_LARGEFILE at open) and
// reports i64 offsets; Windows already uses SetFilePointerEx (i64) /
// GetFileSizeEx. Payloads > 2 GiB work.

const arena_mod = @import("std_arena.zig");
const pal = @import("std_file_pal.zig");

@cInclude("<std_os_prelude.h>");
@cInclude("<fcntl.h>");
@cInclude("<stdio.h>");
// <sys/stat.h> supplies the POSIX stat(2) prototype for the mtime capability
// below (the Z98 extern live in std_file_pal.zig; the C prototype must be
// visible in this module's emitted C). Portable across the win32 branch too.
@cInclude("<sys/stat.h>");

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
// O_LARGEFILE (0100000): let a 32-bit process create/use files > 2 GiB. Without
// it a write past the 2 GiB mark fails EFBIG even after a 64-bit lseek.
const O_LARGEFILE: i32 = 32768;
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

// i386 Linux _llseek syscall number (__NR__llseek). The pinned target is
// i386, so this one constant carries the 64-bit seek on the POSIX side.
const SYS_LLSEEK: i32 = 140;

// --- file modification time (mtime) ---------------------------------------
// `struct stat` is ABI-specific, so the PAL passes an opaque byte buffer and the
// fields are read at probed offsets (the same S2-I layout-probe pattern std_time
// uses for struct timeval). Probe (2026-10-08, `gcc 12.2 -m32` / glibc 2.36,
// i386, no _FILE_OFFSET_BITS):
//   sizeof(struct stat) == 88
//   offsetof(struct stat, st_mtime) == 64   (32-bit time_t, 4 bytes)
//   offsetof(struct stat, st_size)  == 44
// The buffer is rounded up so a struct stat that later grows still fits; only
// the pinned i386 non-LFS layout is supported.
const STAT_BUF_BYTES: usize = 256;
const STAT_MTIME_OFFSET: usize = 64;

// win32 WIN32_FILE_ATTRIBUTE_DATA (x86): dwFileAttributes (4), ftCreationTime
// (8), ftLastAccessTime (8), ftLastWriteTime (8), dwFileSizeHigh/Low (8). A
// FILETIME is two DWORDs, so ftLastWriteTime.dwLowDateTime is at offset 20.
const WIN_FILE_ATTR_BYTES: usize = 40;
const WIN_FT_LASTWRITE_OFF: usize = 20;
const GET_FILEEX_INFO_STANDARD: u32 = 0;

// FILETIME counts 100-ns ticks from 1601-01-01; the Unix epoch is this many
// seconds later.
const FILETIME_TICKS_PER_SEC: i64 = 10000000;
const WINDOWS_EPOCH_DELTA_SECS: i64 = 11644473600;

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

// Little-endian 32-bit read from `b` at `off`, widened to i64 (no alignment
// assumption). Used for struct stat.st_mtime (i32 time_t) and for each half of a
// win32 FILETIME (two DWORDs).
fn leU32At(b: []const u8, off: usize) i64 {
    var v: i64 = @intCast(i64, b[off]);
    v = v | (@intCast(i64, b[off + 1]) << 8);
    v = v | (@intCast(i64, b[off + 2]) << 16);
    v = v | (@intCast(i64, b[off + 3]) << 24);
    return v;
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
        var flags: i32 = O_RDONLY | O_LARGEFILE;
        if (mode == Mode.Write) { flags = O_WRONLY | O_CREAT | O_TRUNC | O_LARGEFILE; }
        if (mode == Mode.Append) { flags = O_WRONLY | O_CREAT | O_APPEND | O_LARGEFILE; }
        if (mode == Mode.ReadWrite) { flags = O_RDWR | O_CREAT | O_LARGEFILE; }
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

// POSIX 64-bit seek. The i64 offset is split into the _llseek syscall's
// unsigned high/low words; the syscall writes the resulting absolute offset
// through an out-parameter, so the full i64 survives even though the C call is
// made through an implicit declaration (see std_file_pal.zig: a directly
// declared 64-bit-returning lseek64 has no author C prototype under the pinned
// -std=c89/no-LFS compilation and would truncate). whence is SEEK_SET/_CUR/_END.
fn llseekHandle(fd: i32, offset: i64, whence: i32) FileError!i64 {
    if (@isWindows()) {
        // POSIX-only helper: the Windows 64-bit seek is SetFilePointerEx in
        // seekHandle. This branch is pruned under -osw so the emitted C carries
        // no `syscall` reference (mingw has no such symbol).
        return error.SeekFailed;
    } else {
        var high: u32 = @intCast(u32, (offset >> 32) & 4294967295);
        var low: u32 = @intCast(u32, offset & 4294967295);
        var res: i64 = 0;
        const r = pal.syscall(SYS_LLSEEK, fd, high, low, &res, whence);
        if (r != @intCast(i32, 0)) return error.SeekFailed;
        return res;
    }
}

fn seekHandle(h: *void, offset: i64, whence: i32) FileError!i64 {
    if (@isWindows()) {
        var np: i64 = 0;
        if (pal.SetFilePointerEx(h, offset, &np, @intCast(u32, whence)) == 0) return error.SeekFailed;
        return np;
    } else {
        // 64-bit offset (the lseek64 equivalent via the _llseek syscall): a
        // payload may seek past the 2 GiB i32 off_t boundary. open() also passes
        // O_LARGEFILE so a 32-bit process may grow the file past 2 GiB.
        return llseekHandle(@intCast(i32, @ptrToInt(h)), offset, whence);
    }
}

fn sizeHandle(h: *void) FileError!i64 {
    if (@isWindows()) {
        var sz: i64 = 0;
        if (pal.GetFileSizeEx(h, &sz) == 0) return error.SizeFailed;
        return sz;
    } else {
        const fd = @intCast(i32, @ptrToInt(h));
        const cur = llseekHandle(fd, @intCast(i64, 0), SEEK_CUR_I32) catch {
            return error.SizeFailed;
        };
        const end = llseekHandle(fd, @intCast(i64, 0), SEEK_END_I32) catch {
            return error.SizeFailed;
        };
        const restored = llseekHandle(fd, cur, SEEK_SET_I32) catch {
            return error.SizeFailed;
        };
        _ = restored;
        return end;
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

// Modification time in seconds since the Unix epoch. POSIX: stat(2) into an
// opaque buffer and read st_mtime at STAT_MTIME_OFFSET; win32:
// GetFileAttributesExA + ftLastWriteTime (FILETIME 100-ns ticks). A missing or
// un-statable path is OpenFailed (the granularity `open` uses). Used by the
// z9torr resume sidecar's mtime validation (spec 2026-10-08 §7).
pub fn mtime(path: []const u8) FileError!i64 {
    var cbuf: [PATH_BUF]u8 = undefined;
    if (!cstr(path, cbuf[0..])) return error.OpenFailed;
    if (@isWindows()) {
        var info: [WIN_FILE_ATTR_BYTES]u8 = undefined;
        if (pal.GetFileAttributesExA(@ptrCast([*]const u8, &cbuf[0]), GET_FILEEX_INFO_STANDARD, @ptrCast(*void, &info[0])) == 0) return error.OpenFailed;
        var lo: i64 = leU32At(info[0..], WIN_FT_LASTWRITE_OFF);
        var hi: i64 = leU32At(info[0..], WIN_FT_LASTWRITE_OFF + 4);
        var ticks: i64 = (hi << 32) | lo;
        return ticks / FILETIME_TICKS_PER_SEC - WINDOWS_EPOCH_DELTA_SECS;
    } else {
        var stbuf: [STAT_BUF_BYTES]u8 = undefined;
        if (pal.stat(@ptrCast([*]const u8, &cbuf[0]), @ptrCast(*void, &stbuf[0])) != 0) return error.OpenFailed;
        return leU32At(stbuf[0..], STAT_MTIME_OFFSET);
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
