// std_debug.zig — Z98 logging + assertion helpers (STDLIB §3.4).
//
// Output routes ONLY through the @stdoutWrite / @putChar builtins (no cstdio,
// no externs, no C-runtime dependence). `panic` is a PRINTED abort followed by
// a real divergence trap: `assert(false)`/`panic()` call `pal_trap()` (x86
// `int3`; `pal_abort()` on non-x86), which never returns.
//
//   log(msg)        writes msg bytes verbatim
//   logInt(tag, n)  writes tag, ':', ' ', the signed decimal n, '\n'
//   assert(cond)    on false writes "assertion failed\n" then traps
//   panic(msg)      writes "panic: ", msg, '\n' then traps
//
// The trap path terminates the process (SIGTRAP) and cannot be a GREEN fixture
// run; GREEN fixtures exercise only passing asserts / log / logInt. The failing
// path is proven separately by a scratch probe run under a timeout.

extern "c" fn pal_trap() noreturn;

const io = @import("std_io.zig");

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
    pal_trap();
}

// --- Trap handling (blueprint §3 L1; operator trap hook 2026-09-17) ---------
//
// The single authorized compiler<->std crossing in Plan A: the emitted
// zig_pal.c owns `TrapContext`/`g_trap_handler`, exposes
// `pal_set_trap_handler`, and `pal_trap()` populates the context and invokes
// the installed handler before terminating. The C struct layout is fixed
// (10 x unsigned int); the field names AND order below MUST match
// sf/src/include/zig_pal.c exactly.
pub const TrapContext = struct {
    eip: u32, esp: u32, ebp: u32, eflags: u32,
    eax: u32, ebx: u32, ecx: u32, edx: u32,
    esi: u32, edi: u32,
};

// One error set per module (R2); writeCoreDump is the only fallible function.
pub const DebugError = error{CoreDumpWriteFailed};

// Plan A Task 4c: the blueprint §3 L1 signature is restored now that Task 4b-F
// fixed the optional-fn-pointer C emission (`?fn` extern parameters no longer
// materialize an `int`). The extern takes the optional function pointer
// directly; `setTrapHandler(null)` is the null-uninstall, so the redundant
// `clearTrapHandler` helper (non-blueprint) is dropped.
extern "c" fn pal_set_trap_handler(h: ?fn(*TrapContext) void) void;
extern "c" fn pal_abort() noreturn;

pub fn setTrapHandler(h: ?fn(*TrapContext) void) void {
    pal_set_trap_handler(h);
}

// NOTE (Plan A Task 4): the blueprint's `backtrace(ctx, out: *std.buf.Buf)`
// is deferred. It consumes `std_buf` (Plan A Task 5, L2); importing it here
// would be an L1->L2 R3 violation, and the module does not exist yet. It must
// land with (or after) Task 5.

// Default handler: write `core.dump` in the CWD, then abort. A failed dump
// (open/write) still terminates — the trap path must never return.
pub fn defaultTrapHandler(ctx: *TrapContext) noreturn {
    _ = writeCoreDump(ctx, "core.dump") catch {};
    pal_abort();
}

// Dump the captured register context to `path` as one `name=decimal` line per
// field (struct order). Pure std: std_io file I/O only, no cstdio.
pub fn writeCoreDump(ctx: *const TrapContext, path: []const u8) DebugError!void {
    var fd = io.fileOpen(path, true) orelse return error.CoreDumpWriteFailed;
    writeField(fd, "eip", ctx.eip);
    writeField(fd, "esp", ctx.esp);
    writeField(fd, "ebp", ctx.ebp);
    writeField(fd, "eflags", ctx.eflags);
    writeField(fd, "eax", ctx.eax);
    writeField(fd, "ebx", ctx.ebx);
    writeField(fd, "ecx", ctx.ecx);
    writeField(fd, "edx", ctx.edx);
    writeField(fd, "esi", ctx.esi);
    writeField(fd, "edi", ctx.edi);
    io.fileClose(fd);
}

// writeField/writeU32: tiny decimal formatter for the core dump. No cstdio,
// no allocation (stack buffers only).
fn writeField(fd: usize, name: []const u8, v: u32) void {
    io.fileWrite(fd, name);
    var eq: []const u8 = "=";
    io.fileWrite(fd, eq);
    writeU32(fd, v);
    var nl: []const u8 = "\n";
    io.fileWrite(fd, nl);
}

fn writeU32(fd: usize, v: u32) void {
    var tmp: [10]u8 = undefined;
    var len: usize = 0;
    if (v == 0) {
        tmp[0] = '0';
        len = 1;
    } else {
        var x = v;
        while (x > 0) {
            tmp[len] = '0' + @intCast(u8, x % 10);
            len += 1;
            x = x / 10;
        }
    }
    var out: [10]u8 = undefined;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        out[i] = tmp[len - 1 - i];
    }
    io.fileWrite(fd, out[0..len]);
}
