extern "stdcall" fn MessageBoxA(hwnd: *void, text: [*]const u8, cap: [*]const u8, typ: u32) i32;

pub fn main() void {
    if (@isWindows()) {
        _ = MessageBoxA(@ptrCast(*void, @intToPtr(*void, 0)), @ptrCast([*]const u8, @intToPtr([*]const u8, 0)), @ptrCast([*]const u8, @intToPtr([*]const u8, 0)), @intCast(u32, 0));
    }
}
