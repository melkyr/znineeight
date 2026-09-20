# I/O — `std.io` + `std_file` + `std_stdin`

| | |
|---|---|
| **Modules** | `std.io`, `std_file`, `std_stdin` |
| **Layers** | `std.io` — core (builtin-backed): console output over the builtins plus a thin descriptor file surface over the compiler PAL; `std_file`, `std_stdin` — `L3` owned-handle file I/O and stdin line readers |
| **Import (re-export)** | `const std = @import("std");` → `std.io` |
| **Import (by path)** | `const std_file = @import("std_file");`, `const std_stdin = @import("std_stdin");` |

## Module overview

This domain has three layers of I/O. `std.io` is the low-level surface: console
writers (`write`, `writeByte`, `writeStr`, `print`, `printInt`), a reader
(`readByte`), and a small descriptor-based file API (`fileOpen`, `fileRead`,
`fileWrite`, `fileClose`). `std_file` is the higher-level, owned-handle file
API: it opens a `File` with a `Mode`, reads/writes/seek/sizes/flushes it, and
offers whole-file helpers (`readAll`, `writeAll`) plus path operations
(`exists`, `remove`, `rename`). `std_stdin` reads lines and the whole of
standard input.

**Two file surfaces.** `std.io`'s `fileOpen` returns a raw OS descriptor
(`usize`) or `null`; it is a thin wrapper over the compiler's private file
primitives, its path is copied into a 512-byte stack buffer, and its read path has
no separate error channel (0 means both EOF and error). `std_file` is the
recommended surface for new code: it owns a `File` handle, uses
`CreateFileA`/`open` through the std-side PAL, reports a full `FileError`, caps
paths at 4096 bytes, and handles partial writes internally in `writeAll`. The
two surfaces are independent — do not mix a descriptor from `std.io.fileOpen`
with `std_file.close`, or a `File` with `std.io.fileClose`.

**Console output is unbuffered.** Every `std.io` console writer lowers to the
`@stdoutWrite`/`@putChar` builtins, which write straight to the process's
standard output (file descriptor 1, or `WriteConsoleA` on win32) with no
buffering. `std.debug.log`/`logInt` use the same path. **Gotcha:** if a program
also writes to standard output through a *buffered* C stream (`printf`,
`fwrite`), the two streams can reorder, because the C stream holds bytes until
it flushes; flush the C stream before relying on the order. `std.io` itself
never buffers, and there is no buffered `std.io` writer to flush.

**stdin reads one byte at a time.** `std_stdin.readLine` deliberately does not
buffer: it reads exactly to the line's terminator so it never consumes the start
of the next line. It strips the terminating `\n` (and the `\r` of `\r\n`),
returns a slice **into the caller's buffer** (no allocation), and returns `null`
at EOF with no partial line. When a line is longer than the buffer, it returns a
full buffer and leaves the rest of the line in the stream; the module carries
just enough state across calls to consume that line's terminator on the next
call, including the exact-multiple case (see `readLine`).

## Quick start

```zig
const std = @import("std");
const std_file = @import("std_file");

var backing: [4096]u8 = undefined;

pub fn main() !void {
    var arena = std.arena.init(backing[0..]);

    var f = try std_file.open(&arena, "note.txt", std_file.Mode.Write);
    _ = try std_file.write(&f, "hello, file\n");
    std_file.close(&f);

    const text = try std_file.readAll(&arena, "note.txt");
    std.io.write(text);

    std.arena.reset(&arena);
}
```

## API

### `std.io`

#### `writeByte`

**Purpose** — writes a single byte to standard output.

**When to use** — for one-character output (a separator, a newline) where a
slice would be awkward. For a run of bytes use `write`.

**Signature** — `pub fn writeByte(c: u8) void`

**Parameters**
- `c` — the byte to write.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.io.writeByte('\n');
```

**Gotchas** — writes the raw byte, not a character encoding; for multi-byte
UTF-8 emit the bytes with `write`.

#### `write`

**Purpose** — writes a byte slice to standard output.

**When to use** — the default way to emit text or data to the console.

**Signature** — `pub fn write(data: []const u8) void`

**Parameters**
- `data` — the bytes to write; no terminator is added.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.io.write("done\n");
```

**Gotchas** — unbuffered direct output (see the module overview). No newline is
appended.

#### `writeStr`

**Purpose** — writes a NUL-terminated C string to standard output.

**When to use** — when the bytes come from a C API as a `[*]const c_char` and
the length is not known.

**Signature** — `pub fn writeStr(s: [*]const c_char) void`

**Parameters**
- `s` — a many-item pointer to a NUL-terminated string; the NUL is not written.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.io.writeStr("literal");
```

**Gotchas** — scans for the NUL, so `s` must be terminated; a missing NUL runs
off the buffer. For a slice that already carries its length, use `write`.

#### `print`

**Purpose** — writes a NUL-terminated string to standard output; it is a
variadic-declared alias of `writeStr`.

**When to use** — for call sites that spell console output as a function call.
For slices prefer `write`.

**Signature** — `pub fn print(s: [*]const c_char, ...) void`

**Parameters**
- `s` — a many-item pointer to a NUL-terminated string.
- `...` — accepted syntactically, but **ignored**: this is not `printf`.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.io.print("x = ");
std.io.printInt(7);
std.io.writeByte('\n');
```

**Gotchas** — **`print` does no formatting.** Extra arguments after `s` are
dropped; only the string itself is written. Use `printInt` for a decimal integer
and `write`/`writeByte` for everything else.

#### `printInt`

**Purpose** — writes a signed decimal integer to standard output.

**When to use** — to emit a number without hand-rolling digit conversion.

**Signature** — `pub fn printInt(n: i32) void`

**Parameters**
- `n` — the value to write, including `i32` minimum.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.io.printInt(-1234);
std.io.writeByte('\n');
```

**Gotchas** — writes digits only: no leading space, no trailing newline, and no
padding. The digits are formatted into a fixed 12-byte stack buffer, so the call
never allocates.

#### `readByte`

**Purpose** — reads one byte from standard input.

**When to use** — for a single-byte prompt/response. For lines use
`std_stdin.readLine`.

**Signature** — `pub fn readByte() u8`

**Parameters** — none.

**Returns** — the next input byte as a `u8`.

**Errors** — none exposed; there is no EOF or error channel, so the return is a
raw byte.

**Example**
```zig
const c = std.io.readByte();
_ = c;
```

**Gotchas** — blocking; on EOF the behavior is whatever the `@getChar` builtin
returns (there is no sentinel to test). Use `std_stdin.readLine` when you need
EOF detection.

#### `sleepMs`

**Purpose** — suspends the calling thread for a number of milliseconds.

**When to use** — to pace console output or wait out a short delay. This is the
same builtin-backed sleep as `std.time.sleepMs`.

**Signature** — `pub fn sleepMs(ms: u32) void`

**Parameters**
- `ms` — milliseconds to sleep.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.io.sleepMs(100);
```

**Gotchas** — a minimum wait, not a guarantee. In the Model C async model it
blocks the whole program.

#### `fileOpen`

**Purpose** — opens a file and returns a raw descriptor, or `null`.

**When to use** — for the low-level descriptor surface. For owned handles,
error reporting, seek/size, and whole-file helpers, use
[`std_file`](#std_file) instead.

**Signature** — `pub fn fileOpen(path: []const u8, write_mode: bool) ?usize`

**Parameters**
- `path` — the file path, copied into a 512-byte stack buffer and
  NUL-terminated. Paths of 511 bytes or more are rejected.
- `write_mode` — `true` opens for write, creating/truncating; `false` opens
  read-only.

**Returns** — `?usize`: the descriptor on success, `null` if the path is too
long or the open failed.

**Errors** — none; failure is the `null` optional.

**Example**
```zig
const fd = std.io.fileOpen("out.bin", true) orelse return;
std.io.fileWrite(fd, "data");
std.io.fileClose(fd);
```

**Gotchas** — the descriptor is a raw OS handle; close it with
`std.io.fileClose`, not `std_file.close`. The 512-byte path cap is much smaller
than `std_file`'s 4096.

#### `fileWrite`

**Purpose** — writes a byte slice to a descriptor opened with `fileOpen`.

**When to use** — only with the `std.io` descriptor surface.

**Signature** — `pub fn fileWrite(fd: usize, data: []const u8) void`

**Parameters**
- `fd` — a descriptor from `fileOpen`.
- `data` — the bytes to write.

**Returns** — nothing.

**Errors** — none exposed; a write failure is silently ignored.

**Example**
```zig
std.io.fileWrite(fd, "line\n");
```

**Gotchas** — no error channel and no byte count; if the write fails there is no
signal. Prefer `std_file.writeAll` when correctness matters.

#### `fileRead`

**Purpose** — reads up to `buf.len` bytes from a descriptor.

**When to use** — only with the `std.io` descriptor surface.

**Signature** — `pub fn fileRead(fd: usize, buf: []u8) usize`

**Parameters**
- `fd` — a descriptor from `fileOpen`.
- `buf` — the destination slice; at most `buf.len` bytes are read.

**Returns** — the number of bytes read. `0` means EOF **or** an error — v1 has
no separate read-error channel.

**Errors** — none; an error is reported as `0`, the same as EOF.

**Example**
```zig
var buf: [64]u8 = undefined;
const n = std.io.fileRead(fd, buf[0..]);
if (n > 0) std.io.write(buf[0..n]);
```

**Gotchas** — `0` is ambiguous between EOF and failure. On POSIX the underlying
PAL loops until the buffer is full or EOF; on win32 it is a single `ReadFile`,
so a short read is possible.

#### `fileClose`

**Purpose** — closes a descriptor opened with `fileOpen`.

**When to use** — when finished with a `std.io` descriptor.

**Signature** — `pub fn fileClose(fd: usize) void`

**Parameters**
- `fd` — the descriptor to close.

**Returns** — nothing.

**Errors** — none exposed; a close failure is ignored.

**Example**
```zig
std.io.fileClose(fd);
```

**Gotchas** — does not match `std_file.close`; do not cross the two surfaces.

### `std_file`

#### `FileError`

**Purpose** — the module's single error set, covering every file operation.

**When to use** — when naming or matching a `std_file` failure.

**Signature** — `pub const FileError = error{ OpenFailed, ReadFailed, WriteFailed, SeekFailed, SizeFailed, FlushFailed, RemoveFailed, RenameFailed, OutOfMemory };`

**Parameters** — none.

**Returns** — an error set, not a value.

**Errors**
- `error.OpenFailed` — `open` could not open/create the path (including a path
  that does not fit the 4096-byte buffer).
- `error.ReadFailed` — the OS read failed.
- `error.WriteFailed` — the OS write failed, or a `writeAll` loop made no
  progress.
- `error.SeekFailed` — the OS seek failed, or the POSIX offset did not fit the
  32-bit `off_t`.
- `error.SizeFailed` — the OS size query failed.
- `error.FlushFailed` — `fsync`/`FlushFileBuffers` failed.
- `error.RemoveFailed` — `unlink`/`DeleteFileA` failed (or the path was too
  long).
- `error.RenameFailed` — `rename`/`MoveFileA` failed (or a path was too long).
- `error.OutOfMemory` — `readAll` could not allocate from its arena (R1).

**Example**
```zig
var f = std_file.open(&arena, "x.bin", std_file.Mode.Read) catch |e| {
    if (e == error.OpenFailed) return;
    return;
};
_ = &f;
```

**Gotchas** — `close`, `exists`, and the `fileOpen`-style path checks do not
return errors; `close` ignores its OS result entirely.

#### `Mode`

**Purpose** — selects how `open` treats an existing file.

**When to use** — the second argument to `std_file.open`.

**Signature** — `pub const Mode = enum { Read, Write, Append, ReadWrite };`

**Parameters** (members)
- `Read` — open an existing file read-only.
- `Write` — create or truncate, write-only.
- `Append` — create if needed, write-only, positioned at end.
- `ReadWrite` — create if needed, read/write.

**Returns** — an enum value.

**Errors** — none.

**Example**
```zig
var f = try std_file.open(&arena, "log.txt", std_file.Mode.Append);
```

**Gotchas** — `Write` truncates; use `Append` to add. On win32 `Append` opens
with `OPEN_ALWAYS` and then seeks to end; on POSIX it uses `O_APPEND`.

#### `SeekWhence`

**Purpose** — selects the base for a `seek` offset.

**When to use** — the third argument to `std_file.seek`.

**Signature** — `pub const SeekWhence = enum { Set, Cur, End };`

**Parameters** (members)
- `Set` — offset from the start of the file.
- `Cur` — offset from the current position.
- `End` — offset from the end of the file.

**Returns** — an enum value.

**Errors** — none.

**Example**
```zig
const pos = try std_file.seek(&f, 0, std_file.SeekWhence.End);
```

**Gotchas** — the enum maps to the OS `SEEK_SET`/`SEEK_CUR`/`SEEK_END` values.

#### `File`

**Purpose** — an owned OS file handle plus its owning arena and last size
query.

**When to use** — as the value returned by `open` and passed to
`read`/`write`/`seek`/`size`/`flush`/`close`.

**Signature** — `pub const File = struct { handle: *void, size_cache: i64, arena: *std.arena.Arena };`

**Parameters** (fields)
- `handle` — the OS handle: a win32 `HANDLE` or a POSIX descriptor, stored as
  `*void`.
- `size_cache` — the most recent `size` result; `-1` until `size` is called.
- `arena` — the arena passed to `open` (used only by `readAll`).

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
var f = try std_file.open(&arena, "data.bin", std_file.Mode.Read);
_ = try std_file.size(&f);
std_file.close(&f);
```

**Gotchas** — `open` does not allocate; only `readAll` touches `arena`. Treat
`handle` as opaque and never construct a `File` by hand. A `File` is not
refcounted: `close` closes the handle but does not free the arena.

#### `open`

**Purpose** — opens or creates a file and returns an owned `File`.

**When to use** — the entry point for the `std_file` surface.

**Signature** — `pub fn open(arena: *std.arena.Arena, path: []const u8, mode: Mode) FileError!File`

**Parameters**
- `arena` — stored in the `File`; used by `readAll`, not by `open` itself.
- `path` — the path, copied into a 4096-byte stack buffer and NUL-terminated.
- `mode` — how to open (`Read`/`Write`/`Append`/`ReadWrite`).

**Returns** — a `File` whose `size_cache` is `-1`.

**Errors** — `error.OpenFailed` when the path does not fit the buffer or the OS
open/create fails.

**Example**
```zig
var f = try std_file.open(&arena, "out.txt", std_file.Mode.Write);
std_file.close(&f);
```

**Gotchas** — the path is copied to a stack buffer per call; there is no
allocation and no error other than `OpenFailed`. Paths of 4096 bytes or more are
`OpenFailed`.

#### `close`

**Purpose** — closes the file's OS handle.

**When to use** — when finished with a `File`.

**Signature** — `pub fn close(f: *File) void`

**Parameters**
- `f` — the file to close.

**Returns** — nothing.

**Errors** — none exposed; the OS close result is ignored.

**Example**
```zig
std_file.close(&f);
```

**Gotchas** — does not flush and does not free arena memory; call `flush` first
if durability matters. Using a `File` after `close` is a use-after-close.

#### `read`

**Purpose** — reads up to `buf.len` bytes from the file.

**When to use** — for chunked reads. For a whole small file use `readAll`.

**Signature** — `pub fn read(f: *File, buf: []u8) FileError!usize`

**Parameters**
- `f` — an open file.
- `buf` — the destination; at most `buf.len` bytes are read.

**Returns** — the number of bytes read; `0` at EOF. `buf.len == 0` returns `0`.

**Errors** — `error.ReadFailed` when the OS read fails.

**Example**
```zig
var buf: [128]u8 = undefined;
const n = try std_file.read(&f, buf[0..]);
```

**Gotchas** — a single `read` may return fewer bytes than requested; loop until
`0` for a complete read. The file position advances by the returned count.

#### `write`

**Purpose** — writes up to `buf.len` bytes to the file.

**When to use** — for chunked writes. For a whole buffer with retry use
`writeAll`.

**Signature** — `pub fn write(f: *File, buf: []const u8) FileError!usize`

**Parameters**
- `f` — an open file.
- `buf` — the bytes to write.

**Returns** — the number of bytes written; may be less than `buf.len`.
`buf.len == 0` returns `0`.

**Errors** — `error.WriteFailed` when the OS write fails.

**Example**
```zig
const n = try std_file.write(&f, "chunk");
_ = n;
```

**Gotchas** — the OS may write fewer bytes than requested (notably win32
`WriteFile`); callers that need the whole buffer must loop, as `writeAll` does.

#### `seek`

**Purpose** — repositions the file's read/write offset and returns the new
absolute offset.

**When to use** — random access within an open file.

**Signature** — `pub fn seek(f: *File, offset: i64, whence: SeekWhence) FileError!i64`

**Parameters**
- `f` — an open file.
- `offset` — the signed offset relative to `whence`.
- `whence` — `Set`, `Cur`, or `End`.

**Returns** — the resulting absolute offset as an `i64`.

**Errors** — `error.SeekFailed` when the OS seek fails, or (POSIX) when
`offset` is outside the 32-bit `off_t` range.

**Example**
```zig
_ = try std_file.seek(&f, 0, std_file.SeekWhence.Set);
```

**Gotchas** — on the pinned i386 target `off_t` is 32-bit, so offsets beyond
`[-2147483648, 2147483647]` are rejected rather than truncated.

#### `size`

**Purpose** — returns the file's size in bytes and caches it.

**When to use** — before allocating a buffer for a whole-file read.

**Signature** — `pub fn size(f: *File) FileError!i64`

**Parameters**
- `f` — an open file.

**Returns** — the file size in bytes; also stored in `f.size_cache`.

**Errors** — `error.SizeFailed` when the OS size query fails.

**Example**
```zig
const n = try std_file.size(&f);
_ = n;
```

**Gotchas** — on POSIX the size is derived with seeks (current, end, restore); a
failed seek yields `SizeFailed` and may leave the position where it stopped.

#### `flush`

**Purpose** — flushes buffered file data to the OS (`fsync`/`FlushFileBuffers`).

**When to use** — before `close` when the data must reach stable storage.

**Signature** — `pub fn flush(f: *File) FileError!void`

**Parameters**
- `f` — an open file.

**Returns** — nothing.

**Errors** — `error.FlushFailed` when the OS flush fails.

**Example**
```zig
try std_file.flush(&f);
```

**Gotchas** — `close` does not flush; `writeAll` flushes internally before it
closes.

#### `exists`

**Purpose** — reports whether a path exists.

**When to use** — a cheap pre-check before `open`.

**Signature** — `pub fn exists(path: []const u8) bool`

**Parameters**
- `path` — the path to test.

**Returns** — `true` if the path exists, `false` otherwise (including a path too
long for the buffer).

**Errors** — none; a missing path is `false`, not an error.

**Example**
```zig
if (std_file.exists("config.txt")) {
    std.io.write("found\n");
}
```

**Gotchas** — a `true` result can go stale before `open`; treat it as a hint,
not a guarantee.

#### `remove`

**Purpose** — deletes a file by path.

**When to use** — cleanup after a temporary file.

**Signature** — `pub fn remove(path: []const u8) FileError!void`

**Parameters**
- `path` — the file to delete.

**Returns** — nothing.

**Errors** — `error.RemoveFailed` when `unlink`/`DeleteFileA` fails or the path
does not fit the buffer.

**Example**
```zig
try std_file.remove("tmp.bin");
```

**Gotchas** — removes files only (not directories); a missing file is an error.

#### `rename`

**Purpose** — renames or moves a file.

**When to use** — atomic replacement of a file's name.

**Signature** — `pub fn rename(old_path: []const u8, new_path: []const u8) FileError!void`

**Parameters**
- `old_path` — the existing path.
- `new_path` — the new path.

**Returns** — nothing.

**Errors** — `error.RenameFailed` when `rename`/`MoveFileA` fails or either path
does not fit its buffer.

**Example**
```zig
try std_file.rename("tmp.bin", "final.bin");
```

**Gotchas** — both paths are copied into separate 4096-byte buffers; a path too
long is `RenameFailed`.

#### `readAll`

**Purpose** — reads an entire file into one arena allocation.

**When to use** — for small/medium whole-file reads where the arena's bulk-free
model fits (R1).

**Signature** — `pub fn readAll(arena: *std.arena.Arena, path: []const u8) FileError![]u8`

**Parameters**
- `arena` — the allocation source.
- `path` — the file to read (opened `Read`).

**Returns** — a `[]u8` of the bytes read. It is `raw[0..got]`, so if the file
shrank between `size` and the reads it may be shorter than the reported size.

**Errors** — `error.OpenFailed`, `error.SizeFailed`, `error.ReadFailed`, and
`error.OutOfMemory`.

**Example**
```zig
const text = try std_file.readAll(&arena, "config.txt");
std.io.write(text);
std.arena.reset(&arena);
```

**Gotchas** — allocates `size` bytes up front; the slice is valid only until the
next arena `reset`. On a read failure after that allocation the file is closed and
the arena is left with the size buffer consumed; `SizeFailed` allocates nothing
and `OutOfMemory` fails before any consumption.

#### `writeAll`

**Purpose** — writes an entire buffer to a path, retrying partial writes.

**When to use** — the safe whole-buffer write: it loops on `write`, flushes, and
closes.

**Signature** — `pub fn writeAll(path: []const u8, data: []const u8) FileError!void`

**Parameters**
- `path` — the output path; opened `Write`, so it is created/truncated.
- `data` — the bytes to write in full.

**Returns** — nothing.

**Errors** — `error.OpenFailed`, `error.WriteFailed` (including a zero-progress
write), and `error.FlushFailed`.

**Example**
```zig
try std_file.writeAll("out.bin", "all bytes");
```

**Gotchas** — truncates the destination. It flushes before closing, unlike a
bare `write` + `close`.

### `std_stdin`

#### `StdinError`

**Purpose** — the module's error set.

**When to use** — when naming or matching a `std_stdin` failure.

**Signature** — `pub const StdinError = error{OutOfMemory, Io};`

**Parameters** — none.

**Returns** — an error set, not a value.

**Errors**
- `error.OutOfMemory` — `readAll` could not grow its arena buffer (R1).
- `error.Io` — a read from standard input failed.

**Example**
```zig
const std_stdin = @import("std_stdin");

const line = std_stdin.readLine(buf[0..]) catch |e| {
    if (e == error.Io) return;
    return null;
};
_ = line;
```

**Gotchas** — `readLine` can return only `Io` (it never allocates);
`OutOfMemory` comes only from `readAll`.

#### `readLine`

**Purpose** — reads one line from standard input into the caller's buffer,
without consuming past the line.

**When to use** — line-oriented input (a REPL, a filter, a prompt loop).

**Signature** — `pub fn readLine(buf: []u8) StdinError!?[]u8`

**Parameters**
- `buf` — the destination. **`buf.len` must be greater than `0`** (a
  zero-length buffer traps).

**Returns** — `?[]u8`: a slice **into `buf`** with the terminator stripped, or
`null` at EOF with no partial line. When the line is longer than `buf`, a full
buffer is returned and the remainder stays in the stream for the next call.

**Errors** — `error.Io` when a read from stdin fails.

**Example**
```zig
const std_stdin = @import("std_stdin");

var buf: [256]u8 = undefined;
while (try std_stdin.readLine(buf[0..])) |line| {
    std.io.write(line);
    std.io.writeByte('\n');
}
```

**Gotchas**
- Reads one byte at a time (no internal buffer) and returns a view into `buf`;
  the next `readLine` overwrites it.
- Strips a trailing `\n` and the `\r` of a `\r\n`; a lone `\r` at EOF is
  exposed as its own one-byte line.
- **Overflow / exact-multiple contract:** a full buffer means the line
  continues. The module carries state so the *next* call consumes that line's
  terminator first; a line whose length is an exact multiple of `buf.len`
  therefore does not surface a spurious empty line. A `\r` landing exactly at
  the buffer boundary is carried so a following `\n` closes the same line.
- A 1-byte buffer keeps the plain boundary behavior (the CR carry needs room for
  two bytes).
- The carry state is module-global, so interleaving readers on the same process
  share it.

#### `readAll`

**Purpose** — reads all of standard input into one arena allocation, growing by
doubling.

**When to use** — to slurp a pipe or redirected file of unknown length.

**Signature** — `pub fn readAll(arena: *std.arena.Arena) StdinError![]u8`

**Parameters**
- `arena` — the allocation source; the buffer starts at 4096 bytes and doubles.

**Returns** — a `[]u8` of everything read, as a prefix of the final arena
buffer.

**Errors** — `error.OutOfMemory` when the arena cannot grow the buffer, and
`error.Io` when a read fails.

**Example**
```zig
const std_stdin = @import("std_stdin");

const all = try std_stdin.readAll(&arena);
std.io.write(all);
std.arena.reset(&arena);
```

**Gotchas** — an input of exactly 4096 bytes is detected as EOF before the grow
step, so it does not allocate a second buffer. Earlier buffers are never freed
(the arena reclaims only by `reset`), so total arena usage is the sum of all the
doublings — about twice the final capacity.

## See also

- `std.io`, `std_file`, `std_stdin` — the modules in this doc.
- [`os_time.md`](os_time.md) — `std.debug.log` shares the same unbuffered
  `@stdoutWrite` path as `std.io.write`.
- [`memory.md`](memory.md) — `readAll` allocates through the `std.arena` model
  documented there.
- [`text.md`](text.md) — `std.buf.Buf` is the growable buffer alternative to
  `std_stdin.readAll`.
- [`net.md`](net.md) — socket I/O and the non-blocking primitives that pair with
  file/stdin input.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
