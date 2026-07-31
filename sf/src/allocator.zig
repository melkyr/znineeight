pub const Sand = struct {
    start: [*]u8,
    pos: usize,
    end: usize,
    peak: usize,
    name: []const u8,
};
const pal = @import("pal.zig");
const panic_mod = @import("panic.zig");
const itoa_mod = @import("util/itoa.zig");

pub fn sandInit(buf: []u8) Sand {
    var uname: []const u8 = "unknown";
    var s = Sand{
        .start = buf.ptr,
        .pos = @intCast(usize, 0),
        .end = buf.len,
        .peak = @intCast(usize, 0),
        .name = uname,
    };
    var used = s.pos;
    if (used > s.peak) s.peak = used;
    return s;
}

pub fn sandAlloc(sand: *Sand, size: usize, alignment: usize) ![*]u8 {
    var mask: usize = alignment - @intCast(usize, 1);
    var aligned: usize = (sand.pos + mask) & ~mask;
    var new_pos: usize = aligned + size;
    if (new_pos > sand.end) {
        pal.stderr_write("OOM: used=");
        printUsize(sand.pos);
        pal.stderr_write(" new=");
        printUsize(new_pos);
        pal.stderr_write(" total=");
        printUsize(sand.end);
        pal.stderr_write("\n");
        panic_mod.panicHandler("out of memory", "allocator.zig", 28);
        return error.OutOfMemory;
    }
    var result: [*]u8 = sand.start + aligned;
    sand.pos = new_pos;
    if (new_pos > sand.peak) sand.peak = new_pos;
    return result;
}

pub fn sandReset(sand: *Sand) void {
    sand.pos = @intCast(usize, 0);
}

pub fn sandResetPeak(sand: *Sand) void {
    sand.peak = sand.pos;
}

pub fn sandReallocInPlace(sand: *Sand, old_ptr: [*]u8, old_size: usize, new_size: usize, alignment: usize) ?[*]u8 {
    if (new_size <= old_size) return old_ptr;
    var old_end: usize = @ptrToInt(old_ptr) + old_size;
    var arena_end: usize = @ptrToInt(sand.start) + sand.pos;
    if (old_end == arena_end and new_size > old_size) {
        sand.pos += (new_size - old_size);
        if (sand.pos > sand.peak) sand.peak = sand.pos;
        return old_ptr;
    }
    return null;
}

pub const CompilerAlloc = struct {
    permanent: Sand,
    module: Sand,
    scratch: Sand,
    max_mem: u32,
};

var perm_arena_buf: [1048576]u8 = undefined;
var mod_arena_buf: [1572864]u8 = undefined;
var scr_arena_buf: [1572864]u8 = undefined;

pub const DEV_MAX_MEM: usize = 8 * 1024 * 1024;
pub const RELEASE_MAX_MEM: usize = 16 * 1024 * 1024;

pub fn initCompilerAlloc() CompilerAlloc {
    var ca = CompilerAlloc{
        .permanent = sandInit(perm_arena_buf[0..]),
        .module = sandInit(mod_arena_buf[0..]),
        .scratch = sandInit(scr_arena_buf[0..]),
        .max_mem = @intCast(u32, DEV_MAX_MEM),
    };
    ca.permanent.name = "perm";
    ca.module.name = "module";
    ca.scratch.name = "scratch";
    return ca;
}

pub fn checkCombinedPeak(alloc: *CompilerAlloc) void {
    var perm_kb: usize = alloc.permanent.peak / @intCast(usize, 1024);
    var mod_kb: usize = alloc.module.peak / @intCast(usize, 1024);
    var scr_kb: usize = alloc.scratch.peak / @intCast(usize, 1024);
    var total_kb: usize = perm_kb + mod_kb + scr_kb;
    var limit_kb: usize = @intCast(usize, alloc.max_mem) / @intCast(usize, 1024);
    if (total_kb > limit_kb) {
        var mm: []const u8 = "memory limit exceeded: max-mem="; pal.stderr_write(mm);
        printUsize(limit_kb);
        var p: []const u8 = "K perm="; pal.stderr_write(p);
        printUsize(perm_kb);
        var m: []const u8 = "K mod="; pal.stderr_write(m);
        printUsize(mod_kb);
        var s: []const u8 = "K scr="; pal.stderr_write(s);
        printUsize(scr_kb);
        var t: []const u8 = "K\n"; pal.stderr_write(t);
        pal.exit(1);
    }
}

fn printUsize(val: usize) void {
    var buf: [16]u8 = undefined;
    var len = itoa_mod.itoa(@intCast(u32, val), buf[0..]);
    var start: usize = @intCast(usize, 15) - @intCast(usize, len);
    pal.stderr_write(buf[start..@intCast(usize, 15)]);
}

// KEPT (unwired) — per-allocation tracking infra for --track-memory / --max-mem enforcement per TEST_HARNESS_p2.md §5. Not currently wired into CompilerAlloc.
pub const TrackingAllocator = struct {
    arena: *Sand,
    total_allocated: u32,
    peak_allocated: u32,
    allocation_count: u32,
};

pub fn trackingAllocatorInit(arena: *Sand) TrackingAllocator {
    return TrackingAllocator{
        .arena = arena,
        .total_allocated = @intCast(u32, 0),
        .peak_allocated = @intCast(u32, 0),
        .allocation_count = @intCast(u32, 0),
    };
}

pub fn trackingAlloc(tracker: *TrackingAllocator, size: usize, alignment: usize) ![*]u8 {
    var ptr = try sandAlloc(tracker.arena, size, alignment);
    tracker.allocation_count += 1;
    tracker.total_allocated += @intCast(u32, size);
    if (tracker.total_allocated > tracker.peak_allocated) {
        tracker.peak_allocated = tracker.total_allocated;
    }
    return ptr;
}

pub fn trackingReset(tracker: *TrackingAllocator) void {
    sandReset(tracker.arena);
    tracker.total_allocated = @intCast(u32, 0);
}

pub fn trackingPeak(tracker: *TrackingAllocator) u32 {
    return tracker.peak_allocated;
}

pub fn trackingAllocatorReport(tracker: *TrackingAllocator) TrackingAllocatorReport {
    return TrackingAllocatorReport{
        .peak = tracker.peak_allocated,
        .total = tracker.total_allocated,
        .count = tracker.allocation_count,
    };
}

pub const TrackingAllocatorReport = struct {
    peak: u32,
    total: u32,
    count: u32,
};
