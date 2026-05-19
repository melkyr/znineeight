pub const Sand = struct {
    start: [*]u8,
    pos: usize,
    end: usize,
    peak: usize,
};

pub fn sandInit(buf: []u8) Sand {
    var s = Sand{
        .start = buf.ptr,
        .pos = @intCast(usize, 0),
        .end = buf.len,
        .peak = @intCast(usize, 0),
    };
    var used = s.pos;
    if (used > s.peak) s.peak = used;
    return s;
}

pub fn sandAlloc(sand: *Sand, size: usize, alignment: usize) ![*]u8 {
    var mask = alignment - @intCast(usize, 1);
    var aligned = (sand.pos + mask) & ~mask;
    var new_pos = aligned + size;
    if (new_pos > sand.end) return error.OutOfMemory;
    var result = sand.start + aligned;
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
    return CompilerAlloc{
        .permanent = sandInit(perm_arena_buf[0..]),
        .module = sandInit(mod_arena_buf[0..]),
        .scratch = sandInit(scr_arena_buf[0..]),
        .max_mem = @intCast(u32, DEV_MAX_MEM),
    };
}

pub fn checkCombinedPeak(alloc: *CompilerAlloc) void {
    var total = @intCast(u32, alloc.permanent.peak + alloc.module.peak + alloc.scratch.peak);
    if (total > alloc.max_mem) {
        while (true) {}
    }
}

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
