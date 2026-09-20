# OS, Time & Diagnostics — `std.os` + `std.time` + `std.debug`

| | |
|---|---|
| **Modules** | `std.os`, `std.time`, `std.debug` |
| **Layers** | `L1` — process, clock, and diagnostic primitives over the builtins and a per-OS PAL; `std.debug.backtrace` reaches up to `L2` (`std.buf`) |
| **Import (re-export)** | `const std = @import("std");` → `std.os`, `std.time`, `std.debug` |
| **Import (by path)** | `const std_os = @import("std_os");`, `const std_time = @import("std_time");`, `const std_debug = @import("std_debug");` |

## Module overview

These three modules cover the parts of a program that touch the process and the
machine rather than data: its arguments and environment, the current directory,
the two clocks, and the diagnostic output and crash path.

`std.os` exposes the process surface: `initArgs`/`argc`/`argv` (the program's
argument vector), `env`, `cwd`, and `exit`. There is no compiler argument-capture
hook: a `main` that wants arguments declares them as
`pub fn main(argc: i32, argv: [*]*const u8) void` (the emitted C wrapper forwards
`argc`/`argv` only when `main` declares them) and calls `initArgs(argc, argv)`
itself. `cwd` is the only allocating function here (R1): it takes an `arena` and
returns the directory as a slice into an arena allocation. `env` and `argv`
return slices that **alias** the process's own memory; they never allocate and
the caller never frees them.

`std.time` exposes two clocks and a sleep. `ticksMs` is the coarse millisecond
counter, `highRes` is the high-resolution monotonic counter whose unit is
`1 / highResFreq()` seconds, and `wallClockUnix` is UTC seconds since the epoch.
`clockMonotonicAvailable` reports whether the POSIX monotonic source was
selected at C compile time. Per rule **R6**, a target without a high-resolution
timer falls back to `ticksMs() * 1000`, so on such hardware consecutive
`highRes` samples can be equal — the clock stays monotonic but not strictly
increasing. `sleepMs` wraps the `@sleepMs` builtin (identical to
`std.io.sleepMs`).

`std.debug` is the diagnostics module. `log`/`logInt` write to standard output,
`assert`/`panic` print and then **trap** (never returning on the failing path),
and `setTrapHandler` installs an optional callback that the trap path invokes
with a captured register context before terminating. `writeCoreDump` serializes
that context to a file, and `backtrace` walks the x86 frame chain into a
`std.buf.Buf`.

**Per-OS split.** OS specifics live in private std-side PAL units, never in
the compiler PAL. `std_os_pal.zig` selects `GetCurrentDirectoryA` (win32) vs
`getcwd` (POSIX) and declares `getenv` for both. `std_time_pal.zig` selects
`GetTickCount`/`QueryPerformanceCounter`/`QueryPerformanceFrequency` (win32) vs
`gettimeofday` and a compile-time-selected monotonic read (POSIX). All of these
are documented in place below. The win32 caveats: `ticksMs` is milliseconds
since boot; `highRes` uses QPC counts; `clockMonotonicAvailable` is always
`false`; and an over-long `cwd` path is reported as `error.CwdFailed` rather
than truncated.

## Quick start

```zig
const std = @import("std");

fn onTrap(ctx: *std.debug.TrapContext) void {
    std.debug.writeCoreDump(ctx, "crash.dump") catch {};
    std.io.write("trapped\n");
}

pub fn main() !void {
    std.debug.setTrapHandler(onTrap);

    const freq = std.time.highResFreq();
    const t0 = std.time.highRes();
    std.debug.logInt("highres", @intCast(i32, t0 % freq));

    std.debug.setTrapHandler(null);
}
```

## API

### `std.os`

#### `OsError`

**Purpose** — the error set of `cwd`: an exhausted arena or a failed/oversized
directory query.

**When to use** — when naming the failure of `cwd`, or when a function's own
error set must include it.

**Signature** — `pub const OsError = error{ OutOfMemory, CwdFailed };`

**Parameters** — none.

**Returns** — an error set, not a value.

**Errors** — `error.OutOfMemory`, `error.CwdFailed`.

**Example**
```zig
const dir = std.os.cwd(&arena) catch |e| {
    if (e == error.CwdFailed) return;
    return;
};
_ = dir;
```

**Gotchas** — `CwdFailed` covers both a failed OS query and a path that does not
fit the fixed 4096-byte work buffer; a failed `cwd` leaves the arena's cursor
advanced by the buffer it already allocated.

#### `initArgs`

**Purpose** — saves the argument count and vector so `argc`/`argv` can read them.

**When to use** — once, at the very top of `main`, before any `argc()`/`argv(i)`
call. The compiler emits no argument-capture hook, so nothing calls this for you:
a `main` that declares `(argc: i32, argv: [*]*const u8)` must forward them here.

**Signature** — `pub fn initArgs(arg_count: i32, arg_values: [*]*const u8) void`

**Parameters**
- `arg_count` — the C `argc`: the number of arguments, including the program
  name at index 0.
- `arg_values` — the C `argv`: a many-item pointer to `arg_count`
  NUL-terminated strings.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
pub fn main(argc: i32, argv: [*]*const u8) void {
    std.os.initArgs(argc, argv);
    // argc()/argv(i) now read the values saved here.
}
```

**Gotchas** — the saved pointers are stored, not copied: `arg_values` and every
string it points at must stay alive for as long as `argv(i)` is used. The
parameter names are `arg_count`/`arg_values`, not `argc`/`argv`, because those
names would resolve to this module's own functions.

#### `argc`

**Purpose** — returns the argument count saved by `initArgs`.

**When to use** — to bound an `argv(i)` loop.

**Signature** — `pub fn argc() usize`

**Parameters** — none.

**Returns** — the saved count as a `usize`.

**Errors** — none.

**Example**
```zig
var i: usize = 0;
while (i < std.os.argc()) : (i += 1) {
    std.io.write(std.os.argv(i));
    std.io.write("\n");
}
```

**Gotchas** — before `initArgs` runs the backing global is `undefined`, so the
result is meaningless; call `initArgs` first.

#### `argv`

**Purpose** — returns the `i`-th argument as a slice up to its NUL terminator.

**When to use** — to read a specific argument after `initArgs`.

**Signature** — `pub fn argv(i: usize) []const u8`

**Parameters**
- `i` — argument index; `0` is the program name. Must be less than `argc()`.

**Returns** — a `[]const u8` over the argument bytes (the NUL is not included).

**Errors** — none.

**Example**
```zig
if (std.os.argc() > 1) {
    std.io.write(std.os.argv(1));
}
```

**Gotchas** — no bounds check: `i >= argc()` reads past the saved vector. The
returned slice aliases the process's argument memory; it is read-only and is not
freed by the caller.

#### `exit`

**Purpose** — terminates the process with the given status code.

**When to use** — to leave `main` early with an explicit status, or from deep in
a call chain where unwinding is not wanted.

**Signature** — `pub fn exit(code: i32) noreturn`

**Parameters**
- `code` — the process exit status; `0` conventionally means success.

**Returns** — nothing; the return type is `noreturn`.

**Errors** — none.

**Example**
```zig
if (std.os.argc() < 2) std.os.exit(1);
```

**Gotchas** — `exit` does not run arena cleanup (there is none) and never
returns; code after it is unreachable.

#### `env`

**Purpose** — looks up an environment variable and returns its value.

**When to use** — for configuration that the caller passes through the
environment rather than on the command line.

**Signature** — `pub fn env(name: []const u8) ?[]const u8`

**Parameters**
- `name` — the variable name. Names of `256` bytes or more are rejected as
  unset.

**Returns** — `?[]const u8`: the value bytes, or `null` when the variable is
unset or the name is too long. An empty value is a non-null empty slice.

**Errors** — none; "not found" is `null`, not an error.

**Example**
```zig
if (std.os.env("HOME")) |home| {
    std.io.write(home);
    std.io.write("\n");
}
```

**Gotchas** — the returned slice aliases the process environment; do not write
through it and do not free it. The lookup copies the name into a fixed
stack buffer, so an over-long name is `null` rather than truncated to a
different variable.

#### `cwd`

**Purpose** — returns the current working directory as a slice into a fresh
arena allocation.

**When to use** — when you need an absolute base path for relative file opens
(see [`io.md`](io.md)).

**Signature** — `pub fn cwd(arena: *std.arena.Arena) OsError![]u8`

**Parameters**
- `arena` — the arena to allocate the directory buffer from (R1).

**Returns** — `[]u8` over the directory bytes, without the NUL terminator.

**Errors**
- `error.OutOfMemory` — the arena could not satisfy the fixed 4096-byte request.
- `error.CwdFailed` — the OS directory query failed, or the path did not fit the
  work buffer (the win32 over-long-path case).

**Example**
```zig
var backing: [4096]u8 = undefined;
var arena = std.arena.init(backing[0..]);
const dir = try std.os.cwd(&arena);
std.io.write(dir);
std.arena.reset(&arena);
```

**Gotchas** — each call allocates a fresh 4096-byte buffer; the memory is
reclaimed only by `std.arena.reset`. The returned slice is invalid after that
reset. On POSIX the path length is bounded by the fixed buffer, not by
`PATH_MAX`.

### `std.time`

#### `ticksMs`

**Purpose** — a coarse millisecond counter, wrapping every ~49.7 days.

**When to use** — for timeouts and elapsed-time checks where millisecond
resolution and wrap-around are acceptable. For intervals, prefer `highRes`.

**Signature** — `pub fn ticksMs() u32`

**Parameters** — none.

**Returns** — a `u32` millisecond count. win32: milliseconds since boot
(`GetTickCount`). POSIX: wall-clock milliseconds since the epoch, truncated to
32 bits.

**Errors** — none.

**Example**
```zig
const start = std.time.ticksMs();
// ... work ...
const elapsed = std.time.ticksMs() - start;
_ = elapsed;
```

**Gotchas** — the value wraps (subtracting two readings still gives the correct
elapsed count modulo 2^32). On POSIX this is **wall-clock**, so it is not
monotonic: a clock adjustment can move it backwards. Use `highRes` for a
monotonic source.

#### `highRes`

**Purpose** — a high-resolution monotonic counter.

**When to use** — for measuring elapsed intervals and for any place a
non-decreasing clock is required. This is the clock to pair with `highResFreq`.

**Signature** — `pub fn highRes() u64`

**Parameters** — none.

**Returns** — a `u64` counter reading whose unit is `1 / highResFreq()`
seconds. win32: `QueryPerformanceCounter` counts, or `ticksMs() * 1000` when no
usable performance counter exists. POSIX: nanoseconds
(`clock_gettime(CLOCK_MONOTONIC)` when available, else `gettimeofday`
microseconds — always divide by `highResFreq()`).

**Errors** — none.

**Example**
```zig
const freq = std.time.highResFreq();
const t0 = std.time.highRes();
// ... work ...
const ms = (std.time.highRes() - t0) * @intCast(u64, 1000) / freq;
_ = ms;
```

**Gotchas** — **R6 determinism:** on hardware with no high-resolution timer the
counter is `ticksMs() * 1000`, so consecutive samples can be equal. The clock
never goes backwards, but it is not guaranteed to advance between calls. The
unit is not fixed; always divide by `highResFreq()` rather than assuming
nanoseconds or milliseconds.

#### `clockMonotonicAvailable`

**Purpose** — reports whether the POSIX target provides
`clock_gettime(CLOCK_MONOTONIC)`.

**When to use** — to distinguish the monotonic-nanosecond source from the
`gettimeofday` fallback when reasoning about resolution.

**Signature** — `pub fn clockMonotonicAvailable() bool`

**Parameters** — none.

**Returns** — `true` when the POSIX build selected `clock_gettime(CLOCK_MONOTONIC)`
at C compile time; `false` on win32 and on POSIX targets without it.

**Errors** — none.

**Example**
```zig
if (std.time.clockMonotonicAvailable()) {
    std.io.write("monotonic clock\n");
}
```

**Gotchas** — always `false` on win32, which uses `QueryPerformanceCounter`
instead. The answer is fixed at C compile time, not probed at run time.

#### `highResFreq`

**Purpose** — returns the number of `highRes` ticks per second.

**When to use** — to convert a `highRes` delta into seconds or milliseconds.

**Signature** — `pub fn highResFreq() u64`

**Parameters** — none.

**Returns** — ticks per second. win32: the `QueryPerformanceFrequency` value, or
`1000000` when no usable counter exists. POSIX: `1000000000` for the monotonic
nanosecond source, or `1000000` for the `gettimeofday` microsecond fallback.

**Errors** — none.

**Example**
```zig
const ns = (std.time.highRes() - t0) * @intCast(u64, 1000000000) / std.time.highResFreq();
_ = ns;
```

**Gotchas** — the fallback frequency (`1000000`) is chosen to match the
`ticksMs() * 1000` fallback unit, so `highRes`/`highResFreq` stays consistent
even when the two win32 queries disagree about whether a counter is usable.

#### `wallClockUnix`

**Purpose** — returns UTC seconds since the Unix epoch.

**When to use** — for calendar/timestamp values, logging, and wall-clock
display. For durations use `highRes`.

**Signature** — `pub fn wallClockUnix() i64`

**Parameters** — none.

**Returns** — an `i64` count of UTC seconds since 1970-01-01T00:00:00Z.

**Errors** — none.

**Example**
```zig
const now = std.time.wallClockUnix();
std.debug.logInt("years since epoch", @intCast(i32, now / @intCast(i64, 31536000)));
```

**Gotchas** — this is wall-clock time: it can jump forward or backward when the
system clock is adjusted. It is not monotonic. On the pinned 32-bit target the
C `time_t` may be 32-bit, so values beyond its range are not representable even
though the return type is `i64`.

#### `sleepMs`

**Purpose** — suspends the calling thread for a number of milliseconds.

**When to use** — to pace a loop or wait out a short delay. In the Model C
async model this blocks the whole program; yielding is done by the scheduler,
not here.

**Signature** — `pub fn sleepMs(ms: u32) void`

**Parameters**
- `ms` — milliseconds to sleep. `0` returns promptly.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.time.sleepMs(10);
```

**Gotchas** — the sleep duration is a minimum, not a guarantee. This is the
same builtin-backed sleep as `std.io.sleepMs`; use either.

### `std.debug`

#### `TrapContext`

**Purpose** — the x86 register snapshot delivered to a trap handler.

**When to use** — as the parameter type of a handler installed with
`setTrapHandler`, and as the input to `writeCoreDump` and `backtrace`.

**Signature** — `pub const TrapContext = struct { eip: u32, esp: u32, ebp: u32, eflags: u32, eax: u32, ebx: u32, ecx: u32, edx: u32, esi: u32, edi: u32 };`

**Parameters** (fields)
- `eip`/`esp`/`ebp`/`eflags` — instruction pointer, stack pointer, frame
  pointer, and flags at the trap site.
- `eax`/`ebx`/`ecx`/`edx`/`esi`/`edi` — the general-purpose registers.

**Returns** — a plain value type; the handler receives a pointer to one.

**Errors** — none.

**Example**
```zig
fn onTrap(ctx: *std.debug.TrapContext) void {
    std.debug.logInt("eip", @intCast(i32, ctx.eip));
}
```

**Gotchas** — the field names **and order** are fixed by the C side
(`zig_pal.c`); do not reorder or rename them. The capture is GCC/x86-only: other
compilers receive a zero-filled context (the pointer is still valid).

#### `DebugError`

**Purpose** — the error set of `writeCoreDump`; its only member is
`CoreDumpWriteFailed`.

**When to use** — when naming the failure of a core-dump write.

**Signature** — `pub const DebugError = error{CoreDumpWriteFailed};`

**Parameters** — none.

**Returns** — an error set, not a value.

**Errors** — `error.CoreDumpWriteFailed`.

**Example**
```zig
std.debug.writeCoreDump(ctx, "core.dump") catch |e| {
    if (e == error.CoreDumpWriteFailed) return;
};
```

**Gotchas** — a write failure **after** a successful open is not reported (the
underlying `fileWrite`/`fileClose` return nothing), so only an open failure
surfaces as `CoreDumpWriteFailed`.

#### `log`

**Purpose** — writes a byte slice verbatim to standard output.

**When to use** — for plain diagnostic text where you control the bytes. For a
tagged integer use `logInt`.

**Signature** — `pub fn log(msg: []const u8) void`

**Parameters**
- `msg` — the bytes to write; no terminator is added and nothing is formatted.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.debug.log("starting\n");
```

**Gotchas** — output goes straight to the `@stdoutWrite` builtin (the same
unbuffered path as `std.io.write`); no newline is appended, so include one in
`msg` if you want one. `log` is not printf-style.

#### `logInt`

**Purpose** — writes `tag`, a colon and space, a signed decimal integer, and a
newline.

**When to use** — for a labelled numeric trace where you do not want to format
by hand.

**Signature** — `pub fn logInt(tag: []const u8, n: i32) void`

**Parameters**
- `tag` — the label written before the separator; no terminator is added.
- `n` — the signed decimal value (including `i32` minimum).

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.debug.logInt("count", 42);
// writes: count: 42\n
```

**Gotchas** — always emits the `": "` separator and a trailing newline; there
is no way to suppress them. The value is formatted into a fixed 12-byte stack
buffer, so the call never allocates.

#### `assert`

**Purpose** — checks a condition and, on failure, prints a message and traps.

**When to use** — for invariants that must never be violated; it always traps
on failure, so keep it out of hot loops.

**Signature** — `pub fn assert(cond: bool) void`

**Parameters**
- `cond` — the condition to require. When `true`, the call is a no-op.

**Returns** — nothing on success; it does not return when `cond` is `false`.

**Errors** — none; the failure path is a process trap, not an error value.

**Example**
```zig
std.debug.assert(len <= buf.len);
```

**Gotchas** — on failure it writes `assertion failed\n` and then executes the
trap path (`pal_trap`), which terminates the process and **never returns**. A
failing assert cannot be caught or recovered; it cannot appear in a green test
run.

#### `panic`

**Purpose** — prints `panic: <msg>` and traps.

**When to use** — for unrecoverable states where you want a message before the
trap. Prefer returning an error for anything the caller can handle.

**Signature** — `pub fn panic(msg: []const u8) noreturn`

**Parameters**
- `msg` — the panic text written after `panic: `; a newline is added.

**Returns** — nothing; the return type is `noreturn`.

**Errors** — none; the trap is the termination, not an error value.

**Example**
```zig
if (fd == 0) std.debug.panic("stdin closed");
```

**Gotchas** — always terminates via the trap path; the message goes to standard
output, not standard error. There is no payload formatting.

#### `setTrapHandler`

**Purpose** — installs or clears the global trap callback.

**When to use** — at startup to capture a crash context (for a core dump or a
custom trace), and again with `null` to uninstall it.

**Signature** — `pub fn setTrapHandler(h: ?fn(*TrapContext) void) void`

**Parameters**
- `h` — the handler to run when a trap occurs, or `null` to clear the hook.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std.debug.setTrapHandler(onTrap);
// ... later ...
std.debug.setTrapHandler(null);
```

**Gotchas** — there is a single global handler: installing one replaces the
previous. The handler runs on the trap path and must return normally (the trap
still terminates afterward); it should avoid operations that could themselves
fault. `pal_trap` invokes it only after populating the context.

#### `backtrace`

**Purpose** — walks the x86 `ebp` frame chain and appends each frame pointer to
a `std.buf.Buf`.

**When to use** — inside a trap handler, to record a raw frame-pointer trace
for later inspection.

**Signature** — `pub fn backtrace(ctx: *const TrapContext, out: *std.buf.Buf) !void`

**Parameters**
- `ctx` — the trap context; the walk starts at `ctx.ebp`.
- `out` — the buffer to append frame pointers to, each as a little-endian
  `u32`.

**Returns** — nothing on success; `out` grows by one `u32` per frame.

**Errors** — `error.OutOfMemory` from the underlying `std.buf.appendU32LE` when
the arena cannot grow `out`.

**Example**
```zig
var trace = std.buf.init(&arena);
std.debug.backtrace(ctx, &trace) catch {};
```

**Gotchas** — this is a raw frame-pointer walk, not a symbolizing backtrace: it
records addresses only. It stops at a null successor or a non-increasing frame
pointer (the stack grows down). It assumes a valid `ebp` chain, so a corrupted
or optimized-away frame pointer can end the walk early. `backtrace` is the one
documented `L1 → L2` import of `std.buf` (R3 exception).

#### `defaultTrapHandler`

**Purpose** — the default handler: writes `core.dump` in the current directory,
then aborts.

**When to use** — as the reference behavior, or when you want a dump without
writing a handler of your own.

**Signature** — `pub fn defaultTrapHandler(ctx: *TrapContext) noreturn`

**Parameters**
- `ctx` — the trap context to serialize.

**Returns** — nothing; the return type is `noreturn`.

**Errors** — none exposed; a failed dump is ignored and the abort still happens.

**Example**
```zig
std.debug.setTrapHandler(std.debug.defaultTrapHandler);
```

**Gotchas** — the trap path must never return, so a dump failure is swallowed
and `pal_abort()` still terminates. The file is always named `core.dump` in the
process's current directory.

#### `writeCoreDump`

**Purpose** — writes a register context to a file, one `name=decimal` line per
field in struct order.

**When to use** — from a trap handler, or anywhere you want a readable snapshot
of a `TrapContext`.

**Signature** — `pub fn writeCoreDump(ctx: *const TrapContext, path: []const u8) DebugError!void`

**Parameters**
- `ctx` — the context to serialize (not modified).
- `path` — the output file path. It is opened in truncating write mode.

**Returns** — nothing on success.

**Errors** — `error.CoreDumpWriteFailed` when the file cannot be opened (or the
path does not fit the fixed buffer).

**Example**
```zig
std.debug.writeCoreDump(ctx, "crash.dump") catch {};
```

**Gotchas** — fields are written in struct order (`eip`, `esp`, `ebp`,
`eflags`, `eax`, `ebx`, `ecx`, `edx`, `esi`, `edi`). Only the open failure is
reported; write errors after open are silently ignored. Uses `std.io`'s file
surface, not C stdio.

## See also

- `std.os`, `std.time`, `std.debug` — the modules in this doc.
- [`io.md`](io.md) — `std.io` console/file output shares the same unbuffered
  `@stdoutWrite` path as `std.debug.log`.
- [`memory.md`](memory.md) — `std.os.cwd` allocates through the `std.arena`
  model documented there.
- [`text.md`](text.md) — `std.buf.Buf`, the target of `std.debug.backtrace`.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
