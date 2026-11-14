// For bootstrap, we use a special signature that the type checker allows
// but the codegen will lower specially.
pub extern fn print(fmt: *const u8, args: anytype) void;
