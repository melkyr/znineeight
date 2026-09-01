pub fn maybe(seed: i32) ?i32 {
    if (seed > 0) return seed;
    return null;
}
