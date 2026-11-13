const io = @import("std_io");
const os = @import("std_os");
const crypto = @import("std_crypto.zig");
const file_mod = @import("std_file");
const paths = @import("../paths.zig");

@cInclude("<unistd.h>");
@cInclude("<sys/stat.h>");

// POSIX-only test setup (the driver runs natively on Linux). The win32 build
// evidence for std_os.modulePath is a separate probe, not this driver.
extern "c" fn mkdir(path: [*]const u8, mode: u32) i32;
extern "c" fn chmod(path: [*]const u8, mode: u32) i32;
extern "c" fn rmdir(path: [*]const u8) i32;
extern "c" fn chdir(path: [*]const u8) i32;
extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*]u8;

var fails: usize = 0;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn crcStream(data: []const u8) u32 {
    var c = crypto.crc32Init();
    c = crypto.crc32Update(c, data);
    return crypto.crc32Final(c);
}

fn fillMsg(msg: []u8) void {
    var i: usize = 0;
    while (i < msg.len) : (i += 1) {
        msg[i] = @intCast(u8, i % 256);
    }
}

fn tCrcVectors() bool {
    if (crypto.crc32("123456789") != 0xCBF43926) return false;
    if (crypto.crc32("") != 0x00000000) return false;
    var msg: [200]u8 = undefined;
    fillMsg(msg[0..]);
    if (crypto.crc32(msg[0..]) != 0xED086180) return false;
    return true;
}

fn tCrcStreamingEqual() bool {
    if (crypto.crc32("123456789") != crcStream("123456789")) return false;
    if (crypto.crc32("") != crcStream("")) return false;

    var msg: [200]u8 = undefined;
    fillMsg(msg[0..]);

    var c = crypto.crc32Init();
    var i: usize = 0;
    while (i < msg.len) {
        var end: usize = i + 7;
        if (end > msg.len) end = msg.len;
        c = crypto.crc32Update(c, msg[i..end]);
        i = end;
    }
    if (crypto.crc32(msg[0..]) != crypto.crc32Final(c)) return false;
    return true;
}

fn tIs83() bool {
    if (!paths.is83Name("bg_a.zsp")) return false;
    if (paths.is83Name("fig_mermaid.zsp")) return false;
    if (paths.is83Name("BG_A.ZSP")) return false;
    if (paths.is83Name("a b.zsp")) return false;
    if (!paths.is83Name("eel00")) return false;
    if (!paths.is83Name("font8x16")) return false;
    if (!paths.is83Name("a")) return false;
    if (paths.is83Name("")) return false;
    if (paths.is83Name(".zsp")) return false;
    if (paths.is83Name("bg_a.")) return false;
    if (paths.is83Name("bg_a.toolong")) return false;
    return true;
}

fn tPathJoin() bool {
    var out: [64]u8 = undefined;

    const p = paths.pathJoin83("data", "bg_a.zsp", out[0..]) orelse return false;
    if (!eq(p, "data\\bg_a.zsp")) return false;

    const p2 = paths.pathJoin83("data\\", "bg_a.zsp", out[0..]) orelse return false;
    if (!eq(p2, "data\\bg_a.zsp")) return false;

    const p3 = paths.pathJoin83("", "bg_a.zsp", out[0..]) orelse return false;
    if (!eq(p3, "bg_a.zsp")) return false;

    var tiny: [12]u8 = undefined;
    if (paths.pathJoin83("data", "bg_a.zsp", tiny[0..]) != null) return false;

    var exact: [13]u8 = undefined;
    const pe = paths.pathJoin83("data", "bg_a.zsp", exact[0..]) orelse return false;
    if (!eq(pe, "data\\bg_a.zsp")) return false;

    if (paths.pathJoin83("data", "BAD.ZSP", out[0..]) != null) return false;
    if (paths.pathJoin83("data", "fig_mermaid.zsp", out[0..]) != null) return false;
    return true;
}

fn cstr(dst: []u8, s: []const u8) bool {
    if (s.len + 1 > dst.len) return false;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        dst[i] = s[i];
    }
    dst[s.len] = 0;
    return true;
}

fn makeDir(path: []const u8, mode: u32) bool {
    var b: [512]u8 = undefined;
    if (!cstr(b[0..], path)) return false;
    return mkdir(@ptrCast([*]const u8, &b[0]), mode) == 0;
}

fn chmodPath(path: []const u8, mode: u32) bool {
    var b: [512]u8 = undefined;
    if (!cstr(b[0..], path)) return false;
    return chmod(@ptrCast([*]const u8, &b[0]), mode) == 0;
}

fn removeDir(path: []const u8) bool {
    var b: [512]u8 = undefined;
    if (!cstr(b[0..], path)) return false;
    return rmdir(@ptrCast([*]const u8, &b[0])) == 0;
}

fn changeDir(path: []const u8) bool {
    var b: [512]u8 = undefined;
    if (!cstr(b[0..], path)) return false;
    return chdir(@ptrCast([*]const u8, &b[0])) == 0;
}

fn changeDirZ(path: [*]const u8) bool {
    return chdir(path) == 0;
}

fn probeTmpPath(dir: []const u8, out: []u8) ?[]u8 {
    const name: []const u8 = "/probe.tmp";
    const need = dir.len + name.len;
    if (need > out.len) return null;
    var i: usize = 0;
    while (i < dir.len) : (i += 1) {
        out[i] = dir[i];
    }
    var j: usize = 0;
    while (j < name.len) : (j += 1) {
        out[dir.len + j] = name[j];
    }
    return out[0..need];
}

fn tProbeWritable() bool {
    if (@isWindows()) return true;

    const okdir = "/tmp/m1_t5/probe_ok_dir";
    const badir = "/tmp/m1_t5/probe_bad_dir";

    _ = chmodPath(okdir, 493);
    _ = removeDir(okdir);
    if (!makeDir(okdir, 493)) return false;
    if (!paths.probeWritable(okdir)) return false;

    var pbuf: [512]u8 = undefined;
    const okp = probeTmpPath(okdir, pbuf[0..]) orelse return false;
    if (file_mod.exists(okp)) return false;
    if (!removeDir(okdir)) return false;

    _ = chmodPath(badir, 493);
    _ = removeDir(badir);
    if (!makeDir(badir, 493)) return false;
    if (!chmodPath(badir, 365)) return false;
    if (paths.probeWritable(badir)) return false;

    const badp = probeTmpPath(badir, pbuf[0..]) orelse return false;
    if (file_mod.exists(badp)) return false;

    _ = chmodPath(badir, 493);
    return removeDir(badir);
}

fn tFallbackConstants() bool {
    if (!eq(paths.FALLBACK_WIN, "C:\\WINDOWS\\TEMP\\UNDERSAN\\")) return false;
    if (!eq(paths.FALLBACK_POSIX, "/tmp/UNDERSAN")) return false;
    return true;
}

fn tResolveDataDirNative() bool {
    if (@isWindows()) return true;
    var out: [512]u8 = undefined;
    const d = paths.resolveDataDir(out[0..]);
    return eq(d, ".");
}

fn tDataDirFallback() bool {
    if (@isWindows()) return true;

    const badir = "/tmp/m1_t5/fallback_bad_dir";
    _ = chmodPath(badir, 493);
    _ = removeDir(badir);
    if (!makeDir(badir, 493)) return false;
    if (!chmodPath(badir, 365)) return false;

    // Do not delete a pre-existing shared /tmp/UNDERSAN; only clean up the
    // directory if this run created it.
    const had_fb = file_mod.exists(paths.FALLBACK_POSIX);

    var cwdbuf: [1024]u8 = undefined;
    const got = getcwd(@ptrCast([*]u8, &cwdbuf[0]), cwdbuf.len);
    if (got == null) return false;

    if (!changeDir(badir)) return false;

    var out: [512]u8 = undefined;
    const d = paths.dataDirOrFallback(out[0..]);
    var ok = eq(d, paths.FALLBACK_POSIX);

    if (!changeDirZ(@ptrCast([*]const u8, &cwdbuf[0]))) ok = false;
    if (ok and !paths.probeWritable(paths.FALLBACK_POSIX)) ok = false;

    _ = chmodPath(badir, 493);
    _ = removeDir(badir);
    if (!had_fb) _ = removeDir(paths.FALLBACK_POSIX);
    return ok;
}

pub fn main() void {
    _ = makeDir("/tmp/m1_t5", 493);

    report("crc32_known_vectors", tCrcVectors());
    report("crc32_streaming_equal", tCrcStreamingEqual());
    report("is83_name", tIs83());
    report("path_join83", tPathJoin());
    report("probe_writable", tProbeWritable());
    report("fallback_constants", tFallbackConstants());
    report("resolve_data_dir_native", tResolveDataDirNative());
    report("data_dir_fallback", tDataDirFallback());

    if (fails != 0) os.exit(1);
    io.write("paths_test PASS\n");
}
