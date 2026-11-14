pub const Sand = struct {
    start: [*]u8,
    pos: usize,
    end: usize,
    peak: usize,
    name: []const u8,
    growable: ?*GrowableSand,
};

pub const SandSegment = struct {
    start: [*]u8,
    size: usize,
    end: usize, // segment byte capacity (== size); Sand.end is a LENGTH, not an address
    next: ?*SandSegment,
};

pub const GrowableSand = struct {
    first: SandSegment,     // embedded first-segment header (e.g. 4 KB)
    last: *SandSegment,     // active segment header
    backing: *Sand,         // module arena (supplies new segments)
    view: Sand,             // the stable *Sand held by consumers
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
        .growable = null,
    };
    var used = s.pos;
    if (used > s.peak) s.peak = used;
    return s;
}

pub fn sandAlloc(sand: *Sand, size: usize, alignment: usize) ![*]u8 {
    var fail_new_pos: usize = @intCast(usize, 0);
    while (true) {
        var mask: usize = alignment - @intCast(usize, 1);
        var aligned: usize = (sand.pos + mask) & ~mask;
        var new_pos: usize = aligned + size;
        if (new_pos <= sand.end) {
            var result: [*]u8 = sand.start + aligned;
            sand.pos = new_pos;
            if (new_pos > sand.peak) sand.peak = new_pos;
            return result;
        }
        if (sand.growable) |gs| {
            if (growableSandGrow(gs, sand, size)) {
                continue; // retry in the new segment
            }
        }
        fail_new_pos = new_pos;
        break;
    }
    if (sand.growable) |gs| {
        _ = gs;
        pal.stderr_write("OOM: growable arena cannot grow (pool exhausted)\n");
    }
    pal.stderr_write("OOM: used=");
    printUsize(sand.pos);
    pal.stderr_write(" new=");
    printUsize(fail_new_pos);
    pal.stderr_write(" total=");
    printUsize(sand.end);
    pal.stderr_write("\n");
    panic_mod.panicHandler("out of memory", "allocator.zig", 28);
    return error.OutOfMemory;
}

pub fn sandReset(sand: *Sand) void {
    if (sand.growable) |gs| {
        var rest = gs.first.next;
        gs.first.next = null;
        gs.last = &gs.first;
        sand.start = gs.first.start;
        sand.end = gs.first.end;
        sand.pos = @intCast(usize, 0);
        if (rest) |r| {
            var tail = r;
            while (tail.next) |nn| {
                tail = nn;
            }
            tail.next = seg_free_head;
            seg_free_head = r;
        }
        return; // peak intentionally kept (matches plain-sand behavior)
    }
    sand.pos = @intCast(usize, 0);
}

pub fn growableSandInit(gs: *GrowableSand, backing: *Sand, first_size: usize, name: []const u8) void {
    var raw = sandAlloc(backing, first_size, 4) catch {
        panic_mod.panicHandler("growable init oom", "allocator.zig", 28);
        return;
    };
    gs.first = SandSegment{ .start = raw, .size = first_size, .end = first_size, .next = null };
    gs.last = &gs.first;
    gs.backing = backing;
    gs.view = Sand{
        .start = raw,
        .pos = @intCast(usize, 0),
        .end = first_size,
        .peak = @intCast(usize, 0),
        .name = name,
        .growable = null,
    };
    gs.view.growable = gs; // MUST be set AFTER assignment (points at caller's final location)
}

fn growableSandGrow(gs: *GrowableSand, view: *Sand, size: usize) bool {
    if (gs.last.next) |next| {
        // chain already has this size (post-reset reuse) — no warning
        gs.last = next;
        view.start = next.start;
        view.end = next.end;
        view.pos = @intCast(usize, 0);
        return true;
    }
    var old_size: usize = gs.last.size;
    var new_size: usize = gs.last.size * 2; // capped doubling 4→8→16→…→2 MiB
    var max_segment: usize = @intCast(usize, 1 * 1024 * 1024);
    if (new_size > max_segment) new_size = max_segment;
    if (size > new_size) new_size = size; // exact-fit final segment to the requested size
    if (seg_free_head != null) {
        if (popFreeBestFit(new_size)) |seg| {
            var seg_cap: usize = seg.end;
            gs.last.next = seg;
            gs.last = seg;
            seg.next = null;
            seg.size = new_size; // re-baseline: natural ladder size, not the popped capacity
            seg.end = seg_cap;
            view.start = seg.start;
            view.end = seg.end;
            view.pos = @intCast(usize, 0);
            return true; // reuse — no arenaGrew (not a genuine new carve)
        }
    }
    var raw = sandAlloc(gs.backing, new_size, 4) catch return false;
    var seg_raw = sandAlloc(gs.backing, @intCast(usize, @sizeOf(SandSegment)), 4) catch return false;
    var node = @ptrCast(*SandSegment, seg_raw);
    node.* = SandSegment{ .start = raw, .size = new_size, .end = new_size, .next = null };
    gs.last.next = node;
    gs.last = node;
    view.start = node.start;
    view.end = node.end;
    view.pos = @intCast(usize, 0);
    arenaGrew(view.name, old_size, new_size); // fires ONLY on a new allocation
    return true;
}

fn popFreeBestFit(min_cap: usize) ?*SandSegment {
    var best: ?*SandSegment = null;
    var best_prev: ?*SandSegment = null;
    var prev: ?*SandSegment = null;
    var cur = seg_free_head;
    while (cur) |c| {
        if (c.end >= min_cap) {
            if (best) |b| {
                if (c.end < b.end) {
                    best = c;
                    best_prev = prev;
                    if (c.end == min_cap) break;
                }
            } else {
                best = c;
                best_prev = prev;
                if (c.end == min_cap) break;
            }
        }
        prev = cur;
        cur = c.next;
    }
    if (best) |b| {
        if (best_prev) |bp| {
            bp.next = b.next;
        } else {
            seg_free_head = b.next;
        }
        b.next = null;
        return b;
    }
    return null;
}

pub fn arenaGrew(name: []const u8, old_size: usize, new_size: usize) void {
    if (!pal.isMarkersEnabled()) return;
    var p0: []const u8 = "arena ";
    pal.measureMarkerWrite(p0);
    pal.measureMarkerWrite(name);
    var p1: []const u8 = ": grew ";
    pal.measureMarkerWrite(p1);
    writeUsizeExact(old_size);
    var p2: []const u8 = " -> ";
    pal.measureMarkerWrite(p2);
    writeUsizeExact(new_size);
    var p3: []const u8 = "\n";
    pal.measureMarkerWrite(p3);
}

fn writeUsizeExact(val: usize) void {
    var buf: [16]u8 = undefined;
    var len = itoa_mod.itoa(@intCast(u32, val), buf[0..]);
    var start: usize = @intCast(usize, 16) - @intCast(usize, len) - @intCast(usize, 1);
    pal.measureMarkerWrite(buf[start..@intCast(usize, 15)]);
}

pub fn sandResetPeak(sand: *Sand) void {
    sand.peak = sand.pos;
}

pub fn sandTryReallocInPlace(sand: *Sand, old_ptr: [*]u8, old_size: usize, new_size: usize, alignment: usize) ?[*]u8 {
    if (new_size <= old_size) return old_ptr;
    var old_end: usize = @ptrToInt(old_ptr) + old_size;
    var arena_end: usize = @ptrToInt(sand.start) + sand.pos;
    if (old_end == arena_end) {
        var new_pos: usize = sand.pos + (new_size - old_size);
        if (new_pos <= sand.end) {
            sand.pos = new_pos;
            if (sand.pos > sand.peak) sand.peak = sand.pos;
            return old_ptr;
        }
    }
    return null;
}

pub fn sandReallocInPlace(sand: *Sand, old_ptr: [*]u8, old_size: usize, new_size: usize, alignment: usize) ?[*]u8 {
    return sandTryReallocInPlace(sand, old_ptr, old_size, new_size, alignment);
}

pub const CompilerAlloc = struct {
    permanent: Sand,
    module: Sand,
    scratch: Sand,
    lir_read: Sand,
    emission: Sand,
    max_mem: u32,
};

pub const POOL_SIZE: usize = 268435456; // 256 MiB measurement pool; sized to measured peak + margin in Task 12
var memory_pool_buf: [POOL_SIZE]u8 = undefined;
var pool: Sand = undefined; // monotonic bump over memory_pool_buf; never reset
var perm_gs: GrowableSand = undefined; // tier arena perm (pool-backed growable)
var mod_gs: GrowableSand = undefined; // tier arena module (pool-backed growable)
var scr_gs: GrowableSand = undefined; // tier arena scratch (pool-backed growable)
var lir_gs: GrowableSand = undefined; // tier arena lir_read (pool-backed growable)
var emit_gs: GrowableSand = undefined; // tier arena emission (pool-backed growable)
var seg_free_head: ?*SandSegment = null; // cross-arena reuse pool (re-baselined splice)

pub const DEV_MAX_MEM: usize = 16 * 1024 * 1024;
pub const RELEASE_MAX_MEM: usize = 16 * 1024 * 1024;
// -mm<N> default: 64 MB hard pool budget, in KB (checkCombinedPeak compares pool.peak/1024 vs max_mem)
pub const DEFAULT_MAX_MEM_KB: usize = 64 * 1024;

pub fn poolPtr() *Sand {
    return &pool;
}

pub fn poolPeak() usize {
    return pool.peak;
}

pub fn initCompilerAlloc() CompilerAlloc {
    pool = sandInit(memory_pool_buf[0..]);
    growableSandInit(&perm_gs, &pool, 4096, "perm");
    growableSandInit(&mod_gs, &pool, 4096, "module");
    growableSandInit(&scr_gs, &pool, 4096, "scratch");
    growableSandInit(&lir_gs, &pool, 4096, "lir_read");
    growableSandInit(&emit_gs, &pool, 4096, "emission");
    var ca = CompilerAlloc{
        .permanent = perm_gs.view,
        .module = mod_gs.view,
        .scratch = scr_gs.view,
        .lir_read = lir_gs.view,
        .emission = emit_gs.view,
        .max_mem = @intCast(u32, DEV_MAX_MEM),
    };
    return ca;
}

pub fn checkCombinedPeak(alloc: *CompilerAlloc) void {
    var pool_kb: usize = pool.peak / @intCast(usize, 1024);
    var limit_kb: usize = POOL_SIZE / @intCast(usize, 1024);
    if (alloc.max_mem != 0) {
        limit_kb = @intCast(usize, alloc.max_mem);
    }
    if (pool_kb > limit_kb) {
        var mm: []const u8 = "memory limit exceeded: pool limit="; pal.stderr_write(mm);
        printUsize(limit_kb);
        var p: []const u8 = "K pool="; pal.stderr_write(p);
        printUsize(pool_kb);
        var t: []const u8 = "K\n"; pal.stderr_write(t);
        panic_mod.panicHandler("out of memory", "allocator.zig", 28);
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
