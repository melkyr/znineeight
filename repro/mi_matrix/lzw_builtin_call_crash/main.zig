@cInclude("<stdio.h>");
extern fn printf(fmt: *u8, x: i32) i32;
extern fn getchar() i32;
pub fn main() void {
    const choice = getchar();
    const next = getchar();
    if (next != @intCast(i32, '\n') and next != -1) {
    }
    if (choice == @intCast(i32, 'c')) {
        _ = printf("compress\n", 0);
    } else if (choice == @intCast(i32, 'd')) {
        _ = printf("decompress\n", 0);
    } else {
        _ = printf("invalid\n", 0);
    }
}
