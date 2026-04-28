const fnv1a = @import("hash.zig").fnv1a;
const mem_eql = @import("mem.zig").mem_eql;
const binary_search = @import("mem.zig").binary_search;
const itoa = @import("itoa.zig").itoa;
const min = @import("util.zig").min;
const max = @import("util.zig").max;
const U32ArrayList = @import("growable_array.zig").U32ArrayList;
const sortDiagnostics = @import("diagnostic_sort.zig").sortDiagnostics;
const assert_true = @import("../test_runner.zig").assert_true;
const assert_eq_u32 = @import("../test_runner.zig").assert_eq_u32;
const assert_eq_str = @import("../test_runner.zig").assert_eq_str;

const Allocator = @import("../allocator.zig").Allocator;
const Diagnostic = @import("../diagnostics.zig").Diagnostic;

const BumpState = struct {
    buf: []u8,
    pos: u32,
};

const BumpAlloc = struct {
    state: BumpState,
    iface: Allocator,

    pub fn init(buf: []u8) BumpAlloc {
        var result = BumpAlloc{
            .state = BumpState{ .buf = buf, .pos = 0 },
            .iface = undefined,
        };
        result.iface = Allocator{
            .context = @ptrCast(*void, &result.state),
            .alloc_fn = bumpAllocFn,
            .free_fn = bumpFreeFn,
            .resize_fn = bumpResizeFn,
        };
        return result;
    }

    pub fn allocator(self: *BumpAlloc) *Allocator {
        self.iface.context = @ptrCast(*void, &self.state);
        return &self.iface;
    }
};

fn bumpFromContext(ctx: *void) *BumpState {
    return @ptrCast(*BumpState, ctx);
}

fn bumpAllocFn(ctx: *void, byte_count: usize, alignment: u32) ![]u8 {
    var state = bumpFromContext(ctx);
    var align_val = alignment;
    if (align_val < 1) align_val = 1;
    var mask = align_val - 1;
    var current = state.pos;
    var aligned = (current + mask) & ~mask;
    var new_pos = aligned + @intCast(u32, byte_count);
    if (new_pos > @intCast(u32, state.buf.len)) {
        @panic("test bump alloc OOM");
    }
    state.pos = new_pos;
    return state.buf[@intCast(usize, aligned)..@intCast(usize, new_pos)];
}

fn bumpFreeFn(ctx: *void, bytes: []u8) void {
    _ = ctx;
    _ = bytes;
}

fn bumpResizeFn(ctx: *void, bytes: []u8, new_count: usize) !bool {
    _ = ctx;
    _ = bytes;
    _ = new_count;
    return false;
}

fn appendOrPanic(list: *U32ArrayList, value: u32) void {
    list.append(value) catch @panic("append failed");
}

fn test_string_interner() void {
    var backing_buf: [4096]u8 = undefined;
    var bump = BumpAlloc.init(backing_buf[0..]);
    var alloc = bump.allocator();

    const StringInterner = @import("../string_interner.zig").StringInterner;
    var inter = StringInterner.init(alloc, 4) catch @panic("interner init");
    var id_a = inter.intern("hello") catch @panic("intern hello");
    var id_b = inter.intern("world") catch @panic("intern world");
    var id_c = inter.intern("hello") catch @panic("intern hello again");
    assert_true(id_a == id_c, "interner dedup");
    assert_true(id_a != id_b, "interner different");
    assert_eq_str(inter.get(id_a), "hello", "interner get hello");
    assert_eq_str(inter.get(id_b), "world", "interner get world");
}

fn test_fnv1a() void {
    var h = fnv1a("");
    assert_eq_u32(h, 2166136261, "fnv1a empty");
    assert_eq_u32(fnv1a("hello"), 1335831723, "fnv1a hello");
    assert_eq_u32(fnv1a("Hello"), 2673584966, "fnv1a Hello");
}

fn test_mem_eql() void {
    assert_true(mem_eql("", ""), "mem_eql empty");
    assert_true(mem_eql("abc", "abc"), "mem_eql equal");
    assert_true(!mem_eql("abc", "ab"), "mem_eql len mismatch");
    assert_true(!mem_eql("abc", "abd"), "mem_eql byte diff");
}

fn test_binary_search() void {
    var offsets = [_]u32{ 0, 10, 20, 30, 40 };
    assert_eq_u32(binary_search(offsets[0..], 0), 0, "bs 0");
    assert_eq_u32(binary_search(offsets[0..], 5), 0, "bs 5");
    assert_eq_u32(binary_search(offsets[0..], 10), 1, "bs 10");
    assert_eq_u32(binary_search(offsets[0..], 15), 1, "bs 15");
    assert_eq_u32(binary_search(offsets[0..], 40), 4, "bs 40");
    assert_eq_u32(binary_search(offsets[0..], 99), 4, "bs 99");
}

fn test_itoa() void {
    var buf: [16]u8 = undefined;
    var len = itoa(0, buf[0..]);
    assert_true(len == 1, "itoa 0 len");
    assert_true(buf[15] == '0', "itoa 0 char");
    len = itoa(42, buf[0..]);
    assert_true(len == 2, "itoa 42 len");
    assert_true(buf[14] == '4', "itoa 42 first");
    assert_true(buf[15] == '2', "itoa 42 second");
    len = itoa(9999, buf[0..]);
    assert_true(len == 4, "itoa 9999 len");
}

fn test_min_max() void {
    assert_eq_u32(min(1, 2), 1, "min 1 2");
    assert_eq_u32(min(5, 5), 5, "min 5 5");
    assert_eq_u32(max(1, 2), 2, "max 1 2");
    assert_eq_u32(max(5, 5), 5, "max 5 5");
}

fn test_u32_arraylist() void {
    var backing_buf: [256]u8 = undefined;
    var bump = BumpAlloc.init(backing_buf[0..]);
    var list = U32ArrayList.init(bump.allocator());
    assert_eq_u32(list.len, 0, "al init len");
    appendOrPanic(&list, 10);
    appendOrPanic(&list, 20);
    appendOrPanic(&list, 30);
    assert_eq_u32(list.len, 3, "al append len");
    assert_eq_u32(list.items[0], 10, "al item 0");
    assert_eq_u32(list.items[1], 20, "al item 1");
    assert_eq_u32(list.items[2], 30, "al item 2");
    var popped = list.popOrNull();
    assert_true(popped != null, "al pop");
    assert_eq_u32(popped.?, 30, "al pop val");
    assert_eq_u32(list.len, 2, "al len pop");
    var slice = list.getSlice();
    assert_eq_u32(@intCast(u32, slice.len), 2, "al slice len");
}

fn test_sort() void {
    var d0 = Diagnostic{ .level = 1, .file_id = 1, .span_start = 30, .span_end = 35, .message = "c" };
    var d1 = Diagnostic{ .level = 1, .file_id = 0, .span_start = 10, .span_end = 15, .message = "b" };
    var d2 = Diagnostic{ .level = 1, .file_id = 0, .span_start = 5, .span_end = 10, .message = "a" };
    var diags = [_]Diagnostic{ d0, d1, d2 };
    sortDiagnostics(diags[0..]);
    assert_eq_u32(diags[0].span_start, 5, "sort 0");
    assert_eq_u32(diags[1].span_start, 10, "sort 1");
    assert_eq_u32(diags[2].span_start, 30, "sort 2");
}

fn test_assertions() void {
    assert_true(true, "true");
    assert_eq_u32(1, 1, "u32 eq");
    assert_eq_str("abc", "abc", "str eq");
}

fn test_source_manager() void {
    var backing_buf: [4096]u8 = undefined;
    var bump = BumpAlloc.init(backing_buf[0..]);
    var alloc = bump.allocator();

    const SourceManager = @import("../source_manager.zig").SourceManager;
    var sm = SourceManager.init(alloc);
    var fid = sm.addFile("test.zig", "a\nbc\ndef\n") catch @panic("sm addFile");
    assert_eq_u32(fid, 0, "sm first file id");

    var files = sm.files.getSlice();
    var offs = files[0].line_offsets.getSlice();
    assert_eq_u32(offs.len, 4, "sm line count");
    assert_eq_u32(offs[0], 0, "sm off 0");
    assert_eq_u32(offs[1], 2, "sm off 2");
    assert_eq_u32(offs[2], 5, "sm off 5");
    assert_eq_u32(offs[3], 8, "sm off 8");

    var loc = sm.getLocation(0, 0);
    assert_eq_u32(loc.line, 1, "sm loc 0 line");
    assert_eq_u32(loc.col, 0, "sm loc 0 col");

    loc = sm.getLocation(0, 1);
    assert_eq_u32(loc.line, 1, "sm loc 1 line");
    assert_eq_u32(loc.col, 1, "sm loc 1 col");

    loc = sm.getLocation(0, 2);
    assert_eq_u32(loc.line, 2, "sm loc 2 line");
    assert_eq_u32(loc.col, 0, "sm loc 2 col");

    loc = sm.getLocation(0, 3);
    assert_eq_u32(loc.line, 2, "sm loc 3 line");
    assert_eq_u32(loc.col, 1, "sm loc 3 col");

    loc = sm.getLocation(0, 5);
    assert_eq_u32(loc.line, 3, "sm loc 5 line");
    assert_eq_u32(loc.col, 0, "sm loc 5 col");

    loc = sm.getLocation(0, 7);
    assert_eq_u32(loc.line, 3, "sm loc 7 line");
    assert_eq_u32(loc.col, 2, "sm loc 7 col");
}

pub fn main() !void {
    test_fnv1a();
    test_mem_eql();
    test_binary_search();
    test_itoa();
    test_min_max();
    test_assertions();
    test_sort();
    test_u32_arraylist();
    test_string_interner();
    test_source_manager();
}
