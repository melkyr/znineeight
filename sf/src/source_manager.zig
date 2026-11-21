const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const ga_mod = @import("growable_array.zig");
const U32ArrayList = ga_mod.U32ArrayList;
const mem_mod = @import("util/mem.zig");
const util_mod = @import("util/util.zig");
const pal_mod = @import("pal.zig");

pub const SourceFile = struct {
    filename: []const u8,
    content: []const u8,
    line_offsets: *U32ArrayList,
    len: usize,
    loaded: bool,
    transient: bool,
};

const SourceFileArrayList = struct {
    items: [*]SourceFile,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

fn sourceFileArrayListInit(allocator: *Sand) SourceFileArrayList {
    return SourceFileArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

fn sourceFileArrayListEnsureCapacity(self: *SourceFileArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    if (self.capacity > 0) {
        var grown = alloc_mod.sandTryReallocInPlace(self.allocator,
            @ptrCast([*]u8, self.items),
            self.capacity * @intCast(usize, @sizeOf(SourceFile)),
            new_cap * @intCast(usize, @sizeOf(SourceFile)),
            @intCast(usize, 4));
        if (grown != null) {
            self.capacity = new_cap;
            return;
        }
    }
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, @sizeOf(SourceFile)) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]SourceFile, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

fn sourceFileArrayListAppend(self: *SourceFileArrayList, value: SourceFile) void {
    sourceFileArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

fn sourceFileArrayListGetSlice(self: *SourceFileArrayList) []SourceFile {
    return self.items[0..self.len];
}

pub const Location = struct {
    file_id: u32,
    line: u32,
    col: u32,
};

pub const SourceManager = struct {
    files: *SourceFileArrayList,
    allocator: *Sand,
    fault: *alloc_mod.GrowableSand,
    fault_ready: bool,
};

pub fn sourceManagerInit(allocator: *Sand) SourceManager {
    var f_raw = alloc_mod.sandAlloc(allocator, @intCast(usize, 16), @intCast(usize, 4)) catch unreachable;
    var f_ptr = @ptrCast(*SourceFileArrayList, f_raw);
    f_ptr.* = sourceFileArrayListInit(allocator);
    var gs_raw = alloc_mod.sandAlloc(allocator, @intCast(usize, @sizeOf(alloc_mod.GrowableSand)), @intCast(usize, 4)) catch unreachable;
    var gs_ptr = @ptrCast(*alloc_mod.GrowableSand, gs_raw);
    return SourceManager{
        .files = f_ptr,
        .allocator = allocator,
        .fault = gs_ptr,
        .fault_ready = false,
    };
}

pub fn sourceManagerAddFile(self: *SourceManager, filename: []const u8, content: []const u8) u32 {
    var fname_raw = sourceManagerCopyToArena(self, filename);
    var fname_copy = fname_raw[0..filename.len];

    var line_count: u32 = @intCast(u32, 0);
    for (content) |c| {
        if (c == '\n') { line_count += 1; }
    }
    var cap: u32 = line_count + 1;
    if (cap < 64) cap = 64;
    var lo_raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 16), @intCast(usize, 4)) catch unreachable;
    var lo_ptr = @ptrCast(*U32ArrayList, lo_raw);
    lo_ptr.* = ga_mod.u32ArrayListInit(self.allocator);
    ga_mod.u32ArrayListEnsureCapacity(lo_ptr, cap);
    ga_mod.u32ArrayListAppend(lo_ptr, 0);

    for (content) |c, i| {
        if (c == '\n') {
            ga_mod.u32ArrayListAppend(lo_ptr, @intCast(u32, i) + 1);
        }
    }

    sourceFileArrayListAppend(self.files, SourceFile{
        .filename = fname_copy,
        .content = content,
        .line_offsets = lo_ptr,
        .len = content.len,
        .loaded = true,
        .transient = false,
    });
    return @intCast(u32, self.files.len);
}

pub fn sourceManagerAddFileTransient(self: *SourceManager, filename: []const u8, content: []const u8) u32 {
    var fname_raw = sourceManagerCopyToArena(self, filename);
    var fname_copy = fname_raw[0..filename.len];

    var dummy_raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 16), @intCast(usize, 4)) catch unreachable;
    var dummy_ptr = @ptrCast(*U32ArrayList, dummy_raw);
    dummy_ptr.* = ga_mod.u32ArrayListInit(self.allocator);

    sourceFileArrayListAppend(self.files, SourceFile{
        .filename = fname_copy,
        .content = content,
        .line_offsets = dummy_ptr,
        .len = content.len,
        .loaded = false,
        .transient = true,
    });
    return @intCast(u32, self.files.len);
}

fn sourceManagerFaultIn(self: *SourceManager, file_id: u32) void {
    if (file_id == @intCast(u32, 0)) return;
    var files_slice = sourceFileArrayListGetSlice(self.files);
    if (files_slice.len == @intCast(usize, 0)) return;
    var fid = file_id;
    if (fid > @intCast(u32, files_slice.len)) fid = @intCast(u32, 1);
    var file = &files_slice[@intCast(usize, fid - 1)];
    if (file.loaded) return;
    if (!self.fault_ready) {
        var gs_name: []const u8 = "diag_read";
        alloc_mod.growableSandInit(self.fault, alloc_mod.poolPtr(), 4096, gs_name);
        self.fault_ready = true;
    }
    var content_opt = pal_mod.readFile(file.filename, &self.fault.view);
    if (content_opt) |content| {
        var lo_raw = alloc_mod.sandAlloc(&self.fault.view, @intCast(usize, 16), @intCast(usize, 4)) catch unreachable;
        var lo_ptr = @ptrCast(*U32ArrayList, lo_raw);
        lo_ptr.* = ga_mod.u32ArrayListInit(&self.fault.view);
        var scan_len: usize = file.len;
        if (scan_len > content.len) scan_len = content.len;
        var line_count: u32 = @intCast(u32, 0);
        var si: usize = @intCast(usize, 0);
        while (si < scan_len) : (si += 1) {
            if (content[si] == '\n') line_count += 1;
        }
        var cap: u32 = line_count + 1;
        ga_mod.u32ArrayListEnsureCapacity(lo_ptr, cap);
        ga_mod.u32ArrayListAppend(lo_ptr, 0);
        for (content) |c, i| {
            if (c == '\n') { ga_mod.u32ArrayListAppend(lo_ptr, @intCast(u32, i) + 1); }
        }
        file.content = content;
        file.line_offsets = lo_ptr;
        file.loaded = true;
    } else {
        var empty_content: []const u8 = "";
        var lo_raw2 = alloc_mod.sandAlloc(&self.fault.view, @intCast(usize, 16), @intCast(usize, 4)) catch unreachable;
        var lo_ptr2 = @ptrCast(*U32ArrayList, lo_raw2);
        lo_ptr2.* = ga_mod.u32ArrayListInit(&self.fault.view);
        ga_mod.u32ArrayListAppend(lo_ptr2, 0);
        file.content = empty_content;
        file.line_offsets = lo_ptr2;
        file.loaded = true;
    }
}

pub fn sourceManagerResetFaults(self: *SourceManager) void {
    if (!self.fault_ready) return;
    alloc_mod.sandReset(&self.fault.view);
    var files_slice = sourceFileArrayListGetSlice(self.files);
    var i: usize = @intCast(usize, 0);
    while (i < files_slice.len) : (i += 1) {
        if (files_slice[i].transient) files_slice[i].loaded = false;
    }
}

pub fn sourceManagerGetFileName(self: *SourceManager, file_id: u32) []const u8 {
    if (file_id == @intCast(u32, 0)) { var dummy: []const u8 = ""; return dummy; }
    var files_slice = sourceFileArrayListGetSlice(self.files);
    if (files_slice.len == @intCast(usize, 0)) { var dummy: []const u8 = ""; return dummy; }
    var fid = file_id;
    if (fid > @intCast(u32, files_slice.len)) fid = @intCast(u32, 1);
    return files_slice[@intCast(usize, fid - 1)].filename;
}

pub fn sourceManagerGetSourceContent(self: *SourceManager, file_id: u32) []const u8 {
    if (file_id == @intCast(u32, 0)) { var dummy: []const u8 = ""; return dummy; }
    var files_slice = sourceFileArrayListGetSlice(self.files);
    if (files_slice.len == @intCast(usize, 0)) { var dummy: []const u8 = ""; return dummy; }
    var fid = file_id;
    if (fid > @intCast(u32, files_slice.len)) fid = @intCast(u32, 1);
    sourceManagerFaultIn(self, fid);
    return files_slice[@intCast(usize, fid - 1)].content;
}

pub fn sourceManagerGetLineOffsets(self: *SourceManager, file_id: u32) []u32 {
    if (file_id == @intCast(u32, 0)) { var dummy: [0]u32 = undefined; return dummy[0..]; }
    var files_slice = sourceFileArrayListGetSlice(self.files);
    if (files_slice.len == @intCast(usize, 0)) { var dummy: [0]u32 = undefined; return dummy[0..]; }
    var fid = file_id;
    if (fid > @intCast(u32, files_slice.len)) fid = @intCast(u32, 1);
    sourceManagerFaultIn(self, fid);
    return ga_mod.u32ArrayListGetSlice(files_slice[@intCast(usize, fid - 1)].line_offsets);
}

pub fn sourceManagerGetLocation(self: *SourceManager, file_id: u32, offset: u32) Location {
    if (file_id == @intCast(u32, 0)) {
        return Location{ .file_id = @intCast(u32, 0), .line = @intCast(u32, 0), .col = @intCast(u32, 0) };
    }
    var files_slice = sourceFileArrayListGetSlice(self.files);
    var fid: u32 = file_id;
    if (files_slice.len == @intCast(usize, 0)) {
        return Location{ .file_id = @intCast(u32, 0), .line = @intCast(u32, 0), .col = @intCast(u32, 0) };
    }
    if (fid > @intCast(u32, files_slice.len)) fid = @intCast(u32, 1);
    sourceManagerFaultIn(self, fid);
    var file = &files_slice[@intCast(usize, fid - 1)];
    var offsets = ga_mod.u32ArrayListGetSlice(file.line_offsets);
    var line_idx = mem_mod.binary_search(offsets, offset);
    var col: u32 = offset - offsets[@intCast(usize, line_idx)];
    return Location{
        .file_id = file_id,
        .line = line_idx + 1,
        .col = col,
    };
}

fn sourceManagerCopyToArena(self: *SourceManager, text: []const u8) [*]u8 {
    if (text.len == 0) return undefined;
    var raw = alloc_mod.sandAlloc(self.allocator, text.len, @intCast(usize, 1)) catch unreachable;
    for (text) |c, i| {
        raw[i] = c;
    }
    return raw;
}
