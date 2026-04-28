const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const ga_mod = @import("growable_array.zig");
const U32ArrayList = ga_mod.U32ArrayList;
const mem_mod = @import("util/mem.zig");
const util_mod = @import("util/util.zig");

pub const SourceFile = struct {
    filename: []const u8,
    content: []const u8,
    line_offsets: *U32ArrayList,
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

fn sourceFileArrayListEnsureCapacity(self: *SourceFileArrayList, new_capacity: usize) !void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = try alloc_mod.sandAlloc(self.allocator, @intCast(usize, 20) * new_cap, @intCast(usize, 4));
    var new_items = @ptrCast([*]SourceFile, raw);
    var i: usize = 0;
    while (i < self.len) {
        new_items[i] = self.items[i];
        i += 1;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

fn sourceFileArrayListAppend(self: *SourceFileArrayList, value: SourceFile) !void {
    try sourceFileArrayListEnsureCapacity(self, self.len + 1);
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
};

pub fn sourceManagerInit(allocator: *Sand) SourceManager {
    var f_raw = alloc_mod.sandAlloc(allocator, @intCast(usize, 16), @intCast(usize, 4)) catch unreachable;
    var f_ptr = @ptrCast(*SourceFileArrayList, f_raw);
    f_ptr.* = sourceFileArrayListInit(allocator);
    return SourceManager{
        .files = f_ptr,
        .allocator = allocator,
    };
}

pub fn sourceManagerAddFile(self: *SourceManager, filename: []const u8, content: []const u8) !u32 {
    var fname_raw = sourceManagerCopyToArena(self, filename);
    var fname_copy = fname_raw[0..filename.len];
    var content_raw = sourceManagerCopyToArena(self, content);
    var content_copy = content_raw[0..content.len];

    var hint = content.len / 40 + 16;
    var cap = util_mod.max(@intCast(u32, hint), 64);
    var lo_raw = try alloc_mod.sandAlloc(self.allocator, @intCast(usize, 16), @intCast(usize, 4));
    var lo_ptr = @ptrCast(*U32ArrayList, lo_raw);
    lo_ptr.* = ga_mod.u32ArrayListInit(self.allocator);
    try ga_mod.u32ArrayListEnsureCapacity(lo_ptr, cap);
    try ga_mod.u32ArrayListAppend(lo_ptr, 0);

    var i: usize = 0;
    while (i < content.len) {
        if (content[i] == '\n') {
            try ga_mod.u32ArrayListAppend(lo_ptr, @intCast(u32, i) + 1);
        }
        i += 1;
    }

    try sourceFileArrayListAppend(self.files, SourceFile{
        .filename = fname_copy,
        .content = content_copy,
        .line_offsets = lo_ptr,
    });
    return @intCast(u32, self.files.len - 1);
}

pub fn sourceManagerGetFileName(self: *SourceManager, file_id: u32) []const u8 {
    var files_slice = sourceFileArrayListGetSlice(self.files);
    return files_slice[@intCast(usize, file_id)].filename;
}

pub fn sourceManagerGetSourceContent(self: *SourceManager, file_id: u32) []const u8 {
    var files_slice = sourceFileArrayListGetSlice(self.files);
    return files_slice[@intCast(usize, file_id)].content;
}

pub fn sourceManagerGetLineOffsets(self: *SourceManager, file_id: u32) []u32 {
    var files_slice = sourceFileArrayListGetSlice(self.files);
    return ga_mod.u32ArrayListGetSlice(files_slice[@intCast(usize, file_id)].line_offsets);
}

pub fn sourceManagerGetLocation(self: *SourceManager, file_id: u32, offset: u32) Location {
    var files_slice = sourceFileArrayListGetSlice(self.files);
    var file = &files_slice[@intCast(usize, file_id)];
    var offsets = ga_mod.u32ArrayListGetSlice(file.line_offsets);
    var line_idx = mem_mod.binary_search(offsets, offset);
    var col = offset - offsets[@intCast(usize, line_idx)];
    return Location{
        .file_id = file_id,
        .line = line_idx + 1,
        .col = col,
    };
}

fn sourceManagerCopyToArena(self: *SourceManager, text: []const u8) [*]u8 {
    if (text.len == 0) return undefined;
    var raw = alloc_mod.sandAlloc(self.allocator, text.len, @intCast(usize, 1)) catch unreachable;
    var i: usize = 0;
    while (i < text.len) {
        raw[i] = text[i];
        i += 1;
    }
    return raw;
}
