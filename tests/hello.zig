extern fn puts(s: *const u8) i32;

pub fn main() i32 {
    return puts("Hello from RetroZig!");
}
