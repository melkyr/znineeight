# Z98 Standard Library Reference

A reference for the Z98 standard library shipped with `zig1`. Every entry below is
transcribed from the module sources in `sf/src/std_*.zig`; the sources are the
source of truth. Z98 is a Zig subset, so the API surface is deliberately concrete:
no generics, no traits, slices (`[]u8` / `[]const u8`), optionals (`?T`),
error unions (`!T`), `try` / `catch`, and `?T` unwrapping (`if (x) |v| { ... }`).

Two tiers exist:

- **Core re-exported** through `const std = @import("std");` — `std.io`,
  `std.arena`, `std.str`, `std.mem`, `std.math`, `std.debug`, `std.net`,
  `std.async`, `std.bits`, `std.os`, `std.time`, `std.buf` (the 12 names
  re-exported by `sf/src/std.zig`).
- **Higher layers imported by path** — `@import("std_file.zig")`,
  `@import("std_crypto.zig")`, etc. The extension-less form
  (`@import("std_file")`) also resolves; the `.zig` form is the canonical style
  used by the `stdlib_test/` usage programs.

Two library-wide rules apply to every module:

- **R1 — Arena rule.** Every allocating function takes `arena: *std.arena.Arena`
  as its first parameter and returns `OutOfMemory` (or a module error set that
  contains it) on exhaustion. Functions never own memory across calls.
- **R2 — One error set per module.** Each module declares a single error set;
  cross-module translation happens at the call site.

---

## Module index

### Core (re-exported via `@import("std")`)

| Module | Layer | Access | Source |
|---|---|---|---|
| `io` | core (builtin-backed) | `std.io` | `sf/src/std_io.zig` |
| `arena` | L0 | `std.arena` | `sf/src/std_arena.zig` |
| `str` | L2 | `std.str` | `sf/src/std_str.zig` |
| `mem` | L0 | `std.mem` | `sf/src/std_mem.zig` |
| `math` | L0 | `std.math` | `sf/src/std_math.zig` |
| `debug` | L1 | `std.debug` | `sf/src/std_debug.zig` |
| `net` | L3 | `std.net` | `sf/src/std_net.zig` |
| `async` | async runtime | `std.async` | `sf/src/std_async.zig` |
| `bits` | L0 | `std.bits` | `sf/src/std_bits.zig` |
| `os` | L1 | `std.os` | `sf/src/std_os.zig` |
| `time` | L1 | `std.time` | `sf/src/std_time.zig` |
| `buf` | L2 | `std.buf` | `sf/src/std_buf.zig` |

### Higher layers (imported by path)

| Module | Layer | Import | Source |
|---|---|---|---|
| `std_file` | L3 | `@import("std_file.zig")` | `sf/src/std_file.zig` |
| `std_stdin` | L3 | `@import("std_stdin.zig")` | `sf/src/std_stdin.zig` |
| `std_stream` | L6 | `@import("std_stream.zig")` | `sf/src/std_stream.zig` |
| `std_crypto` | L5 | `@import("std_crypto.zig")` | `sf/src/std_crypto.zig` |
| `std_parse` | L5 | `@import("std_parse.zig")` | `sf/src/std_parse.zig` |
| `std_map` | L4 | `@import("std_map.zig")` | `sf/src/std_map.zig` |
| `std_sort` | L4 | `@import("std_sort.zig")` | `sf/src/std_sort.zig` |
| `std_heap` | L4 | `@import("std_heap.zig")` | `sf/src/std_heap.zig` |
| `std_rle` | L4 | `@import("std_rle.zig")` | `sf/src/std_rle.zig` |
| `std_base64` | L5 | `@import("std_base64.zig")` | `sf/src/std_base64.zig` |
| `std_hex` | L5 | `@import("std_hex.zig")` | `sf/src/std_hex.zig` |
| `std_utf8` | L5 | `@import("std_utf8.zig")` | `sf/src/std_utf8.zig` |

`std_net` and `std_async` are also importable by path
(`@import("std_net.zig")`, `@import("std_async.zig")`).

### Private PAL units (do not import directly)

| Module | Owner | Source |
|---|---|---|
| `std_os_pal` | `std_os` | `sf/src/std_os_pal.zig` |
| `std_time_pal` | `std_time` | `sf/src/std_time_pal.zig` |
| `std_file_pal` | `std_file` | `sf/src/std_file_pal.zig` |
| `std_stdin_pal` | `std_stdin` | `sf/src/std_stdin_pal.zig` |

These hold target-selected `extern "c"` / `extern "stdcall"` OS bindings. They are
implementation details of their owning module and are not part of the public API.

---

## Core modules

### `std.io` — console and simple file I/O

- **Layer / import:** core (builtin-backed); `const std = @import("std"); std.io.*`
- **Purpose:** byte-oriented stdout/stdin and a small handle-based file surface
  backed by the compiler PAL (`pal_file_*` in `zig_pal.c`).

**Public functions**

```zig
pub fn writeByte(c: u8) void;
pub fn write(data: []const u8) void;
pub fn writeStr(s: [*]const c_char) void;          // NUL-terminated
pub fn print(s: [*]const c_char, ...) void;        // writes s only (args ignored)
pub fn printInt(n: i32) void;                      // signed decimal, no newline
pub fn readByte() u8;
pub fn sleepMs(ms: u32) void;

pub fn fileOpen(path: []const u8, write_mode: bool) ?usize; // null on failure
pub fn fileWrite(fd: usize, data: []const u8) void;
pub fn fileRead(fd: usize, buf: []u8) usize;       // 0 at EOF (or on error)
pub fn fileClose(fd: usize) void;
```

- **Errors:** none (the optional from `fileOpen` is the error channel).
- **Arena:** no allocating functions.

**Usage**

```zig
const std = @import("std");

std.io.write("hello\n");
std.io.printInt(42);
std.io.writeByte('\n');
```

### `std.arena` — bump allocator

- **Layer / import:** L0; `std.arena.*`
- **Purpose:** the single arena used by every allocating function in the library.

**Public types / functions**

```zig
pub const Arena = struct {
    data: [*]u8,
    capacity: usize,
    used: usize,
};

pub const ArenaError = error{OutOfMemory};

pub fn init(data: []u8) Arena;
pub fn alloc(self: *Arena, size: usize) ArenaError![*]u8;
pub fn reset(self: *Arena) void;
```

- **Arena rule:** this module *is* the arena. `alloc` returns raw bytes;
  `reset` reclaims everything (there is no free).

**Usage**

```zig
const std = @import("std");

var backing: [4096]u8 = undefined;
var arena = std.arena.init(backing[0..]);
var p = arena.alloc(16) catch @panic("oom");
arena.reset();
```

### `std.str` — string slice operations

- **Layer / import:** L2; `std.str.*`
- **Purpose:** byte-string helpers over slices; no NUL termination.

**Public functions**

```zig
pub fn len(s: []const u8) usize;
pub fn eql(a: []const u8, b: []const u8) bool;
pub fn copy(dst: []u8, src: []const u8) void;
pub fn copyZ(dst: [*]u8, src: []const u8) usize;   // NUL-terminates; returns src.len
pub fn findChar(s: []const u8, c: u8) ?usize;
pub fn startsWith(s: []const u8, prefix: []const u8) bool;
pub fn endsWith(s: []const u8, suffix: []const u8) bool;
pub fn toUpper(s: []u8) void;                      // in place
pub fn toLower(s: []u8) void;                      // in place

pub fn split(arena: *std.arena.Arena, s: []const u8, sep: u8) ![][]const u8;
pub fn splitLines(arena: *std.arena.Arena, s: []const u8) ![][]const u8;
pub fn join(arena: *std.arena.Arena, parts: [][]const u8, sep: []const u8) ![]u8;
pub fn trim(s: []const u8) []const u8;
pub fn trimLeft(s: []const u8, chars: []const u8) []const u8;
pub fn trimRight(s: []const u8, chars: []const u8) []const u8;
pub fn indexOf(s: []const u8, needle: []const u8) ?usize;
pub fn lastIndexOf(s: []const u8, needle: []const u8) ?usize;
pub fn eqIgnoreCase(a: []const u8, b: []const u8) bool;
pub fn replace(arena: *std.arena.Arena, s: []const u8, from: []const u8, to: []const u8) ![]u8;
pub fn count(s: []const u8, needle: u8) usize;
pub fn repeat(arena: *std.arena.Arena, s: []const u8, n: usize) ![]u8;
```

- **Errors:** allocating functions return only `error.OutOfMemory`.
- **Notes:** `split`/`splitLines` return slices into `s` (only the outer array is
  allocated). `replace` reads `s` without mutating it, so `from`/`to` may alias
  `s`.

**Usage**

```zig
const std = @import("std");

var backing: [4096]u8 = undefined;
var arena = std.arena.init(backing[0..]);
var parts = std.str.split(&arena, "a,b,c", ',') catch @panic("split");
var joined = std.str.join(&arena, parts, ":") catch @panic("join");
std.io.write(std.str.trim("  hi  "));
```

### `std.mem` — raw memory operations

- **Layer / import:** L0; `std.mem.*`
- **Purpose:** pointer/length bulk copy, zero, and equality.

**Public functions**

```zig
pub fn copyU8(dst: [*]u8, src: [*]const u8, n: usize) void;
pub fn copyU32(dst: [*]u32, src: [*]const u32, n: usize) void;
pub fn copyU64(dst: [*]u64, src: [*]const u64, n: usize) void;
pub fn zeroU8(dst: [*]u8, n: usize) void;
pub fn eqlU8(a: [*]const u8, b: [*]const u8, n: usize) bool;
```

- **Errors / arena:** none; no allocation.

### `std.math` — integer helpers

- **Layer / import:** L0; `std.math.*`
- **Purpose:** scalar `i32`/`u32` min/max/clamp/alignment.

**Public functions**

```zig
pub fn min(a: i32, b: i32) i32;
pub fn max(a: i32, b: i32) i32;
pub fn minU(a: u32, b: u32) u32;
pub fn maxU(a: u32, b: u32) u32;
pub fn abs(n: i32) i32;
pub fn clamp(v: i32, lo: i32, hi: i32) i32;
pub fn clampU(v: u32, lo: u32, hi: u32) u32;
pub fn isPowerOfTwoU32(n: u32) bool;
pub fn alignUp(n: u32, alignment: u32) u32;
pub fn alignDown(n: u32, alignment: u32) u32;
```

- **Errors / arena:** none; no allocation.

### `std.bits` — bit manipulation

- **Layer / import:** L0; `std.bits.*`
- **Purpose:** pure bit operations on `u32`/`u64` (Z98 has no bit builtins beyond
  `@bitCast`, so these are hand-written).

**Public functions**

```zig
pub fn popcount32(x: u32) u32;
pub fn popcount64(x: u64) u32;
pub fn clz32(x: u32) u32;          // clz32(0) == 32
pub fn clz64(x: u64) u32;          // clz64(0) == 64
pub fn ctz32(x: u32) u32;          // ctz32(0) == 32
pub fn ctz64(x: u64) u32;          // ctz64(0) == 64
pub fn rotl32(x: u32, n: u32) u32; // n wraps mod 32
pub fn rotr32(x: u32, n: u32) u32;
pub fn bitrev32(x: u32) u32;
pub fn mask(bits: u32) u32;        // low `bits` set; bits in [0,32]
pub fn extract(x: u32, off: u32, len: u32) u32;
pub fn insert(x: u32, val: u32, off: u32, len: u32) u32;
pub fn isPow2(x: u32) bool;
pub fn nextPow2(x: u32) u32;       // nextPow2(0) == 1; 0 if unrepresentable
```

- **Errors / arena:** none; no allocation.
- **Traps:** `extract`/`insert` trap via `unreachable` when
  `off >= 32`, `len > 32`, or `off + len > 32`.

**Usage**

```zig
const std = @import("std");

var hdr: u32 = 0;
hdr = std.bits.insert(hdr, @intCast(u32, 0xA), 0, 4);
var a = std.bits.extract(hdr, 0, 4);          // 10
var n = std.bits.popcount32(hdr);
```

### `std.os` — process information

- **Layer / import:** L1; `std.os.*`
- **Purpose:** argc/argv capture, environment lookup, working directory, exit.

**Public types**

```zig
pub const OsError = error{ OutOfMemory, CwdFailed };
```

**Public functions**

```zig
pub fn initArgs(arg_count: i32, arg_values: [*]*const u8) void;
pub fn argc() usize;
pub fn argv(i: usize) []const u8;               // slice aliases the caller's pointer
pub fn exit(code: i32) noreturn;
pub fn env(name: []const u8) ?[]const u8;       // null when unset
pub fn cwd(arena: *std.arena.Arena) OsError![]u8;
```

- **Arena:** only `cwd` allocates (R1).
- **Notes:** call `initArgs(argc, argv)` from `main` before `argc()`/`argv(i)`.
  Names `>= 256` bytes are rejected as unset by `env`.

**Usage**

```zig
const std = @import("std");

pub fn main(argc: i32, argv: [*]*const u8) void {
    std.os.initArgs(argc, argv);
    var n = std.os.argc();
    var a0 = std.os.argv(0);
    var dir = std.os.cwd(&arena) catch @panic("cwd");
}
```

### `std.time` — clocks and sleep

- **Layer / import:** L1; `std.time.*`
- **Purpose:** monotonic counter, millisecond tick counter, wall clock, sleep.

**Public functions**

```zig
pub fn ticksMs() u32;                  // wraps ~49.7 days
pub fn highRes() u64;                  // monotonic counter
pub fn clockMonotonicAvailable() bool; // POSIX CLOCK_MONOTONIC present
pub fn highResFreq() u64;              // counter ticks per second
pub fn wallClockUnix() i64;            // UTC seconds since epoch
pub fn sleepMs(ms: u32) void;
```

- **Errors / arena:** none; no allocation.

**Usage**

```zig
const std = @import("std");

var t0 = std.time.highRes();
std.time.sleepMs(5);
var t1 = std.time.highRes();
var secs = std.time.wallClockUnix();
```

### `std.debug` — logging, assertions, trap handling

- **Layer / import:** L1; `std.debug.*`
- **Purpose:** stdout diagnostics, `assert`/`panic`, and the x86 trap/core-dump
  surface.

**Public types**

```zig
pub const TrapContext = struct {
    eip: u32, esp: u32, ebp: u32, eflags: u32,
    eax: u32, ebx: u32, ecx: u32, edx: u32,
    esi: u32, edi: u32,
};

pub const DebugError = error{CoreDumpWriteFailed};
```

**Public functions**

```zig
pub fn log(msg: []const u8) void;
pub fn logInt(tag: []const u8, n: i32) void;         // "tag: <n>\n"
pub fn assert(cond: bool) void;                      // prints + traps on false
pub fn panic(msg: []const u8) noreturn;              // prints + traps
pub fn setTrapHandler(h: ?fn(*TrapContext) void) void; // null uninstalls
pub fn backtrace(ctx: *const TrapContext, out: *std.buf.Buf) !void;
pub fn defaultTrapHandler(ctx: *TrapContext) noreturn;
pub fn writeCoreDump(ctx: *const TrapContext, path: []const u8) DebugError!void;
```

- **Arena:** `backtrace` appends to a caller-owned `std.buf.Buf` (R1);
  `writeCoreDump` uses stack buffers only.

**Usage**

```zig
const std = @import("std");

std.debug.log("starting\n");
std.debug.assert(1 + 1 == 2);
std.debug.logInt("count", 3);
```

### `std.buf` — growable byte buffer

- **Layer / import:** L2; `std.buf.*`
- **Purpose:** arena-backed growable byte buffer with endian-aware appends.

**Public type**

```zig
pub const Buf = struct {
    arena: *std.arena.Arena,
    data: []u8,
    len: usize,
};
```

**Public functions**

```zig
pub fn init(arena: *std.arena.Arena) Buf;
pub fn initCapacity(arena: *std.arena.Arena, cap: usize) !Buf;
pub fn capacity(b: *Buf) usize;
pub fn slice(b: *Buf) []u8;                 // b.data[0..b.len]
pub fn clear(b: *Buf) void;                 // keeps capacity
pub fn reserve(b: *Buf, extra: usize) !void;
pub fn append(b: *Buf, bytes: []const u8) !void;
pub fn appendByte(b: *Buf, byte: u8) !void;
pub fn appendU16BE(b: *Buf, v: u16) !void;
pub fn appendU16LE(b: *Buf, v: u16) !void;
pub fn appendU32BE(b: *Buf, v: u32) !void;
pub fn appendU32LE(b: *Buf, v: u32) !void;
pub fn appendU64BE(b: *Buf, v: u64) !void;
pub fn appendU64LE(b: *Buf, v: u64) !void;
```

- **Errors:** `error.OutOfMemory` only. Growth doubles capacity; on failure the
  buffer is left untouched. `slice()` stays valid until the next growing append.

**Usage**

```zig
const std = @import("std");

var b = std.buf.init(&arena);
std.buf.appendU32BE(&b, 0x5A393843) catch @panic("oom");
std.buf.append(&b, "payload") catch @panic("oom");
var out = std.buf.slice(&b);
```

### `std.net` — sockets

- **Layer / import:** L3; `std.net.*` or `@import("std_net.zig")`
- **Purpose:** TCP client/server, UDP, `select`, and non-blocking transfer
  primitives. Target-selected OS bindings (wsock32 / libc).

**Public types**

```zig
pub const Socket = i32;
pub const fd_set = struct { data: [128]u32 };

pub const NetError = error {
    WouldBlock, Timeout, ConnRefused, ConnReset,
    NotConnected, AddrInUse, InvalidAddr, Io,
};
```

`IpAddr` is declared `const` (not `pub`), but Z98 does not gate top-level
declarations on `pub`, so callers can name it for out-params:

```zig
const IpAddr = struct { a: u8, b: u8, c: u8, d: u8 };
```

**Public functions**

```zig
pub extern "stdcall" fn htons(x: u16) u16;
pub extern "stdcall" fn htonl(x: u32) u32;
pub fn htonsManual(x: u16) u16;
pub fn htonlManual(x: u32) u32;

pub fn init() i32;                          // WSAStartup on win32; 0 elsewhere
pub fn cleanup() void;
pub fn createTcpServer(port: u16) i32;      // bound listening fd, or -1
pub fn createTcpClient(port: u16) i32;      // connected fd to 127.0.0.1, or -1
pub fn bindListen(fd: i32, backlog: i32) i32;  // 0 on success, -1 on failure
pub fn accept(fd: i32) i32;
pub fn connect(fd: i32, port: u16) i32;     // 0 on success, -1 on failure
pub fn send(fd: i32, buf: [*]const u8, len: i32) i32;
pub fn recv(fd: i32, buf: [*]u8, len: i32) i32;
pub fn close(fd: i32) void;

pub fn udpBind(port: u16) NetError!Socket;
pub fn udpSendTo(s: *Socket, addr: IpAddr, port: u16, data: []const u8) NetError!void;
pub fn udpRecvFrom(s: *Socket, buf: []u8, out_addr: *IpAddr, out_port: *u16) NetError!usize;
pub fn udpSetTimeout(s: *Socket, ms: u32) NetError!void;
pub fn select(nfds: i32, readfds: ?*u8, writefds: ?*u8, exceptfds: ?*u8, timeout_ms: i32) i32;

pub fn setNonBlocking(s: *Socket) NetError!void;
pub fn recvNonBlocking(s: *Socket, buf: []u8) NetError!usize;   // 0 at peer close
pub fn sendNonBlocking(s: *Socket, buf: []const u8) NetError!usize;

pub fn fdZero(s: *u8) void;
pub fn fdSet(fd: i32, s: *u8) void;
pub fn fdIsset(fd: i32, s: *u8) bool;
```

- **Arena:** no allocating functions; `NetError` deliberately excludes
  `OutOfMemory`.
- **Notes:** `createTcpServer` binds but does not listen — call `bindListen`.
  `createTcpClient` connects to `127.0.0.1`.

**Usage**

```zig
const net = @import("std_net.zig");

if (net.init() != 0) @panic("net init");
var server = net.createTcpServer(4154);
_ = net.bindListen(server, 5);
var conn = net.accept(server);
net.close(conn);
net.close(server);
net.cleanup();
```

### `std.async` — cooperative scheduler and frame pool

- **Layer / import:** async runtime; `std.async.*` or `@import("std_async.zig")`
- **Purpose:** concrete cooperative task scheduler plus the per-task child-frame
  pool used by Z98 coroutines. See the [Async / Model C](#async--model-c) section.

**Public types**

```zig
pub const TaskState = enum(u8) {
    ready = 0, running = 1, suspended = 2, done = 3, cancelled = 4,
};

pub const FrameError = error{OutOfFrame};

pub const StepFn = fn(frame: *void, arg: ?*void) ?*void; // ABI alias, docs only

pub const HEADER_SIZE: usize = 16;

pub const Context = struct {
    used: usize,
    capacity: usize,
    oom: bool,
};

pub const Task = struct {
    frame: *void,
    ctx: *Context,
    state: TaskState,
    cancel_requested: bool,
    result: *void,
    arg: *void,
    waiting_on: *Task,
    has_waiting_on: bool,
};

pub const Scheduler = struct {
    tasks: [*]*Task,
    capacity: usize,
    count: usize,
    current: usize,
    in_task: bool,
};
```

**Public functions**

```zig
pub fn contextInit(buf: []u8) *Context;          // buf must be 8-aligned, len >= 16
pub fn contextAlloc(ctx: *Context, size: usize) FrameError![*]u8;
pub fn contextMark(ctx: *Context) usize;
pub fn contextRelease(ctx: *Context, mark: usize) void;

pub fn schedulerInit(tasks: []*Task) Scheduler;
pub fn addTask(s: *Scheduler, t: *Task) bool;    // idempotent
pub fn removeTask(s: *Scheduler, t: *Task) void;
pub fn tick(s: *Scheduler) FrameError!void;      // resume every ready/suspended task once
pub fn suspend(s: *Scheduler, t: *Task) void;
pub fn suspendUntil(pred: fn() bool) void;       // yields until pred() is true
pub fn waitAll(s: *Scheduler) FrameError!void;
pub fn waitFor(s: *Scheduler, t: *Task) FrameError!void;
pub fn awaitTask(s: *Scheduler, t: *Task) void;  // suspends the current task
pub fn cancel(s: *Scheduler, t: *Task) void;
pub fn cancelAll(s: *Scheduler) void;
```

- **Errors:** `FrameError` = `error{OutOfFrame}` (pool exhaustion).
- **Arena:** caller supplies all storage; `contextInit` places the `Context` at
  the head of the caller buffer.

**Usage** (the pattern from `stdlib_test/file_stream_usage`)

```zig
const sa = @import("std_async.zig");

var storage: [4096]u64 = undefined;                       // 8-aligned pool
var ctx = sa.contextInit(@ptrCast([*]u8, &storage)[0..4096 * 8]);
const frame_sz = @intCast(usize, @asyncFrameSize(co));
var frame_store = arena_mod.alloc(&arena, frame_sz) catch @panic("frame");
var task: sa.Task = undefined;
task.frame = @asyncInit(@ptrCast(*void, ctx), @ptrCast([*]u8, frame_store), co, @ptrCast(*const void, &args));
task.ctx = ctx;
task.arg = @ptrCast(*void, &args);
task.result = @ptrCast(*void, &args);
task.cancel_requested = false;
task.waiting_on = &task;
task.has_waiting_on = false;
var pt: [1]*sa.Task = undefined;
pt[0] = &task;
var s = sa.schedulerInit(pt[0..]);
_ = sa.addTask(&s, &task);
while (task.state != sa.TaskState.done and task.state != sa.TaskState.cancelled) {
    sa.tick(&s) catch @panic("tick");
}
```

---

## L3 modules

### `std_file` — binary-safe file I/O

- **Layer / import:** L3; `@import("std_file.zig")`
- **Purpose:** owns the OS handle; `CreateFileA`/`open`, size, read/write/seek,
  remove/rename, and whole-file helpers.

**Public types**

```zig
pub const FileError = error{
    OpenFailed, ReadFailed, WriteFailed, SeekFailed, SizeFailed,
    FlushFailed, RemoveFailed, RenameFailed, OutOfMemory,
};

pub const Mode = enum { Read, Write, Append, ReadWrite };
pub const SeekWhence = enum { Set, Cur, End };

pub const File = struct {
    handle: *void,
    size_cache: i64,
    arena: *std.arena.Arena,
};
```

**Public functions**

```zig
pub fn open(arena: *std.arena.Arena, path: []const u8, mode: Mode) FileError!File;
pub fn close(f: *File) void;
pub fn read(f: *File, buf: []u8) FileError!usize;     // 0 at EOF
pub fn write(f: *File, buf: []const u8) FileError!usize;
pub fn seek(f: *File, offset: i64, whence: SeekWhence) FileError!i64;
pub fn size(f: *File) FileError!i64;
pub fn flush(f: *File) FileError!void;
pub fn exists(path: []const u8) bool;
pub fn remove(path: []const u8) FileError!void;
pub fn rename(old_path: []const u8, new_path: []const u8) FileError!void;
pub fn readAll(arena: *std.arena.Arena, path: []const u8) FileError![]u8;
pub fn writeAll(path: []const u8, data: []const u8) FileError!void;
```

- **Arena:** only `readAll` allocates (R1).
- **Notes:** on the pinned i386 target `off_t` is 32-bit, so `seek` rejects
  offsets outside the `i32` range rather than truncating.

**Usage**

```zig
const f = @import("std_file.zig");

f.writeAll("out.txt", "one\ntwo\n") catch @panic("write");
var data = f.readAll(&arena, "out.txt") catch @panic("read");
var file = f.open(&arena, "out.txt", f.Mode.Read) catch @panic("open");
var n = f.read(&file, buf[0..]) catch @panic("read");
_ = f.seek(&file, @intCast(i64, 0), f.SeekWhence.Set) catch @panic("seek");
f.close(&file);
```

### `std_stdin` — line-based stdin

- **Layer / import:** L3; `@import("std_stdin.zig")`
- **Purpose:** read one line (CRLF-aware) or all of stdin.

**Public types**

```zig
pub const StdinError = error{ OutOfMemory, Io };
```

**Public functions**

```zig
pub fn readLine(buf: []u8) StdinError!?[]u8;  // slice into buf; null at EOF
pub fn readAll(arena: *std.arena.Arena) StdinError![]u8;
```

- **Arena:** only `readAll` allocates (R1).
- **Notes:** `readLine` strips the terminating `\n` (and the `\r` of `\r\n`).
  `buf.len` must be `> 0` (zero-length traps). An overlong line returns a full
  `buf` prefix; the remainder stays in the stream.

**Usage**

```zig
const stdin = @import("std_stdin.zig");

var buf: [256]u8 = undefined;
while (true) {
    const m = stdin.readLine(buf[0..]) catch @panic("read");
    if (m) |line| {
        std.io.write(line);
    } else break;
}
```

---

## L4 modules

### `std_map` — concrete hash maps

- **Layer / import:** L4; `@import("std_map.zig")`
- **Purpose:** three fixed-capacity open-addressed maps (linear probing,
  tombstone removal). No generics.

**Public types**

```zig
pub const Map32x32  = struct { entries: [*]Entry32x32,  capacity: usize, len: usize }; // u32 -> u32
pub const Map32Ptr  = struct { entries: [*]Entry32Ptr,  capacity: usize, len: usize }; // u32 -> *void
pub const MapStrPtr = struct {
    arena: *std.arena.Arena,
    entries: [*]EntryStrPtr,
    capacity: usize,
    len: usize,
}; // []const u8 -> *void (keys copied into the arena at put)
```

The `Entry*` types are private implementation details.

**Public functions**

```zig
pub fn map32x32Init(arena: *std.arena.Arena, capacity: usize) !Map32x32;
pub fn map32x32Get(m: *Map32x32, key: u32) ?u32;
pub fn map32x32Put(m: *Map32x32, key: u32, val: u32) !void;
pub fn map32x32Remove(m: *Map32x32, key: u32) bool;
pub fn map32x32Len(m: *const Map32x32) usize;

pub fn map32PtrInit(arena: *std.arena.Arena, capacity: usize) !Map32Ptr;
pub fn map32PtrGet(m: *Map32Ptr, key: u32) ?*void;
pub fn map32PtrPut(m: *Map32Ptr, key: u32, val: *void) !void;
pub fn map32PtrRemove(m: *Map32Ptr, key: u32) bool;
pub fn map32PtrLen(m: *const Map32Ptr) usize;

pub fn mapStrPtrInit(arena: *std.arena.Arena, capacity: usize) !MapStrPtr;
pub fn mapStrPtrGet(m: *MapStrPtr, key: []const u8) ?*void;
pub fn mapStrPtrPut(m: *MapStrPtr, key: []const u8, val: *void) !void;
pub fn mapStrPtrRemove(m: *MapStrPtr, key: []const u8) bool;
pub fn mapStrPtrLen(m: *const MapStrPtr) usize;
```

- **Errors:** `error.OutOfMemory` only (table full, or arena exhaustion in
  `MapStrPtr.put`).
- **Notes:** string keys are copied byte-for-byte at put; the maps never free
  (arena reset reclaims). Iteration over the backing table is deterministic
  (slot index ascending).

**Usage**

```zig
const map = @import("std_map.zig");

var m = map.map32x32Init(&arena, 32) catch @panic("init");
map.map32x32Put(&m, 7, 42) catch @panic("put");
var v = map.map32x32Get(&m, 7);            // ?u32
_ = map.map32x32Remove(&m, 7);
var n = map.map32x32Len(&m);
```

### `std_sort` — in-place sort and binary search

- **Layer / import:** L4; `@import("std_sort.zig")`
- **Purpose:** introsort (quicksort + heapsort fallback + insertion sort) and a
  `u32` binary search.

**Public type**

```zig
pub const Sortable = struct {
    lenFn: fn(*void) usize,
    lessFn: fn(*void, usize, usize) bool,
    swapFn: fn(*void, usize, usize) void,
    data: *void,
};
```

**Public functions**

```zig
pub fn sort(s: Sortable) void;
pub fn sortI32(items: []i32) void;
pub fn sortU32(items: []u32) void;
pub fn sortStr(items: [][]const u8) void;          // lexicographic, unsigned bytes
pub fn binarySearchU32(items: []const u32, key: u32) ?usize; // requires sorted input
```

- **Errors / arena:** none; no allocation.
- **Notes:** not stable. `binarySearchU32` returns the index of any matching
  element, or null.

**Usage**

```zig
const sort = @import("std_sort.zig");

sort.sortU32(items[0..]);
var ix = sort.binarySearchU32(items[0..], 9);   // ?usize
```

### `std_heap` — stable binary min-heap

- **Layer / import:** L4; `@import("std_heap.zig")`
- **Purpose:** min-heap over `(i64 key, *void value)` with stable tie-breaking.

**Public types**

```zig
pub const HeapItem = struct { key: i64, value: *void };

pub const Heap = struct {
    arena: *std.arena.Arena,
    items: [*]HeapEntry,
    capacity: usize,
    len: usize,
    seq: u64,
};
```

`HeapEntry` is a private implementation detail.

**Public functions**

```zig
pub fn heapInit(arena: *std.arena.Arena, capacity: usize) !Heap;
pub fn heapPush(h: *Heap, item: HeapItem) !void;   // grows the table when full
pub fn heapPop(h: *Heap) ?HeapItem;                // null when empty
pub fn heapPeek(h: *const Heap) ?HeapItem;
pub fn heapLen(h: *const Heap) usize;
```

- **Errors:** `error.OutOfMemory` only (from `heapInit` / growing `heapPush`).
- **Notes:** ties broken by insertion order (earliest-inserted pops first).

**Usage**

```zig
const heap = @import("std_heap.zig");

var h = heap.heapInit(&arena, 1) catch @panic("init");
heap.heapPush(&h, heap.HeapItem{ .key = 5, .value = @ptrCast(*void, &cell) }) catch @panic("push");
var top = heap.heapPop(&h);   // ?HeapItem
```

### `std_rle` — run-length encoding (QOI-style)

- **Layer / import:** L4; `@import("std_rle.zig")`
- **Purpose:** byte-oriented RLE: a 4-byte little-endian decoded-length prefix
  followed by literal/run tokens.

**Public functions**

```zig
pub fn encodedLen(src: []const u8) usize;   // exact encoded size (prefix + tokens)
pub fn decodedLen(src: []const u8) usize;   // prefix value; 0 when src.len < 4
pub fn encode(arena: *std.arena.Arena, src: []const u8) ![]u8;
pub fn decode(arena: *std.arena.Arena, src: []const u8) ![]u8;
```

- **Errors:** `error.OutOfMemory` only; `encode`/`decode` allocate only the
  output.
- **Notes:** `decode` trusts a well-formed stream (a truncated stream yields a
  zero-filled tail; an overlong run is clamped).

### `std_parse` — number parsing and formatting

- **Layer / import:** L5; `@import("std_parse.zig")`
- **Purpose:** decimal parse/format for `i32`/`u32`/`i64`/`u64` and fixed-point
  `f64`.

**Public functions**

```zig
pub fn parseInt(s: []const u8) ?i32;
pub fn parseUint(s: []const u8) ?u32;
pub fn parseInt64(s: []const u8) ?i64;
pub fn parseUint64(s: []const u8) ?u64;
pub fn parseFloat(s: []const u8) ?f64;

pub fn itoa(buf: []u8, v: i32) []u8;    // result written at buf's end
pub fn utoa(buf: []u8, v: u32) []u8;
pub fn itoa64(buf: []u8, v: i64) []u8;
pub fn utoa64(buf: []u8, v: u64) []u8;
pub fn ftoa(buf: []u8, v: f64, precision: u8) []u8; // precision clamped to 17
```

- **Errors / arena:** none; no allocation (the `?` result is the error channel).
- **Notes:** parsing rejects whitespace, `+`, and underscores; null on overflow or
  malformed input. `ftoa` uses fixed-point notation with round-half-up; non-finite
  input renders as `"nan"`, `"inf"`, or `"-inf"`. `ftoa` returns `buf[0..0]` when
  `buf` is too small (size `>= 328` bytes covers every finite `f64`).

**Usage**

```zig
const parse = @import("std_parse.zig");

var n = parse.parseInt("1234");           // ?i32
var buf: [32]u8 = undefined;
var s = parse.itoa(buf[0..], 1234);       // []u8 slice into buf
```

---

## L5 modules

### `std_crypto` — streaming hashes and CRC-32

- **Layer / import:** L5; `@import("std_crypto.zig")`
- **Purpose:** streaming SHA-1, SHA-256, MD5, and CRC-32. Caller-provided state.

**Public types**

```zig
pub const Sha1 = struct {
    h0: u32, h1: u32, h2: u32, h3: u32, h4: u32,
    buf: [64]u8, buf_len: usize, total: u64,
};

pub const Sha256 = struct {
    h: [8]u32, buf: [64]u8, buf_len: usize, total: u64,
};

pub const Md5 = struct {
    h0: u32, h1: u32, h2: u32, h3: u32,
    buf: [64]u8, buf_len: usize, total: u64,
};
```

**Public functions**

```zig
pub fn sha1Init() Sha1;
pub fn sha1Update(s: *Sha1, data: []const u8) void;
pub fn sha1Final(s: *Sha1, out: *[20]u8) void;

pub fn sha256Init() Sha256;
pub fn sha256Update(s: *Sha256, data: []const u8) void;
pub fn sha256Final(s: *Sha256, out: *[32]u8) void;

pub fn md5Init() Md5;
pub fn md5Update(s: *Md5, data: []const u8) void;
pub fn md5Final(s: *Md5, out: *[16]u8) void;

pub fn crc32Init() u32;                          // 0xFFFFFFFF
pub fn crc32Update(state: u32, data: []const u8) u32;
pub fn crc32Final(state: u32) u32;
```

- **Errors / arena:** none; no allocation.

**Usage**

```zig
const crypto = @import("std_crypto.zig");

var digest: [32]u8 = undefined;
var sha = crypto.sha256Init();
crypto.sha256Update(&sha, msg);
crypto.sha256Final(&sha, &digest);
var crc = crypto.crc32Final(crypto.crc32Update(crypto.crc32Init(), msg));
```

### `std_base64` — RFC 4648 base64

- **Layer / import:** L5; `@import("std_base64.zig")`
- **Purpose:** standard padded base64 encode/decode.

**Public functions**

```zig
pub fn encodedLen(n: usize) usize;   // 4 * ceil(n / 3)
pub fn decodedLen(n: usize) usize;   // (n / 4) * 3 (upper bound)
pub fn encode(arena: *std.arena.Arena, src: []const u8) ![]u8;
pub fn decode(arena: *std.arena.Arena, src: []const u8) ![]u8;
```

- **Errors:** `encode` — `error.OutOfMemory`; `decode` —
  `error{ OutOfMemory, InvalidInput }`.
- **Notes:** `decode` does not skip whitespace; a length not a multiple of 4, a
  byte outside the alphabet, or malformed `=` yields `error.InvalidInput`. Empty
  input is a valid empty result.

### `std_hex` — hexadecimal encode/decode

- **Layer / import:** L5; `@import("std_hex.zig")`
- **Purpose:** two hex chars per byte, high nybble first.

**Public functions**

```zig
pub fn encodeLower(arena: *std.arena.Arena, src: []const u8) ![]u8;  // 0-9 a-f
pub fn encodeUpper(arena: *std.arena.Arena, src: []const u8) ![]u8;  // 0-9 A-F
pub fn decode(arena: *std.arena.Arena, src: []const u8) ![]u8;       // case-insensitive
```

- **Errors:** `encode*` — `error.OutOfMemory`; `decode` —
  `error{ OutOfMemory, InvalidInput }`.
- **Notes:** `decode` requires an even-length string of hex digits and does not
  skip whitespace. Empty input is a valid empty result.

**Usage**

```zig
const hex = @import("std_hex.zig");

var text = hex.encodeLower(&arena, bytes) catch @panic("hex");
var back = hex.decode(&arena, text) catch @panic("unhex");
```

### `std_utf8` — UTF-8 code point iteration

- **Layer / import:** L5; `@import("std_utf8.zig")`
- **Purpose:** validate, decode, encode, and count UTF-8 code points.

**Public type**

```zig
pub const Codepoint = struct { cp: u32, len: u8 };
```

**Public functions**

```zig
pub fn codepointLen(first_byte: u8) u8;  // 1..4, or 0 for an invalid lead byte
pub fn decode(s: []const u8) ?Codepoint; // first code point, or null
pub fn encode(buf: []u8, cp: u32) ?[]u8; // written to buf[0..n], or null
pub fn countCodepoints(s: []const u8) usize;
```

- **Errors / arena:** none; no allocation (optionals are the error channel).
- **Notes:** validation is RFC 3629 (rejects overlong forms, surrogates, and code
  points above U+10FFFF). `encode` refuses a buffer smaller than the encoding.

**Usage**

```zig
const utf8 = @import("std_utf8.zig");

var n = utf8.countCodepoints(msg);
var first = utf8.decode(msg);              // ?Codepoint
if (first) |cp| { var v = cp.cp; }
var buf: [4]u8 = undefined;
var enc = utf8.encode(buf[0..], 233);      // ?[]u8
```

---

## L6 modules

### `std_stream` — coroutine-aware line/frame readers

- **Layer / import:** L6; `@import("std_stream.zig")`
- **Purpose:** composes L3 resources with Model C cooperative-yield line and
  length-prefixed frame readers. See [Async / Model C](#async--model-c).

**Public types**

```zig
pub const StreamError = file_mod.FileError;  // alias of std_file.FileError

pub const FileLineReader = struct {
    src: *file_mod.File,
    buf: []u8,
    pending: []u8,
    pending_cr: bool,
    overflow_cont: bool,
};

pub const SocketLineReader = struct {
    src: *net_mod.Socket,
    buf: []u8,
    pending: []u8,
    pending_cr: bool,
    overflow_cont: bool,
};

pub const MsgReader = struct {
    src: *net_mod.Socket,
    buf: []u8,
    pending: []u8,
};
```

**Public functions**

```zig
pub fn initFileLineReader(src: *std_file.File, buf: []u8) FileLineReader;
pub fn readFileLineSync(lr: *FileLineReader) StreamError!?[]u8;   // blocking
pub fn readFileLineAsync(lr: *FileLineReader) StreamError!?[]u8;  // suspends per incomplete read

pub fn initSocketLineReader(src: *std_net.Socket, buf: []u8) SocketLineReader;
pub fn readSocketLineSync(lr: *SocketLineReader) !?[]u8;   // net error set
pub fn readSocketLineAsync(lr: *SocketLineReader) !?[]u8;  // suspends on WouldBlock

pub fn initMsgReader(src: *std_net.Socket, buf: []u8) MsgReader;
pub fn readMsgSync(mr: *MsgReader) !?[]u8;    // u32 big-endian length prefix
pub fn readMsgAsync(mr: *MsgReader) !?[]u8;   // suspends on WouldBlock
```

- **Errors:** `StreamError` is the module's named error set (the file reader's
  source set). The socket readers' inferred sets are `std_net.NetError`; the
  frame reader additionally raises `error.FrameTooLarge` when the declared frame
  exceeds `buf.len`.
- **Arena:** the reader never allocates; the caller owns `buf`. The returned line
  aliases `buf` and is valid until the next call.
- **Notes:** all readers strip `\n` / `\r\n`, return the final unterminated line,
  and return `null` at EOF. A zero-length frame is a valid empty slice, not
  `null`. The async paths require the socket to be set non-blocking
  (`std.net.setNonBlocking`).

**Usage** (sync)

```zig
const f = @import("std_file.zig");
const st = @import("std_stream.zig");

var file = f.open(&arena, "in.txt", f.Mode.Read) catch @panic("open");
var rbuf: [256]u8 = undefined;
var lr = st.initFileLineReader(&file, rbuf[0..]);
while (true) {
    const m = st.readFileLineSync(&lr) catch @panic("read");
    if (m) |line| { std.io.write(line); } else break;
}
f.close(&file);
```

---

## Async / Model C

Z98 coroutines are **cooperative** and there is **no executor and no poll loop**.
The caller owns the scheduler and drives it explicitly:

- A suspending function compiles to a step machine (`@asyncInit`,
  `@asyncSuspend`, `@asyncResume`, `@asyncFrameSize`).
- The scheduler's `tick` resumes every ready/suspended task once via
  `@asyncResume(t.frame, t.arg)`; a task that yields is re-driven on a later
  tick. `waitAll` / `waitFor` loop `tick` until tasks settle.
- `*Async` readers yield on `error.WouldBlock` (non-blocking sockets) or after
  each incomplete read (file readers). The caller treats a would-block as "yield
  and retry next tick".
- `std.async.suspendUntil(pred: fn() bool) void` is the Model C primitive: it
  yields via `@asyncSuspend(null)` once per tick until `pred()` is true. `pred`
  must be a non-suspending function pointer.
- `std_stream` reaches the async facility through the language-level
  `@asyncSuspend` builtin; it does not import `std.async`. A program that drives
  a `std_stream` coroutine imports `std.async` explicitly to own the scheduler
  and call `tick`.

See `sf/docs/tech_docs/12_async_coroutines.md` for the compiler-side deep dive.

---

## Further reading

- `sf/docs/std_lib_extension.txt` — the std-lib extension blueprint
  (layer table, R1–R7 rules, per-module specs, fixture policy).
- `docs/reference/Language_Spec_Z98.md` — the Z98 language specification
  (syntax, types, builtins, `@async*`).
- `docs/sf/QUICK_REF.md` — the authoritative build / compile / gate command
  cheat sheet.
- `stdlib_test/` — runnable usage programs per module group
  (`bits_buf_str_usage`, `crypto_codec_usage`, `file_stdin_usage`,
  `file_stream_usage`, `map_sort_heap_usage`, `net_stream_usage`,
  `os_time_usage`).
- `repro/mi_matrix/stdlib_*_xmod/` — per-function fixtures.
