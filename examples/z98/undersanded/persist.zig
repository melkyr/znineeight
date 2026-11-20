// persist.zig — UNDERSANDED save public hub + file lifecycle (spec §32).
//
// save_scan.zig owns the scanner/read path; save_io.zig owns serialization and
// CRC verification. This module keeps the historical save API, the fault-
// injection seams tests swap, and the temp/bak/rename lifecycle.

const arena_mod = @import("std_arena.zig");
const buf_mod = @import("std_buf.zig");
const file_mod = @import("std_file.zig");
const def = @import("def.zig");
const paths = @import("paths.zig");
const scan = @import("save_scan.zig");
const io = @import("save_io.zig");

pub const SaveErr = scan.SaveErr;
pub const MAX_LINE: usize = scan.MAX_LINE;
pub const MAX_FILE: usize = scan.MAX_FILE;

// Fault-injection seam (R4): plain fn fields, defaults = std_file, no ?fn
// call-through. Tests swap and restore them.
pub var fs_rename: fn ([]const u8, []const u8) file_mod.FileError!void = file_mod.rename;
pub var fs_remove: fn ([]const u8) file_mod.FileError!void = file_mod.remove;
pub var fs_write: fn ([]const u8, []const u8) file_mod.FileError!void = file_mod.writeAll;

var g_arena_buf: [256 * 1024]u8 = undefined;

// Directory portion of a save path (including the trailing separator). Both
// separators are accepted because the deployed target is Win9x.
fn dirOf(path: []const u8) []const u8 {
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') return path[0 .. i + 1];
    }
    return path[0..0];
}

fn siblingInto(path: []const u8, name: []const u8, out: []u8) ?[]u8 {
    return paths.join(dirOf(path), name, out);
}

pub fn crcOf(prefix: []const u8) u32 {
    return scan.crcOf(prefix);
}

pub fn logError(dir: []const u8, msg: []const u8) void {
    var path_buf: [4096]u8 = undefined;
    const path = paths.join(dir, "errors.log", path_buf[0..]) orelse return;
    var abuf: [1]u8 = undefined;
    var arena = arena_mod.init(abuf[0..]);
    var f = file_mod.open(&arena, path, file_mod.Mode.Append) catch return;
    file_mod.write(&f, msg) catch {
        file_mod.close(&f);
        return;
    };
    file_mod.write(&f, "\n") catch {};
    file_mod.flush(&f) catch {};
    file_mod.close(&f);
}

// Startup recovery: a missing save0.dat with a present save.bak is the crash
// window between steps 4 and 5. Restore the backup (log it) and drop any stale
// save.tmp. Call before any fresh-install decision (Task 3b wires boot).
pub fn recoverAtBoot(dir: []const u8) void {
    var save_buf: [4096]u8 = undefined;
    const save0 = paths.join(dir, "save0.dat", save_buf[0..]) orelse return;
    var bak_buf: [4096]u8 = undefined;
    const bak = paths.join(dir, "save.bak", bak_buf[0..]) orelse return;
    var tmp_buf: [4096]u8 = undefined;
    const tmp = paths.join(dir, "save.tmp", tmp_buf[0..]) orelse return;

    if (!file_mod.exists(save0) and file_mod.exists(bak)) {
        fs_rename(bak, save0) catch {
            logError(dir, "startup recovery failed: could not restore save0.dat from save.bak");
            fs_remove(tmp) catch {};
            return;
        };
        logError(dir, "startup recovery restored save0.dat from save.bak");
    }
    fs_remove(tmp) catch {};
}

pub fn saveRead(path: []const u8, w: *def.World, exp: *def.Expedition) SaveErr!void {
    return scan.saveRead(path, w, exp);
}

pub fn saveWrite(path: []const u8, w: *const def.World, exp: *const def.Expedition) SaveErr!void {
    var arena = arena_mod.init(g_arena_buf[0..]);
    var out = buf_mod.init(&arena);
    io.buildSave(&out, w, exp) catch |e| return e;
    const bytes = buf_mod.slice(&out);

    var tmp_buf: [4096]u8 = undefined;
    const tmp = siblingInto(path, "save.tmp", tmp_buf[0..]) orelse return SaveErr.Io;
    var bak_buf: [4096]u8 = undefined;
    const bak = siblingInto(path, "save.bak", bak_buf[0..]) orelse return SaveErr.Io;

    // 1 + 2: serialize to save.tmp (writeAll flushes and closes).
    fs_write(tmp, bytes) catch |write_err| {
        fs_remove(tmp) catch {};
        return scan.mapFileError(write_err);
    };

    // 3: re-read save.tmp and verify its CRC before any rename.
    io.verifyCrcFile(tmp) catch |verify_err| {
        fs_remove(tmp) catch {};
        return verify_err;
    };

    // 4: remove stale save.bak (mandatory on Win9x), then dest -> save.bak.
    var had_dest = false;
    if (file_mod.exists(path)) {
        if (file_mod.exists(bak)) {
            fs_remove(bak) catch |remove_err| return scan.mapFileError(remove_err);
        }
        fs_rename(path, bak) catch |bak_err| return scan.mapFileError(bak_err);
        had_dest = true;
    }

    // 5 (+6): commit; on any failure restore save.bak -> save0.dat.
    fs_rename(tmp, path) catch {
        if (had_dest) {
            fs_rename(bak, path) catch {};
        }
        return SaveErr.Io;
    };
}

// Direct serializer for tooling that must not touch the save0 rollback
// siblings (save.tmp/save.bak). Builds the canonical image and writes it
// straight to `path`; callers own integrity checks and cleanup.
pub fn saveWriteDirect(path: []const u8, w: *const def.World, exp: *const def.Expedition) SaveErr!void {
    var arena = arena_mod.init(g_arena_buf[0..]);
    var out = buf_mod.init(&arena);
    io.buildSave(&out, w, exp) catch |e| return e;
    const bytes = buf_mod.slice(&out);
    fs_write(path, bytes) catch |e| return scan.mapFileError(e);
}

// Manual backup slot: write save1.dat directly (never auto-written). It does
// not use the 6-step save0 path because that would overwrite save.bak.
pub fn saveBackupSlot(dir: []const u8, w: *const def.World, exp: *const def.Expedition) SaveErr!void {
    var arena = arena_mod.init(g_arena_buf[0..]);
    var out = buf_mod.init(&arena);
    io.buildSave(&out, w, exp) catch |e| return e;
    const bytes = buf_mod.slice(&out);

    var slot_buf: [4096]u8 = undefined;
    const slot = paths.join(dir, "save1.dat", slot_buf[0..]) orelse return SaveErr.Io;
    file_mod.writeAll(slot, bytes) catch |e| return scan.mapFileError(e);
    logError(dir, "backup slot written: save1.dat");
}
