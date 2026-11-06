// stdlib_page_modern_xmod — STDLIB std_page (L1) `modern`/auto-with-callback
// GREEN fixture (Linux-only; the Win9x cross-build excludes it because it
// needs a real madvise).
//
// Contract (Phase 3.1 Layer 1): `.modern` decommits via the caller-supplied
// callback (`madvise(ptr, bytes, MADV_DONTNEED=4)`) and commits via mprotect;
// `.auto` resolves to modern when the callback is non-null. pageInit with
// `.modern` and a null callback returns error.InvalidConfig. The reserved
// address stays stable and the range is reusable after decommit/recommit.
//
// GREEN (contract): deterministic byte-exact stdout `page modern ok\n`
// (RUNRC=0).
const std = @import("std");

extern "c" fn madvise(addr: *void, len: usize, advice: i32) i32;

var g_madvise_calls: u32 = 0;

fn shim(p: *void, n: usize, advice: i32) i32 {
    g_madvise_calls += 1;
    return madvise(p, n, advice);
}

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn run(mode: std.page.PosixMode, what: []const u8) void {
    const page = std.page;
    const two: usize = page.PAGE_SIZE * 2;

    var cfg = page.pageConfigDefault();
    cfg.posix_mode = mode;
    cfg.madvise_fn = shim;
    var a = page.pageInit(cfg) catch {
        @panic(what);
    };

    var r: [*]u8 = page.pageReserve(&a, two) orelse @panic(what);
    const addr: usize = @ptrToInt(r);

    ck(page.pageCommit(&a, r, two), what);
    r[0] = 0xA5;
    r[page.PAGE_SIZE] = 0xA5;
    ck(r[0] == 0xA5, what);
    ck(r[page.PAGE_SIZE] == 0xA5, what);

    const calls_before: u32 = g_madvise_calls;
    ck(page.pageDecommit(&a, r, two), what);
    ck(g_madvise_calls == calls_before + 1, what);
    ck(page.pageCommit(&a, r, two), what);
    ck(@ptrToInt(r) == addr, what);

    // MADV_DONTNEED discards anonymous-private page contents; the recommitted
    // mapping is at the same address and reads back zero before fresh writes.
    ck(r[0] == 0, what);
    ck(r[page.PAGE_SIZE] == 0, what);
    r[0] = 0x3C;
    r[page.PAGE_SIZE] = 0xC3;
    ck(r[0] == 0x3C, what);
    ck(r[page.PAGE_SIZE] == 0xC3, what);

    page.pageRelease(&a, r, two);
}

fn modernMissingCallback() bool {
    var cfg = std.page.pageConfigDefault();
    cfg.posix_mode = .modern;
    cfg.madvise_fn = null;
    var saw: bool = false;
    var a = std.page.pageInit(cfg) catch |e| {
        saw = e == error.InvalidConfig;
        return saw;
    };
    _ = a;
    return saw;
}

pub fn main() void {
    run(.modern, "modern page cycle");
    run(.auto, "auto resolves to modern");

    ck(modernMissingCallback(), "modern with null callback -> InvalidConfig");

    if (g_fail == 0) {
        std.io.write("page modern ok\n");
    } else {
        std.io.write("page modern FAIL\n");
    }
}
