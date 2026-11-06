// std_page.zig — Z98 std lib L1: portable page reserve/commit/decommit/release.
//
// Contract (Phase 3.1 Layer 1): std_page owns OS mappings only; callers own the
// ranges they reserve. POSIX specifics (mmap/mprotect/munmap and its constants)
// live in the std-side PAL std_page_pal.zig (R8); the compiler PAL is untouched.
// Per-OS C prototypes come from the header-only std_page_prelude.h.
//
// Modes:
//   auto    — Win9x/Win32 native; POSIX modern when madvise_fn != null else remap
//   remap   — decommit = munmap + mmap(MAP_FIXED, PROT_NONE); commit = mprotect
//   protect — decommit = mprotect(PROT_NONE); commit = mprotect(RW)
//   modern  — decommit = madvise_fn(ptr, bytes, 4); commit = mprotect; callback
//             is required (pageInit returns error.InvalidConfig when null)
// On Win32 every posix_mode resolves to the native VirtualAlloc/VirtualFree
// path. The resolved mode is fixed at init and read-only afterward.
//
// Pinned contracts: reserve rounds to RESERVE_GRANULARITY and returns null for
// 0 bytes; commit/decommit require a page-aligned pointer and a page-multiple
// length (anything else returns false) and reject 0 bytes; pageRelease(ptr, 0)
// is a no-op; Win32 pageRelease calls VirtualFree(ptr, 0, MEM_RELEASE) (size
// must be 0 and bytes is ignored), POSIX calls munmap(ptr, bytes). A failed
// remap/decommit returns false and the range may be left unmapped.

const pal = @import("std_page_pal.zig");

@cInclude("<std_page_prelude.h>");

pub const PosixMode = enum { auto, remap, protect, modern };

pub const PageConfig = struct {
    posix_mode: PosixMode,
    madvise_fn: ?fn (*void, usize, i32) i32,
};

pub const PageAllocator = struct {
    cfg: PageConfig,
    mode: u8,
};

pub const PageError = error{InvalidConfig};

pub const PAGE_SIZE: usize = 4096;
pub const RESERVE_GRANULARITY: usize = 65536;

const MODE_NATIVE: u8 = 0;
const MODE_REMAP: u8 = 1;
const MODE_PROTECT: u8 = 2;
const MODE_MODERN: u8 = 3;

// MADV_DONTNEED (Linux ABI). Passed to the caller-supplied madvise callback.
const MADV_DONTNEED: i32 = 4;

// Round value up to unit using a u64 intermediate; return null when the result
// cannot fit a 32-bit address space (the z9git bytes64 guard pattern).
fn roundUp(value: usize, unit: usize) ?usize {
    const v: u64 = @intCast(u64, value);
    const u: u64 = @intCast(u64, unit);
    const sum: u64 = v + u - @intCast(u64, 1);
    if (sum > @intCast(u64, 0xFFFFFFFF)) return null;
    return @intCast(usize, sum / u * u);
}

fn pageAligned(ptr: [*]u8) bool {
    return @ptrToInt(ptr) % PAGE_SIZE == 0;
}

// The null `void*` VirtualAlloc's reserved-address argument needs (Z98 `null`
// is optional-only; same construction z9git/std_os use).
fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

pub fn pageConfigDefault() PageConfig {
    return PageConfig{ .posix_mode = .auto, .madvise_fn = null };
}

pub fn pageInit(cfg: PageConfig) PageError!PageAllocator {
    var mode: u8 = MODE_NATIVE;
    if (!@isWindows()) {
        if (cfg.posix_mode == .auto) {
            if (cfg.madvise_fn != null) {
                mode = MODE_MODERN;
            } else {
                mode = MODE_REMAP;
            }
        } else if (cfg.posix_mode == .remap) {
            mode = MODE_REMAP;
        } else if (cfg.posix_mode == .protect) {
            mode = MODE_PROTECT;
        } else {
            if (cfg.madvise_fn == null) return error.InvalidConfig;
            mode = MODE_MODERN;
        }
    }
    return PageAllocator{ .cfg = cfg, .mode = mode };
}

pub fn pageReserve(self: *PageAllocator, bytes: usize) ?[*]u8 {
    _ = self;
    if (bytes == 0) return null;
    const n: usize = roundUp(bytes, RESERVE_GRANULARITY) orelse return null;
    if (@isWindows()) {
        const raw = pal.VirtualAlloc(nullVoid(), n, pal.MEM_RESERVE, pal.PAGE_NOACCESS);
        if (@ptrToInt(raw) == 0) return null;
        return @ptrCast([*]u8, raw);
    }
    const raw = pal.mmap(null, n, pal.PROT_NONE, pal.MAP_PRIVATE | pal.MAP_ANON, -1, 0);
    if (@ptrToInt(raw) >= 0xFFFFF000) return null;
    return @ptrCast([*]u8, raw);
}

pub fn pageCommit(self: *PageAllocator, ptr: [*]u8, bytes: usize) bool {
    _ = self;
    if (bytes == 0) return false;
    if (!pageAligned(ptr)) return false;
    if (bytes % PAGE_SIZE != 0) return false;
    if (@isWindows()) {
        const raw = pal.VirtualAlloc(@ptrCast(*void, ptr), bytes, pal.MEM_COMMIT, pal.PAGE_READWRITE);
        return @ptrToInt(raw) != 0;
    }
    return pal.mprotect(@ptrCast(*void, ptr), bytes, pal.PROT_READ | pal.PROT_WRITE) == 0;
}

pub fn pageDecommit(self: *PageAllocator, ptr: [*]u8, bytes: usize) bool {
    if (bytes == 0) return false;
    if (!pageAligned(ptr)) return false;
    if (bytes % PAGE_SIZE != 0) return false;
    if (@isWindows()) {
        return pal.VirtualFree(@ptrCast(*void, ptr), bytes, pal.MEM_DECOMMIT) != 0;
    }
    if (self.mode == MODE_REMAP) {
        _ = pal.munmap(@ptrCast(*void, ptr), bytes);
        const raw = pal.mmap(@ptrCast(*void, ptr), bytes, pal.PROT_NONE, pal.MAP_FIXED | pal.MAP_PRIVATE | pal.MAP_ANON, -1, 0);
        if (@ptrToInt(raw) >= 0xFFFFF000) return false;
        return true;
    }
    if (self.mode == MODE_PROTECT) {
        return pal.mprotect(@ptrCast(*void, ptr), bytes, pal.PROT_NONE) == 0;
    }
    if (self.mode == MODE_MODERN) {
        if (self.cfg.madvise_fn) |f| {
            return f(@ptrCast(*void, ptr), bytes, MADV_DONTNEED) == 0;
        }
        return false;
    }
    return false;
}

pub fn pageRelease(self: *PageAllocator, ptr: [*]u8, bytes: usize) void {
    _ = self;
    if (bytes == 0) return;
    if (@isWindows()) {
        _ = pal.VirtualFree(@ptrCast(*void, ptr), 0, pal.MEM_RELEASE);
        return;
    }
    // pageReserve rounded the mapping up to RESERVE_GRANULARITY; release the
    // same length, not just the unrounded caller request. If rounding would
    // overflow, fall back to the caller's bytes (the reserve itself could not
    // have succeeded with an overflowing rounded length).
    const n: usize = roundUp(bytes, RESERVE_GRANULARITY) orelse bytes;
    _ = pal.munmap(@ptrCast(*void, ptr), n);
}
