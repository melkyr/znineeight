pub fn getPtrAddr(ptr: [*]u8) usize {
    const mask = @intCast(usize, 7);
    const current_pos = @ptrToInt(ptr);
    const aligned_pos = (current_pos + mask) & ~mask;
    return aligned_pos;
}
