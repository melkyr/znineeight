const io = @import("std_io");
const os = @import("std_os");
const crypto = @import("std_crypto.zig");
const paths = @import("../paths.zig");

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

pub fn main() void {
    report("crc32_known_vectors", tCrcVectors());
    report("crc32_streaming_equal", tCrcStreamingEqual());
    report("is83_name", tIs83());
    report("path_join83", tPathJoin());

    if (fails != 0) os.exit(1);
    io.write("paths_test PASS\n");
}
