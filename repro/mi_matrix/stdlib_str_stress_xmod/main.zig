// stdlib_str_stress_xmod — STDLIB std_str (L2) hand-written adversarial table.
//
// No PRNG: every input is an explicit table. Stresses:
//   - join(split(s, sep), sep) == s over adversarial separators: leading,
//     trailing, consecutive, all-separator, no-separator, empty, whitespace.
//   - long inputs (1024 bytes of mixed data; 512 all-separator bytes) with the
//     same identity.
//   - replace's aliasing contract: from/to alias the source; the result is a
//     fresh buffer and the source is left unmodified; non-overlapping,
//     leftmost-first deletion/growth.
//   - trim over all-whitespace (including the VT/FF bytes 11/12), mixed
//     whitespace, and interior-only whitespace.
//
// GREEN (contract): deterministic byte-exact stdout `str stress ok\n` (RUNRC=0).
const std = @import("std");

var g_backing: [65536]u8 = undefined;
var g_arena = std.arena.init(g_backing[0..]);
var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn roundtrip(s: []const u8, sep: u8) void {
    var parts = std.str.split(&g_arena, s, sep) catch {
        @panic("split");
    };
    ck(parts.len == std.str.count(s, sep) + 1, "split part count");
    var sb: [1]u8 = undefined;
    sb[0] = sep;
    var seps: []const u8 = sb[0..1];
    var joined = std.str.join(&g_arena, parts, seps) catch {
        @panic("join");
    };
    ck(std.str.eql(joined, s), "join(split(s, sep), sep) identity");
}

const SplitCase = struct { s: []const u8, sep: u8 };

pub fn main() void {
    // --- adversarial separator table ---------------------------------------
    var cases = [_]SplitCase{
        SplitCase{ .s = "", .sep = ',' },
        SplitCase{ .s = ",", .sep = ',' },
        SplitCase{ .s = ",,", .sep = ',' },
        SplitCase{ .s = ",,,", .sep = ',' },
        SplitCase{ .s = ",a", .sep = ',' },
        SplitCase{ .s = "a,", .sep = ',' },
        SplitCase{ .s = "a,,b", .sep = ',' },
        SplitCase{ .s = "a,b,c", .sep = ',' },
        SplitCase{ .s = ",a,b,", .sep = ',' },
        SplitCase{ .s = "aaaa", .sep = 'a' },
        SplitCase{ .s = "a", .sep = 'a' },
        SplitCase{ .s = "xyx", .sep = 'x' },
        SplitCase{ .s = "  ", .sep = ' ' },
        SplitCase{ .s = "a b  c", .sep = ' ' },
        SplitCase{ .s = " ", .sep = ' ' },
        SplitCase{ .s = "...x...", .sep = '.' },
        SplitCase{ .s = "abc", .sep = 'z' },
        SplitCase{ .s = "\t\n\r", .sep = '\n' },
    };
    var i: usize = 0;
    while (i < cases.len) : (i += 1) {
        roundtrip(cases[i].s, cases[i].sep);
    }

    // --- long mixed input (1024 bytes) --------------------------------------
    var longbuf: [1024]u8 = undefined;
    var li: usize = 0;
    while (li < 1024) : (li += 1) {
        if (li % 7 == 0) {
            longbuf[li] = ',';
        } else {
            longbuf[li] = 'a' + @intCast(u8, li % 26);
        }
    }
    roundtrip(longbuf[0..1024], ',');

    // --- long all-separator input (512 bytes) -------------------------------
    var sepsbuf: [512]u8 = undefined;
    var si: usize = 0;
    while (si < 512) : (si += 1) {
        sepsbuf[si] = ',';
    }
    roundtrip(sepsbuf[0..512], ',');

    // --- replace aliasing + non-overlap -------------------------------------
    var src: [16]u8 = undefined;
    std.str.copy(src[0..], "abcabcab");
    var ra = std.str.replace(&g_arena, src[0..8], src[0..3], src[6..8]) catch {
        @panic("replace alias");
    };
    ck(std.str.eql(ra, "ababab"), "replace alias result");
    ck(std.str.eql(src[0..8], "abcabcab"), "replace alias source unmodified");

    var s2: []const u8 = "aaaa";
    var r2 = std.str.replace(&g_arena, s2, "aa", "b") catch {
        @panic("replace nonoverlap even");
    };
    ck(std.str.eql(r2, "bb"), "replace nonoverlap even");

    var s3: []const u8 = "aaaaa";
    var r3 = std.str.replace(&g_arena, s3, "aa", "b") catch {
        @panic("replace nonoverlap odd");
    };
    ck(std.str.eql(r3, "bba"), "replace nonoverlap odd");

    var s4: []const u8 = "x";
    var r4 = std.str.replace(&g_arena, s4, "", "Q") catch {
        @panic("replace empty from");
    };
    ck(std.str.eql(r4, "x"), "replace empty from copy");

    // --- trim over whitespace ----------------------------------------------
    ck(std.str.trim("").len == 0, "trim empty");
    ck(std.str.trim("   ").len == 0, "trim spaces");
    ck(std.str.eql(std.str.trim("\t\n x \r\n"), "x"), "trim mixed around x");
    ck(std.str.eql(std.str.trim("  a b  "), "a b"), "trim interior kept");
    ck(std.str.eql(std.str.trim("x"), "x"), "trim no-op");

    var ws: [6]u8 = undefined;
    ws[0] = 9;
    ws[1] = 10;
    ws[2] = 11;
    ws[3] = 12;
    ws[4] = 13;
    ws[5] = 32;
    ck(std.str.trim(ws[0..]).len == 0, "trim all ASCII whitespace bytes");

    if (g_fail == 0) {
        std.io.write("str stress ok\n");
    } else {
        std.io.write("str stress FAIL\n");
    }
}
