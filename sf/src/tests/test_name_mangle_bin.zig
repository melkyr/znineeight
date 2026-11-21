const pal = @import("../pal.zig");
const StringInterner = @import("../string_interner.zig").StringInterner;
const interner_mod = @import("../string_interner.zig");
const Sand = @import("../allocator.zig").Sand;
const alloc_mod = @import("../allocator.zig");
const c89_mod = @import("../c89_emit.zig");

fn report(pfx: []const u8, msg: []const u8) void {
    pal.stderr_write(pfx);
    pal.stderr_write(msg);
    var n: []const u8 = "\n";
    pal.stderr_write(n);
}

fn failInt(exp: u32, got: u32, test_name: []const u8) void {
    var p: []const u8 = "FAIL: ";
    var col: []const u8 = " (expected ";
    var comma: []const u8 = " got ";
    report(p, test_name);
}

fn ok(test_name: []const u8) void {
    var p: []const u8 = "  ok ";
    report(p, test_name);
}

fn testMangle(interner: *StringInterner, mangler: *c89_mod.NameMangler, name_str: []const u8, kind: u8, mod_id: u32) u32 {
    var name_id = interner_mod.stringInternerIntern(interner, name_str);
    return c89_mod.nameManglerMangle(mangler, name_id, kind, mod_id);
}

pub fn main() void {
    pal.initArgs(@intCast(i32, 0), undefined);
    var sa: []const u8 = "start\n";
    pal.stderr_write(sa);
    var arena_buf: [131072]u8 = undefined;
    var arena = alloc_mod.sandInit(arena_buf[0..]);
    var interner = interner_mod.stringInternerInit(&arena, 4);
    var mangler = c89_mod.nameManglerInit(&interner, &arena, @intCast(usize, 64));

    var fn_foo: []const u8 = "foo";
    var fn_bar: []const u8 = "bar";
    var kw_ret: []const u8 = "return";
    var tmp_str: []const u8 = "__tmp_test";
    var long_str: []const u8 = "veryLongFunctionNameThatExceedsThirtyOneCharacters";
    var gv_str: []const u8 = "globalVar";
    var mt_str: []const u8 = "MyType";
    var lv_str: []const u8 = "localVar";

    var s01: []const u8 = "foo (Function)";
    var s02: []const u8 = "foo deterministic";
    var s03: []const u8 = "bar unique from foo";
    var s04: []const u8 = "return (keyword)";
    var s05: []const u8 = "__tmp_ passthrough";
    var s06: []const u8 = "long name (31-char truncation)";
    var s07: []const u8 = "globalVar (Global)";
    var s08: []const u8 = "MyType (Type)";
    var s09: []const u8 = "localVar (Local)";
    var s10: []const u8 = "foo in module 42 unique from module 0";
    var s11: []const u8 = "foo in module 42 deterministic";

    var tmp_id = interner_mod.stringInternerIntern(&interner, tmp_str);
    var long_id = interner_mod.stringInternerIntern(&interner, long_str);

    var id1 = testMangle(&interner, &mangler, fn_foo, @intCast(u8, 0), @intCast(u32, 0));
    if (id1 == @intCast(u32, 0)) { var m: []const u8 = "mangle foo returned 0"; report(m, s01); pal.exit(1); }
    ok(s01);

    var id2 = testMangle(&interner, &mangler, fn_foo, @intCast(u8, 0), @intCast(u32, 0));
    if (id2 != id1) { var m: []const u8 = "mangle foo not deterministic"; report(m, s02); pal.exit(1); }
    ok(s02);

    var id3 = testMangle(&interner, &mangler, fn_bar, @intCast(u8, 0), @intCast(u32, 0));
    if (id3 == @intCast(u32, 0)) { var m: []const u8 = "mangle bar returned 0"; report(m, s03); pal.exit(1); }
    if (id3 == id1) { var m: []const u8 = "mangle bar collides with foo"; report(m, s03); pal.exit(1); }
    ok(s03);

    var id4 = testMangle(&interner, &mangler, kw_ret, @intCast(u8, 0), @intCast(u32, 0));
    if (id4 == @intCast(u32, 0)) { var m: []const u8 = "mangle return (keyword) returned 0"; report(m, s04); pal.exit(1); }
    ok(s04);

    var id5 = c89_mod.nameManglerMangle(&mangler, tmp_id, @intCast(u8, 0), @intCast(u32, 0));
    if (id5 != tmp_id) { var m: []const u8 = "mangle __tmp_ prefix not passed through"; report(m, s05); pal.exit(1); }
    ok(s05);

    var id6 = c89_mod.nameManglerMangle(&mangler, long_id, @intCast(u8, 0), @intCast(u32, 0));
    if (id6 == @intCast(u32, 0)) { var m: []const u8 = "mangle long name returned 0"; report(m, s06); pal.exit(1); }
    ok(s06);

    var id7 = testMangle(&interner, &mangler, gv_str, @intCast(u8, 1), @intCast(u32, 0));
    if (id7 == @intCast(u32, 0)) { var m: []const u8 = "mangle globalVar returned 0"; report(m, s07); pal.exit(1); }
    ok(s07);

    var id8 = testMangle(&interner, &mangler, mt_str, @intCast(u8, 2), @intCast(u32, 0));
    if (id8 == @intCast(u32, 0)) { var m: []const u8 = "mangle MyType returned 0"; report(m, s08); pal.exit(1); }
    ok(s08);

    var id9 = testMangle(&interner, &mangler, lv_str, @intCast(u8, 3), @intCast(u32, 0));
    if (id9 == @intCast(u32, 0)) { var m: []const u8 = "mangle localVar returned 0"; report(m, s09); pal.exit(1); }
    ok(s09);

    var id10 = testMangle(&interner, &mangler, fn_foo, @intCast(u8, 0), @intCast(u32, 42));
    if (id10 == @intCast(u32, 0)) { var m: []const u8 = "mangle foo mod42 returned 0"; report(m, s10); pal.exit(1); }
    if (id10 == id1) { var m: []const u8 = "mangle foo in mod42 collides with mod0"; report(m, s10); pal.exit(1); }
    ok(s10);

    var id11 = testMangle(&interner, &mangler, fn_foo, @intCast(u8, 0), @intCast(u32, 42));
    if (id11 != id10) { var m: []const u8 = "mangle foo in mod42 not deterministic"; report(m, s11); pal.exit(1); }
    ok(s11);

    var s12: []const u8 = "cross-module collision: same name diff modules get _1";
    var s13: []const u8 = "cross-module collision: 3rd module gets _2";
    var s14: []const u8 = "truncation: mangled name <= 31 chars";

    var id12a = testMangle(&interner, &mangler, fn_bar, @intCast(u8, 0), @intCast(u32, 1));
    var id12b = testMangle(&interner, &mangler, fn_bar, @intCast(u8, 0), @intCast(u32, 2));
    if (id12a == @intCast(u32, 0)) { var m: []const u8 = "bar mod1 returned 0"; report(m, s12); pal.exit(1); }
    if (id12b == @intCast(u32, 0)) { var m: []const u8 = "bar mod2 returned 0"; report(m, s12); pal.exit(1); }
    if (id12a == id3) { var m: []const u8 = "bar mod1 collides with bar mod0"; report(m, s12); pal.exit(1); }
    if (id12b == id3) { var m: []const u8 = "bar mod2 collides with bar mod0"; report(m, s12); pal.exit(1); }
    if (id12b == id12a) { var m: []const u8 = "bar mod2 collides with bar mod1"; report(m, s13); pal.exit(1); }
    ok(s12);
    ok(s13);

    var id12a2 = testMangle(&interner, &mangler, fn_bar, @intCast(u8, 0), @intCast(u32, 1));
    var id12b2 = testMangle(&interner, &mangler, fn_bar, @intCast(u8, 0), @intCast(u32, 2));
    if (id12a2 != id12a) { var m: []const u8 = "bar mod1 not deterministic"; report(m, s12); pal.exit(1); }
    if (id12b2 != id12b) { var m: []const u8 = "bar mod2 not deterministic"; report(m, s13); pal.exit(1); }

    var id14 = c89_mod.nameManglerMangle(&mangler, long_id, @intCast(u8, 0), @intCast(u32, 0));
    var mangled_name = interner_mod.stringInternerGet(&interner, id14);
    if (mangled_name.len > @intCast(usize, 31)) {
        var m: []const u8 = "mangled name exceeds 31 chars";
        report(m, s14);
        pal.exit(1);
    }
    ok(s14);

    var end: []const u8 = "NameMangle tests passed.\n";
    pal.stderr_write(end);
}
