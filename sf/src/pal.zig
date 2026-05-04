const alloc_mod = @import("allocator.zig");
const Sand = alloc_mod.Sand;

extern fn write(fd: i32, buf: [*]const u8, count: i32) i32;
extern "c" fn fopen(path: [*]const u8, mode: [*]const u8) ?*void;
extern "c" fn fread(buf: [*]u8, size: u32, count: u32, file: *void) u32;
extern "c" fn fclose(file: *void) i32;
extern "c" fn fseek(file: *void, offset: i32, whence: i32) i32;
extern "c" fn ftell(file: *void) i32;
extern "c" fn c_exit(code: i32) void;

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

pub fn stdout_write(msg: []const u8) void {
    _ = write(1, msg.ptr, @intCast(i32, msg.len));
}

pub fn stderr_write(msg: []const u8) void {
    _ = write(2, msg.ptr, @intCast(i32, msg.len));
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
