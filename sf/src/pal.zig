const alloc_mod = @import("allocator.zig");
const Sand = alloc_mod.Sand;
const panic_mod = @import("panic.zig");

const ext_c = @import("extern_c.zig");
extern "c" fn fopen(path: [*]const u8, mode: [*]const u8) ?*void;
extern "c" fn fread(buf: [*]u8, size: u32, count: u32, file: *void) u32;
extern "c" fn fwrite(buf: [*]const u8, size: u32, count: u32, file: *void) u32;
extern "c" fn fclose(file: *void) i32;
extern "c" fn fseek(file: *void, offset: i32, whence: i32) i32;
extern "c" fn ftell(file: *void) i32;
extern "c" fn c_exit(code: i32) void;
extern "c" fn pal_file_open(path: [*]const u8, flags: i32) usize;
extern "c" fn pal_file_write(fd: usize, buf: [*]const u8, len: u32) i32;
extern "c" fn pal_file_close(fd: usize) i32;
extern "c" fn pal_get_default_lib_path(buf: [*]u8, bufsize: i32) i32;
extern "c" fn pal_dir_exists(path: [*]const u8) i32;

const SEEK_END: i32 = 2;
const SEEK_SET: i32 = 0;
const MODE_READ: [*]const u8 = "rb";

pub fn readFile(path: []const u8, alloc: *Sand) ?[]u8 {
    var c_path: [512]u8 = undefined;
    var i: usize = 0;
    while (i < path.len and i < 511) {
        c_path[i] = path[i];
        i += 1;
    }
    if (i >= 511) return null;
    c_path[i] = 0;
    var f = fopen(&c_path[0], MODE_READ) orelse return null;
    _ = fseek(f, 0, SEEK_END);
    var size = ftell(f);
    if (size <= 0) {
        _ = fclose(f);
        return null;
    }
    _ = fseek(f, 0, SEEK_SET);
    var sz = @intCast(u32, size);
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, sz), @intCast(usize, 1)) catch {
        _ = fclose(f);
        return null;
    };
    var buf = @ptrCast([*]u8, raw);
    var read = fread(buf, 1, sz, f);
    _ = fclose(f);
    if (read != sz) return null;
    return buf[0..sz];
}

pub fn fileExists(path: []const u8) bool {
    var c_path: [512]u8 = undefined;
    var i: usize = 0;
    while (i < path.len and i < 511) {
        c_path[i] = path[i];
        i += 1;
    }
    if (i >= 511) return false;
    c_path[i] = 0;
    var f = fopen(&c_path[0], MODE_READ) orelse return false;
    _ = fclose(f);
    return true;
}

pub fn dirExists(path: []const u8) bool {
    var c_path: [512]u8 = undefined;
    var i: usize = 0;
    while (i < path.len and i < 511) {
        c_path[i] = path[i];
        i += 1;
    }
    if (i >= 511) return false;
    c_path[i] = 0;
    return pal_dir_exists(&c_path[0]) != 0;
}

pub fn stdout_write(msg: []const u8) void {
    _ = ext_c.write(1, msg.ptr, @intCast(i32, msg.len));
}

pub fn stderr_write(msg: []const u8) void {
    _ = ext_c.write(2, msg.ptr, @intCast(i32, msg.len));
}

pub const INVALID_FD: usize = @intCast(usize, 0xFFFFFFFF);

pub fn fileOpen(path: []const u8, flags: i32) usize {
    var c_path: [512]u8 = undefined;
    var i: usize = 0;
    while (i < path.len and i < 511) {
        c_path[i] = path[i];
        i += 1;
    }
    if (i >= 511) return INVALID_FD;
    c_path[i] = 0;
    return pal_file_open(&c_path[0], flags);
}

pub fn fileWrite(fd: usize, msg: []const u8) void {
    _ = pal_file_write(fd, msg.ptr, @intCast(u32, msg.len));
}

pub fn fileClose(fd: usize) void {
    _ = pal_file_close(fd);
}

// Streaming stdio API (LIR spill stream). All disk I/O lives here (platform layer, Win9x target);
// consumers @import("pal.zig") and never declare their own "c" externs.
pub fn streamOpen(path: []const u8, mode: [*]const u8) ?*void {
    var c_path: [512]u8 = undefined;
    var i: usize = 0;
    while (i < path.len and i < 511) {
        c_path[i] = path[i];
        i += 1;
    }
    if (i >= 511) return null;
    c_path[i] = 0;
    var f = fopen(&c_path[0], mode);
    return f;
}

pub fn streamClose(file: *void) void {
    _ = fclose(file);
}

pub fn streamWrite(file: *void, buf: []const u8) void {
    if (buf.len == @intCast(usize, 0)) return;
    var wrote = fwrite(buf.ptr, @intCast(u32, 1), @intCast(u32, buf.len), file);
    if (wrote != @intCast(u32, buf.len)) {
        var emsg: []const u8 = "short write on spill stream (streamWrite)";
        var ef: []const u8 = "pal.zig";
        panic_mod.panicHandler(emsg, ef, 120);
    }
}

pub fn streamRead(file: *void, buf: []u8) void {
    if (buf.len == @intCast(usize, 0)) return;
    var got = fread(buf.ptr, @intCast(u32, 1), @intCast(u32, buf.len), file);
    if (got != @intCast(u32, buf.len)) {
        var emsg: []const u8 = "short read on spill stream (streamRead)";
        var ef: []const u8 = "pal.zig";
        panic_mod.panicHandler(emsg, ef, 130);
    }
}

pub fn streamSeek(file: *void, offset: i32) void {
    var rc = fseek(file, offset, SEEK_SET);
    if (rc != 0) {
        var emsg: []const u8 = "fseek failed on spill stream (streamSeek)";
        var ef: []const u8 = "pal.zig";
        panic_mod.panicHandler(emsg, ef, 139);
    }
}

pub fn getDefaultLibPath(buf: [*]u8, bufsize: i32) i32 {
    return pal_get_default_lib_path(buf, bufsize);
}

pub fn exit(code: u8) void {
    c_exit(@intCast(i32, code));
    while (true) {}
}

var saved_argc: i32 = 0;
var saved_argv: [*]*const u8 = undefined;

pub fn initArgs(argc: i32, argv: [*]*const u8) void {
    saved_argc = argc;
    saved_argv = argv;
}

pub fn argCount() i32 {
    return saved_argc;
}

pub fn argGet(i: i32) [*]const u8 {
    return saved_argv[@intCast(usize, i)];
}

var g_markers_enabled: u32 = 0;

pub fn markersEnabled(on: u32) void {
    g_markers_enabled = on;
}

pub fn isMarkersEnabled() bool {
    return g_markers_enabled != 0;
}

// compile-time-disabled debug-flood gate: per-node/per-inst debug traces
// (pal.markerWrite* below) emit nothing while 0. The ~30 measurement markers
// (pal.measureMarkerWrite*) stay live so --markers / --track-memory keep working.
pub const g_markers_debug: u32 = 0;

const itoa_mod = @import("util/itoa.zig");

pub fn markerWrite(msg: []const u8) void {
    if (g_markers_debug != @intCast(u32, 0)) {
        if (g_markers_enabled != @intCast(u32, 0)) {
            stderr_write(msg);
        }
    }
}

pub fn markerWriteInt(prefix: []const u8, value: u32) void {
    if (g_markers_debug != @intCast(u32, 0)) {
        if (g_markers_enabled != @intCast(u32, 0)) {
            var s_p: []const u8 = prefix;
            markerWrite(s_p);
            var buf: [12]u8 = undefined;
            var vlen = itoa_mod.itoa(value, buf[0..]);
            var start: usize = @intCast(usize, 12) - @intCast(usize, vlen) - @intCast(usize, 1);
            markerWrite(buf[start..@intCast(usize, 11)]);
            var s_nl: []const u8 = "\n";
            markerWrite(s_nl);
        }
    }
}

pub fn markerWriteInt64(prefix: []const u8, value: u64) void {
    if (g_markers_debug != @intCast(u32, 0)) {
        if (g_markers_enabled != @intCast(u32, 0)) {
            var s_p: []const u8 = prefix;
            markerWrite(s_p);
            var buf: [24]u8 = undefined;
            var vlen = itoa_mod.itoa64(value, buf[0..]);
            var start: usize = @intCast(usize, 24) - @intCast(usize, vlen) - @intCast(usize, 1);
            markerWrite(buf[start..@intCast(usize, 23)]);
            var s_nl: []const u8 = "\n";
            markerWrite(s_nl);
        }
    }
}

pub fn measureMarkerWrite(msg: []const u8) void {
    if (g_markers_enabled != @intCast(u32, 0)) {
        stderr_write(msg);
    }
}

pub fn measureMarkerWriteInt(prefix: []const u8, value: u32) void {
    if (g_markers_enabled != @intCast(u32, 0)) {
        var s_p: []const u8 = prefix;
        measureMarkerWrite(s_p);
        var buf: [12]u8 = undefined;
        var vlen = itoa_mod.itoa(value, buf[0..]);
        var start: usize = @intCast(usize, 12) - @intCast(usize, vlen) - @intCast(usize, 1);
        measureMarkerWrite(buf[start..@intCast(usize, 11)]);
        var s_nl: []const u8 = "\n";
        measureMarkerWrite(s_nl);
    }
}

pub fn measureMarkerWriteInt64(prefix: []const u8, value: u64) void {
    if (g_markers_enabled != @intCast(u32, 0)) {
        var s_p: []const u8 = prefix;
        measureMarkerWrite(s_p);
        var buf: [24]u8 = undefined;
        var vlen = itoa_mod.itoa64(value, buf[0..]);
        var start: usize = @intCast(usize, 24) - @intCast(usize, vlen) - @intCast(usize, 1);
        measureMarkerWrite(buf[start..@intCast(usize, 23)]);
        var s_nl: []const u8 = "\n";
        measureMarkerWrite(s_nl);
    }
}
