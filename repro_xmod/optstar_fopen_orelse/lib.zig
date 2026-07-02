pub const File = void;
extern fn fopen(filename: [*]const u8, mode: [*]const u8) ?*File;
