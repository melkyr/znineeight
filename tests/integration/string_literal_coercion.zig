extern fn puts(s: [*]const u8) i32;
extern fn printf(format: [*]const u8, ...) i32;

pub fn main() void {
    // 1. Direct use in extern call (Goal of the task)
    _ = puts("Hello from string literal coercion!");

    // 2. Assigning to a slice
    const s: []const u8 = "hello slice";
    _ = printf("Slice ptr: %p, len: %d\n", s.ptr, s.len);

    // 3. Backward compatibility (if needed by existing code)
    // In Z98, many existing things might expect *const u8
    const ptr: *const u8 = "legacy pointer";
    _ = puts(ptr);

    // 4. Coercion from pointer-to-array variable to many-item pointer
    const arr: [5]u8 = "world".*;
    const arr_ptr: *const [5]u8 = &arr;
    const many_ptr: [*]const u8 = arr_ptr;
    _ = puts(many_ptr);
}
