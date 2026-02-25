// file.zig
pub const File = *void;
extern fn fopen(filename: [*]const u8, mode: [*]const u8) ?File;
extern fn fread(buffer: [*]u8, size: usize, count: usize, file: File) usize;
extern fn fclose(file: File) i32;
extern fn fseek(file: File, offset: i64, whence: i32) i32;
extern fn ftell(file: File) i64;
extern fn ferror(file: File) i32;
extern fn feof(file: File) i32;

// Runtime allocation
extern fn arena_alloc(arena: *void, size: usize) *void;

const SEEK_END: i32 = 2;
const SEEK_SET: i32 = 0;

pub const FileError = error{
    OpenFailed,
    ReadFailed,
    SeekFailed,
    TooLarge,
};

pub fn readFile(arena: *void, path: []const u8) FileError![]u8 {
    const f = fopen(@ptrCast([*]const u8, path.ptr), "rb") orelse return error.OpenFailed;
    defer { _ = fclose(f); }

    if (fseek(f, 0, SEEK_END) != 0) { return error.SeekFailed; }
    const size = ftell(f);
    if (size < 0) { return error.SeekFailed; }
    if (fseek(f, 0, SEEK_SET) != 0) { return error.SeekFailed; }

    const usize_size = @intCast(usize, size);
    const buffer_void = arena_alloc(arena, usize_size);
    const buffer = @ptrCast([*]u8, buffer_void);

    const bytes_read = fread(buffer, 1, usize_size, f);
    if (bytes_read != usize_size) { return error.ReadFailed; }

    return buffer[0..usize_size];
}
