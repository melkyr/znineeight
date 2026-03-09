// file.zig
pub const File = void;

extern fn fopen(filename: [*]const c_char, mode: [*]const c_char) ?*File;
extern fn fread(buffer: [*]u8, size: usize, count: usize, file: *File) usize;
extern fn fclose(file: *File) i32;
extern fn fseek(file: *File, offset: i64, whence: i32) i32;
extern fn ftell(file: *File) i64;
extern fn ferror(file: *File) i32;
extern fn feof(file: *File) i32;
extern fn strtod(nptr: [*]const c_char, endptr: ?[*]const c_char) f64;

const SEEK_END: i32 = 2;
const SEEK_SET: i32 = 0;

pub const FileError = error{
    OpenFailed,
    ReadFailed,
    SeekFailed,
    TooLarge,
};

extern fn arena_alloc_default(size: usize) *void;

pub fn readFile(arena: *void, path: []const u8) FileError![]u8 {
    const rb_str: []const c_char = @ptrCast([*]const c_char, "rb")[0..2];
    const f = fopen(@ptrCast([*]const c_char, path.ptr), rb_str.ptr) orelse return error.OpenFailed;
    defer _ = fclose(f);

    if (fseek(f, 0, SEEK_END) != 0) { return error.SeekFailed; }
    const size = ftell(f);
    if (size < 0) { return error.SeekFailed; }
    if (fseek(f, 0, SEEK_SET) != 0) { return error.SeekFailed; }

    const usize_size = @intCast(usize, size);
    const buffer = @ptrCast([*]u8, arena_alloc_default(usize_size));
    const bytes_read = fread(buffer, 1, usize_size, f);
    if (bytes_read != usize_size) { return error.ReadFailed; }
    if (ferror(f) != 0) { return error.ReadFailed; }

    return buffer[0..usize_size];
}
