// bind_test.zig — native Linux tests for M6 Task 5 game binding (§32/§33/§35).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/bind_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/bind_test"
//   "$OUT/bind_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const file_mod = @import("std_file");
const def = @import("../def.zig");
const data = @import("../data.zig");
const validate = @import("../validate.zig");
const creatures = @import("../creatures_t1.zig");
const tables = @import("../tables_t1.zig");
const paths = @import("../paths.zig");
const content_boot = @import("../content_boot.zig");

@cInclude("<unistd.h>");
@cInclude("<sys/stat.h>");

extern "c" fn mkdir(path: [*]const u8, mode: u32) i32;
extern "c" fn rmdir(path: [*]const u8) i32;
extern "c" fn chdir(path: [*]const u8) i32;
extern "c" fn open(path: [*]const u8, flags: i32, mode: u32) i32;
extern "c" fn dup2(oldfd: i32, newfd: i32) i32;
extern "c" fn close(fd: i32) i32;

const O_CREATE_WRITE_TRUNC: i32 = 577;
const FILE_MODE_0644: u32 = 420;

const DATA_PATH = "examples/z98/undersanded/data.z98";
const TMP_DIR = "/tmp/m6t5_bind";
const MISSING_DIR = "/tmp/m6t5_bind/missing";
const DAMAGED_DIR = "/tmp/m6t5_bind/damaged";
const TMP_CHANGED = "/tmp/m6t5_bind/changed.z98";
const EMIT_OUT = "/tmp/m6t5_bind/emit.out";
const EMIT_ERR = "/tmp/m6t5_bind/emit.err";
const MISSING_MSG = "Content file missing. Reinstall from CD.";
const DAMAGED_MSG = "Content file is damaged at line 3. Reinstall from CD.";

var fails: usize = 0;
var shipped_buf: [256 * 1024]u8 = undefined;
var temp_buf: [256 * 1024]u8 = undefined;
var boot_buf: [256 * 1024]u8 = undefined;
var emit_buf: [4096]u8 = undefined;

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

fn cstr(dst: []u8, s: []const u8) bool {
    if (s.len + 1 > dst.len) return false;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        dst[i] = s[i];
    }
    dst[s.len] = 0;
    return true;
}

fn makeDir(path: []const u8) bool {
    var b: [512]u8 = undefined;
    if (!cstr(b[0..], path)) return false;
    return mkdir(@ptrCast([*]const u8, &b[0]), 493) == 0;
}

fn removeDir(path: []const u8) void {
    var b: [512]u8 = undefined;
    if (!cstr(b[0..], path)) return;
    _ = rmdir(@ptrCast([*]const u8, &b[0]));
}

fn changeDir(path: []const u8) bool {
    var b: [512]u8 = undefined;
    if (!cstr(b[0..], path)) return false;
    return chdir(@ptrCast([*]const u8, &b[0])) == 0;
}

fn findSub(buf: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (buf.len < needle.len) return null;
    var i: usize = 0;
    while (i + needle.len <= buf.len) : (i += 1) {
        var k: usize = 0;
        var same: bool = true;
        while (k < needle.len) : (k += 1) {
            if (buf[i + k] != needle[k]) {
                same = false;
                break;
            }
        }
        if (same) return i;
    }
    return null;
}

fn replaceOnce(buf: []u8, needle: []const u8, repl: []const u8) bool {
    if (needle.len != repl.len) return false;
    const at = findSub(buf, needle) orelse return false;
    var i: usize = 0;
    while (i < repl.len) : (i += 1) {
        buf[at + i] = repl[i];
    }
    return true;
}

fn tShippedLoadValidateInstall() bool {
    data.uninstall();
    var arena = arena_mod.init(shipped_buf[0..]);
    data.loadFile(&arena, DATA_PATH, &data.g_tables) catch return false;
    validate.validateAll(&data.g_tables) catch return false;
    data.install(&data.g_tables);

    if (creatures.defCount() != 18) return false;
    if (creatures.defAt(0).id != 1) return false;
    if (creatures.defAt(0).hp != 70) return false;
    if (creatures.rules().len != 4) return false;
    if (tables.rows(0, 0).len != 5) return false;
    if (tables.rows(0, 0)[0].weight != 30) return false;
    if (tables.tools().len != 7) return false;
    if (tables.upgrades().len != 15) return false;
    if (tables.cosmetics().len != 12) return false;
    if (tables.zoneCost(0) != 1) return false;
    if (tables.zoneIsBoss(8) != 1) return false;

    data.uninstall();
    return true;
}

fn tTempOverrideVisible() bool {
    data.uninstall();
    var shipped = arena_mod.init(shipped_buf[0..]);
    data.loadFile(&shipped, DATA_PATH, &data.g_tables) catch return false;
    validate.validateAll(&data.g_tables) catch return false;
    data.install(&data.g_tables);

    var temp = arena_mod.init(temp_buf[0..]);
    const src = file_mod.readAll(&temp, DATA_PATH) catch return false;
    if (!replaceOnce(src, "hp=70,resolve=80", "hp=71,resolve=80")) return false;
    if (!replaceOnce(src, "sale=20,respawn_sub=3", "sale=21,respawn_sub=3")) return false;
    if (!replaceOnce(src, "def_index=0,weight=30", "def_index=0,weight=31")) return false;
    if (!replaceOnce(src, "id=1,kind=1,cost0_kind=2,cost0_amt=3",
        "id=1,kind=1,cost0_kind=2,cost0_amt=4"))
    {
        return false;
    }
    if (!replaceOnce(src, "id=0,cost=1,boss=0", "id=0,cost=2,boss=0")) return false;
    file_mod.writeAll(TMP_CHANGED, src) catch return false;

    data.loadFile(&temp, TMP_CHANGED, &data.g_tables) catch return false;
    data.install(&data.g_tables);

    if (creatures.defAt(0).hp != 71) return false;
    if (creatures.defAt(0).sale != 21) return false;
    if (tables.rows(0, 0)[0].weight != 31) return false;
    if (tables.tools()[0].cost[0].amt != 4) return false;
    if (tables.zoneCost(0) != 2) return false;

    data.uninstall();
    if (creatures.defAt(0).hp != 70) return false;
    if (creatures.defAt(0).sale != 20) return false;
    if (tables.rows(0, 0)[0].weight != 30) return false;
    if (tables.tools()[0].cost[0].amt != 3) return false;
    if (tables.zoneCost(0) != 1) return false;
    return true;
}

fn bootMissingFromCwd() content_boot.Boot {
    var arena = arena_mod.init(boot_buf[0..]);
    var dir_buf: [512]u8 = undefined;
    const dir = paths.resolveDataDir(dir_buf[0..]);
    return content_boot.loadFromDir(&arena, &data.g_tables, dir);
}

fn childExitIn(dir_path: []const u8) i32 {
    if (!changeDir(dir_path)) return -1;
    const pid = os.fork();
    if (pid == 0) {
        const boot = bootMissingFromCwd();
        if (boot.result == content_boot.BootResult.Loaded) os.exit(0);
        os.exit(1);
    }
    if (pid < 0) return -1;
    var status: i32 = 0;
    _ = os.waitpid(pid, &status, 0);
    return (status >> 8) & 255;
}

fn isOneLine(buf: []const u8, msg: []const u8) bool {
    if (buf.len != msg.len + 1) return false;
    var i: usize = 0;
    while (i < msg.len) : (i += 1) {
        if (buf[i] != msg[i]) return false;
    }
    return buf[msg.len] == '\n';
}

fn emitCapture(out_path: []const u8, err_path: []const u8, console_mode: bool, msg: []const u8) bool {
    _ = makeDir(TMP_DIR);
    const pid = os.fork();
    if (pid == 0) {
        var ob: [512]u8 = undefined;
        var eb: [512]u8 = undefined;
        if (!cstr(ob[0..], out_path) or !cstr(eb[0..], err_path)) os.exit(2);
        const ofd = open(@ptrCast([*]const u8, &ob[0]), O_CREATE_WRITE_TRUNC, FILE_MODE_0644);
        const efd = open(@ptrCast([*]const u8, &eb[0]), O_CREATE_WRITE_TRUNC, FILE_MODE_0644);
        if (ofd < 0 or efd < 0) os.exit(2);
        _ = dup2(ofd, 1);
        _ = dup2(efd, 2);
        _ = close(ofd);
        _ = close(efd);
        content_boot.writeFailure(console_mode, msg);
        os.exit(0);
    }
    if (pid < 0) return false;
    var status: i32 = 0;
    _ = os.waitpid(pid, &status, 0);
    if (((status >> 8) & 255) != 0) return false;

    var arena = arena_mod.init(emit_buf[0..]);
    const o = file_mod.readAll(&arena, out_path) catch return false;
    const e = file_mod.readAll(&arena, err_path) catch return false;
    if (console_mode) {
        if (!isOneLine(o, msg)) return false;
        if (e.len != 0) return false;
    } else {
        if (o.len != 0) return false;
        if (!isOneLine(e, msg)) return false;
    }
    return true;
}

fn tBootFailureSingleEmission() bool {
    if (!emitCapture(EMIT_OUT, EMIT_ERR, true, MISSING_MSG)) return false;
    var msg_buf: [80]u8 = undefined;
    const damaged = content_boot.damagedText(3, msg_buf[0..]);
    if (!emitCapture(EMIT_OUT, EMIT_ERR, true, damaged)) return false;
    if (!emitCapture(EMIT_OUT, EMIT_ERR, false, MISSING_MSG)) return false;
    return true;
}

fn tMissingCopyAndExit() bool {
    data.uninstall();
    _ = makeDir(TMP_DIR);
    _ = makeDir(MISSING_DIR);
    file_mod.remove("/tmp/m6t5_bind/missing/data.z98") catch {};

    if (!changeDir(MISSING_DIR)) return false;
    const boot = bootMissingFromCwd();
    if (boot.result != content_boot.BootResult.Missing) return false;
    if (!eq(content_boot.MSG_MISSING, MISSING_MSG)) return false;
    const code = childExitIn(MISSING_DIR);
    if (!changeDir("/tmp")) return false;
    if (code == 0 or code < 0) return false;
    return true;
}

fn tDamagedCopyAndLine() bool {
    data.uninstall();
    _ = makeDir(DAMAGED_DIR);
    const bad = "format=2\n[creatures]\nnot_a_row\n";
    file_mod.writeAll("/tmp/m6t5_bind/damaged/data.z98", bad) catch return false;

    if (!changeDir(DAMAGED_DIR)) return false;
    const boot = bootMissingFromCwd();
    if (boot.result != content_boot.BootResult.Damaged) return false;
    if (boot.line != 3) return false;
    var msg_buf: [80]u8 = undefined;
    if (!eq(content_boot.damagedText(boot.line, msg_buf[0..]), DAMAGED_MSG)) return false;
    const code = childExitIn(DAMAGED_DIR);
    if (!changeDir("/tmp")) return false;
    if (code == 0 or code < 0) return false;
    return true;
}

pub fn main() void {
    report("shipped_load_validate_install", tShippedLoadValidateInstall());
    report("temp_override_visible_then_uninstall", tTempOverrideVisible());
    report("boot_failure_single_emission", tBootFailureSingleEmission());
    report("startup_missing_copy_exit_nonzero", tMissingCopyAndExit());
    report("startup_damaged_copy_line_3", tDamagedCopyAndLine());

    data.uninstall();
    removeDir(DAMAGED_DIR);
    removeDir(MISSING_DIR);
    removeDir(TMP_DIR);

    if (fails != 0) os.exit(1);
    io.write("bind_test PASS\n");
}
