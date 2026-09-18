// stdlib_str_join_xmod — std_str.join (L2) GREEN fixture.
//
// Contract (blueprint §3 L2): `join(arena, parts, sep) ![]u8` concatenates the
// parts with `sep` between consecutive parts and allocates the result. An empty
// `parts` slice yields an empty result; `sep` may be empty.
//
// Cases pinned:
//   ["a","b","c"] sep ","   -> "a,b,c"
//   ["a"]         sep ","   -> "a"       (no separator for one part)
//   []            sep ","   -> ""        (len 0)
//   ["",""]       sep "-"   -> "-"
//   ["ab","cd"]   sep ""    -> "abcd"
//   ["a","bb","c"] sep "--" -> "a--bb--c"
//
// The input parts arrays are built through an arena-backed `[*][]const u8`
// (rather than `[N][]const u8 = undefined`, whose -ffast zero-fill emits an
// invalid slice store today) so the fixture builds cleanly in every mode.
//
// GREEN (contract): deterministic byte-exact stdout `str join ok\n`.
const std = @import("std");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.str.eql(a, b);
}

fn parts0(ar: *std.arena.Arena) [][]const u8 {
    var raw = std.arena.alloc(ar, 0) catch {
        @panic("parts0 alloc");
    };
    var p: [*][]const u8 = @ptrCast([*][]const u8, raw);
    return p[0..0];
}

fn parts1(ar: *std.arena.Arena, a: []const u8) [][]const u8 {
    var raw = std.arena.alloc(ar, @sizeOf([]const u8)) catch {
        @panic("parts1 alloc");
    };
    var p: [*][]const u8 = @ptrCast([*][]const u8, raw);
    p[0] = a;
    return p[0..1];
}

fn parts2(ar: *std.arena.Arena, a: []const u8, b: []const u8) [][]const u8 {
    var raw = std.arena.alloc(ar, 2 * @sizeOf([]const u8)) catch {
        @panic("parts2 alloc");
    };
    var p: [*][]const u8 = @ptrCast([*][]const u8, raw);
    p[0] = a;
    p[1] = b;
    return p[0..2];
}

fn parts3(ar: *std.arena.Arena, a: []const u8, b: []const u8, c: []const u8) [][]const u8 {
    var raw = std.arena.alloc(ar, 3 * @sizeOf([]const u8)) catch {
        @panic("parts3 alloc");
    };
    var p: [*][]const u8 = @ptrCast([*][]const u8, raw);
    p[0] = a;
    p[1] = b;
    p[2] = c;
    return p[0..3];
}

pub fn main() void {
    var backing: [1024]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    var sep: []const u8 = ",";

    var j1 = std.str.join(&ar, parts3(&ar, "a", "b", "c"), sep) catch {
        @panic("join abc");
    };
    ck(eq(j1, "a,b,c"), "a,b,c");

    var j2 = std.str.join(&ar, parts1(&ar, "a"), sep) catch {
        @panic("join one");
    };
    ck(eq(j2, "a"), "single");

    var j3 = std.str.join(&ar, parts0(&ar), sep) catch {
        @panic("join empty");
    };
    ck(j3.len == 0, "empty len");

    var dash: []const u8 = "-";
    var j4 = std.str.join(&ar, parts2(&ar, "", ""), dash) catch {
        @panic("join empties");
    };
    ck(eq(j4, "-"), "two empties");

    var none: []const u8 = "";
    var j5 = std.str.join(&ar, parts2(&ar, "ab", "cd"), none) catch {
        @panic("join no sep");
    };
    ck(eq(j5, "abcd"), "empty sep");

    var dd: []const u8 = "--";
    var j6 = std.str.join(&ar, parts3(&ar, "a", "bb", "c"), dd) catch {
        @panic("join multibyte sep");
    };
    ck(eq(j6, "a--bb--c"), "multibyte sep");

    std.io.write("str join ok\n");
}
