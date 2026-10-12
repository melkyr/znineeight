pub fn maybeVal(seed: u32) ?u32 {
    if (seed == 0) return null;
    return seed;
}
