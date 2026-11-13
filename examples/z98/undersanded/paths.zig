const str = @import("std_str");
const os = @import("std_os");
const file_mod = @import("std_file");

@cInclude("<std_os_prelude.h>");
@cInclude("<sys/stat.h>");

// Directory creation for the writable-data fallback. Win32 uses
// CreateDirectoryA (windows.h via the prelude); POSIX uses mkdir(2)
// (sys/stat.h). The @isWindows() guards keep the unused symbol out of the
// emitted C on each target.
pub extern "stdcall" fn CreateDirectoryA(lpPathName: [*]const u8, lpSecurityAttributes: *void) i32;
pub extern "c" fn mkdir(path: [*]const u8, mode: u32) i32;

pub const FALLBACK_WIN = "C:\\WINDOWS\\TEMP\\UNDERSAN\\";
pub const FALLBACK_POSIX = "/tmp/UNDERSAN";

fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

fn is83Char(c: u8) bool {
    if (c >= 'a' and c <= 'z') return true;
    if (c >= '0' and c <= '9') return true;
    return c == '_' or c == '-';
}

pub fn is83Name(name: []const u8) bool {
    if (name.len == 0) return false;

    var base_end: usize = name.len;
    const dot = str.findChar(name, '.');
    if (dot) |d| {
        base_end = d;
        const ext = name[d + 1 .. name.len];
        if (ext.len < 1 or ext.len > 3) return false;
        var ei: usize = 0;
        while (ei < ext.len) : (ei += 1) {
            if (!is83Char(ext[ei])) return false;
        }
    }

    if (base_end < 1 or base_end > 8) return false;
    var i: usize = 0;
    while (i < base_end) : (i += 1) {
        if (!is83Char(name[i])) return false;
    }
    return true;
}

pub fn pathJoin83(dir: []const u8, name: []const u8, out: []u8) ?[]u8 {
    if (!is83Name(name)) return null;

    var sep = true;
    if (dir.len == 0) {
        sep = false;
    } else {
        const last = dir[dir.len - 1];
        if (last == '\\' or last == '/') sep = false;
    }

    var need: usize = dir.len + name.len;
    if (sep) need += 1;
    if (need > out.len) return null;

    str.copy(out, dir);
    var o: usize = dir.len;
    if (sep) {
        out[o] = '\\';
        o += 1;
    }
    str.copy(out[o..], name);
    return out[0..need];
}

// Join `dir` and "probe.tmp" with the platform separator (not pathJoin83,
// which hardcodes the Win98 backslash).
fn probePath(dir: []const u8, out: []u8) ?[]u8 {
    const name = "probe.tmp";
    var sep: u8 = '/';
    if (@isWindows()) sep = '\\';

    var add_sep = false;
    if (dir.len > 0) {
        const last = dir[dir.len - 1];
        if (last != '\\' and last != '/') add_sep = true;
    }

    var need: usize = dir.len + name.len;
    if (add_sep) need += 1;
    if (need > out.len) return null;

    str.copy(out, dir);
    var o: usize = dir.len;
    if (add_sep) {
        out[o] = sep;
        o += 1;
    }
    str.copy(out[o..], name);
    return out[0..need];
}

fn ensureDir(path: []const u8) void {
    var cbuf: [512]u8 = undefined;
    if (path.len + 1 > cbuf.len) return;
    str.copy(cbuf[0..], path);
    cbuf[path.len] = 0;
    if (@isWindows()) {
        _ = CreateDirectoryA(@ptrCast([*]const u8, &cbuf[0]), nullVoid());
    } else {
        _ = mkdir(@ptrCast([*]const u8, &cbuf[0]), 493);
    }
}

fn dotDir(out: []u8) []u8 {
    if (out.len == 0) return out[0..0];
    out[0] = '.';
    return out[0..1];
}

// Exe directory (no trailing separator). modulePath is null on POSIX, so the
// native fallback is the current directory.
pub fn resolveDataDir(out: []u8) []u8 {
    const mp = os.modulePath(out) orelse return dotDir(out);
    var i: usize = mp.len;
    while (i > 0) {
        i -= 1;
        if (mp[i] == '\\' or mp[i] == '/') return mp[0..i];
    }
    return dotDir(out);
}

// Create+write+close+delete probe.tmp in `dir`; true only when create and
// delete both succeed. A failed write still attempts to remove the file, so no
// residue is left behind on any reachable path.
pub fn probeWritable(dir: []const u8) bool {
    var pbuf: [4096]u8 = undefined;
    const path = probePath(dir, pbuf[0..]) orelse return false;

    var one: [1]u8 = undefined;
    one[0] = 1;
    var created = true;
    file_mod.writeAll(path, one[0..]) catch {
        created = false;
    };

    if (created) {
        file_mod.remove(path) catch return false;
        return true;
    }

    if (file_mod.exists(path)) {
        file_mod.remove(path) catch return false;
    }
    return false;
}

// Exe dir when writable, else the platform temp fallback (created here).
// Mutable files only go to this directory; data.z98 stays beside the exe.
pub fn dataDirOrFallback(out: []u8) []u8 {
    const exe_dir = resolveDataDir(out);
    if (probeWritable(exe_dir)) return exe_dir;

    var fb: []const u8 = FALLBACK_POSIX;
    if (@isWindows()) fb = FALLBACK_WIN;
    ensureDir(fb);

    if (fb.len > out.len) return out[0..0];
    str.copy(out, fb);
    return out[0..fb.len];
}
