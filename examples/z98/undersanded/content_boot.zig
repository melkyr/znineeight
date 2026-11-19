// content_boot.zig — shared data.z98 startup sequence (spec §25.10, §32, §33).
//
// Resolves data.z98 beside the exe dir, loads/validates it, and installs the
// static override. Both game entries and the tool paths call this; the copy
// strings live here so the startup fatal path and its native tests agree.

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const io = @import("std_io.zig");
const parse = @import("std_parse");
const def = @import("def.zig");
const data = @import("data.zig");
const validate = @import("validate.zig");

pub const MSG_MISSING: []const u8 = "Content file missing. Reinstall from CD.";
pub const MSG_DAMAGED_PREFIX: []const u8 = "Content file is damaged at line ";
pub const MSG_DAMAGED_SUFFIX: []const u8 = ". Reinstall from CD.";

pub const BootResult = enum { Loaded, Missing, Damaged };

pub const Boot = struct { result: BootResult, line: i32 };

fn joinPath(dir: []const u8, name: []const u8, out: []u8) ?[]u8 {
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

    var o: usize = 0;
    var i: usize = 0;
    while (i < dir.len) : (i += 1) {
        out[o] = dir[i];
        o += 1;
    }
    if (add_sep) {
        out[o] = sep;
        o += 1;
    }
    i = 0;
    while (i < name.len) : (i += 1) {
        out[o] = name[i];
        o += 1;
    }
    return out[0..need];
}

fn append(dst: []u8, at: *usize, s: []const u8) void {
    var i: usize = 0;
    while (i < s.len and at.* < dst.len) : (i += 1) {
        dst[at.*] = s[i];
        at.* += 1;
    }
}

fn normalizedLine(line: i32) i32 {
    if (line > 0) return line;
    return 1;
}

// Dedicated boot-failure emission: CUI gets one line on stdout, GUI one line
// on stderr. Unlike app.fail(), never repeats across streams.
pub fn writeFailure(console_mode: bool, msg: []const u8) void {
    if (console_mode) {
        io.write(msg);
        io.write("\n");
    } else {
        @stderrWrite(msg.ptr, msg.len);
        @stderrWrite("\n", 1);
    }
}

pub fn damagedText(line: i32, out: []u8) []const u8 {
    var at: usize = 0;
    append(out, &at, MSG_DAMAGED_PREFIX);
    var ibuf: [16]u8 = undefined;
    const digits = parse.itoa(ibuf[0..], normalizedLine(line));
    append(out, &at, digits);
    append(out, &at, MSG_DAMAGED_SUFFIX);
    return out[0..at];
}

pub fn loadFromDir(arena: *arena_mod.Arena, tables: *def.Tables, dir: []const u8) Boot {
    var path_buf: [512]u8 = undefined;
    const path = joinPath(dir, "data.z98", path_buf[0..]) orelse {
        return Boot{ .result = BootResult.Missing, .line = 0 };
    };
    if (!file_mod.exists(path)) {
        return Boot{ .result = BootResult.Missing, .line = 0 };
    }

    data.loadFile(arena, path, tables) catch {
        return Boot{ .result = BootResult.Damaged, .line = normalizedLine(data.err_line) };
    };
    validate.validateAll(tables) catch {
        return Boot{ .result = BootResult.Damaged, .line = normalizedLine(data.err_line) };
    };

    data.install(tables);
    return Boot{ .result = BootResult.Loaded, .line = 0 };
}
