// stdlib_page_xmod — STDLIB std_page (L1) reserve/commit/decommit/release GREEN
// fixture.
//
// Contract (Phase 3.1 Layer 1): pageReserve rounds to RESERVE_GRANULARITY and
// returns null for 0 bytes; pageCommit/pageDecommit round to PAGE_SIZE and
// require a page-aligned pointer and a page-multiple length; a misaligned
// pointer (or a zero length) returns false. pageRelease(ptr, 0) is a no-op.
// The default (auto) allocator uses remap on POSIX; the protect allocator
// revokes access without returning pages. Both must keep the reserved address
// stable across decommit/recommit and the range reusable afterwards.
//
// GREEN (contract): deterministic byte-exact stdout `page ok\n` (RUNRC=0).
const std = @import("std");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    const page = std.page;
    const two: usize = page.PAGE_SIZE * 2;

    // --- default (auto) allocator: reserve/commit/write/decommit/recommit ---
    var cfg = page.pageConfigDefault();
    var a = page.pageInit(cfg) catch {
        @panic("page init auto");
    };
    var r1: [*]u8 = page.pageReserve(&a, two) orelse @panic("pageReserve auto");
    const addr1: usize = @ptrToInt(r1);

    ck(page.pageCommit(&a, r1, two), "pageCommit auto");
    r1[0] = 0xA5;
    r1[page.PAGE_SIZE] = 0xA5;
    ck(r1[0] == 0xA5, "read back auto page 0");
    ck(r1[page.PAGE_SIZE] == 0xA5, "read back auto page 1");

    ck(page.pageDecommit(&a, r1, two), "pageDecommit auto");
    ck(page.pageCommit(&a, r1, two), "pageCommit recommit auto");
    ck(@ptrToInt(r1) == addr1, "reserved address stable auto");
    r1[1] = 0x5A;
    ck(r1[1] == 0x5A, "range reusable after recommit auto");

    // --- pinned contracts ---
    ck(page.pageReserve(&a, 0) == null, "pageReserve(0) -> null");
    ck(!page.pageCommit(&a, r1, 0), "pageCommit(0) -> false");
    ck(!page.pageDecommit(&a, r1, 0), "pageDecommit(0) -> false");
    var misaligned: [*]u8 = @ptrCast([*]u8, @intToPtr(*void, @ptrToInt(r1) + 1));
    ck(!page.pageCommit(&a, misaligned, page.PAGE_SIZE), "misaligned pageCommit -> false");
    page.pageRelease(&a, r1, 0);
    r1[2] = 0x11;
    ck(r1[2] == 0x11, "pageRelease(ptr, 0) no-op");
    ck(!page.pageCommit(&a, r1, page.PAGE_SIZE + 1), "non-multiple pageCommit -> false");
    ck(!page.pageDecommit(&a, r1, page.PAGE_SIZE + 1), "non-multiple pageDecommit -> false");

    // --- protect allocator: same reserve/commit/decommit/recommit cycle ---
    var pcfg = page.pageConfigDefault();
    pcfg.posix_mode = .protect;
    var b = page.pageInit(pcfg) catch {
        @panic("page init protect");
    };
    var r2: [*]u8 = page.pageReserve(&b, two) orelse @panic("pageReserve protect");
    const addr2: usize = @ptrToInt(r2);

    ck(page.pageCommit(&b, r2, two), "pageCommit protect");
    r2[0] = 0x3C;
    r2[page.PAGE_SIZE] = 0x3C;
    ck(r2[0] == 0x3C, "read back protect page 0");
    ck(r2[page.PAGE_SIZE] == 0x3C, "read back protect page 1");

    ck(page.pageDecommit(&b, r2, two), "pageDecommit protect");
    ck(page.pageCommit(&b, r2, two), "pageCommit recommit protect");
    ck(@ptrToInt(r2) == addr2, "reserved address stable protect");
    r2[3] = 0x77;
    ck(r2[3] == 0x77, "range reusable after recommit protect");

    page.pageRelease(&a, r1, two);
    page.pageRelease(&b, r2, two);

    if (g_fail == 0) {
        std.io.write("page ok\n");
    } else {
        std.io.write("page FAIL\n");
    }
}
