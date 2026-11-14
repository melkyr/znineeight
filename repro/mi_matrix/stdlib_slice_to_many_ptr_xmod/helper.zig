// Helper module for stdlib_slice_to_many_ptr_xmod: many-item-pointer
// parameters and returns in the allowed (slice -> many) directions.
pub fn firstMany(mp: [*]i32) i32 {
    return mp[1];
}

pub fn sumConstMany(mp: [*]const i32) i32 {
    return mp[0] + mp[1];
}

pub fn retMany(s: []i32) [*]i32 {
    return s;
}

pub fn bump(mp: [*]i32) void {
    mp[0] = mp[0] + 5;
}
