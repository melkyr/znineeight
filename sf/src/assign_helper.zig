pub fn resolveAssignedLocalTemp(lt_ptr: *[128]u32, ln_ptr: *[128]u32, count: u32, temp_id: u32) u32 {
    var i: u32 = count;
    while (i > @intCast(u32, 0)) { i = i - @intCast(u32, 1); if (lt_ptr[@intCast(usize, i)] == temp_id) { return ln_ptr[@intCast(usize, i)]; } }
    return @intCast(u32, 0);
}
