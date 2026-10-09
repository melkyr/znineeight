// ratelimit.zig — z9torr M3: global token-bucket rate limiter.
//
// Spec §6 `TokenBucket` (binding interface):
//   TokenBucket = struct { tokens: u32, capacity: u32, rate: u32, last_refill_ms: u32 }
//   bucketInit(rate) -> TokenBucket   (burst starts full: tokens = capacity = rate)
//   refill(b, now_ms)                 (elapsed = now - last, unsigned wrap)
//   take(b, n) bool                   (drain n if available)
//
// `refill` adds `rate * elapsed / 1000` tokens, capped at `capacity` (= `rate`,
// the burst), and advances `last_refill_ms` to `now_ms`. `elapsed` is unsigned
// so a wrapping millisecond clock is handled correctly. The multiply is widened
// to u64 so a large rate cannot overflow the token count.
//
// Z98 rules: free functions only, no generics, strict `@intCast`, string
// literals via `var s: []const u8 = "...";`.

const std = @import("std");

pub const TokenBucket = struct {
    tokens: u32,
    capacity: u32,
    rate: u32,
    last_refill_ms: u32,
};

// Start full: a fresh bucket admits one burst up to `rate`.
pub fn bucketInit(rate: u32) TokenBucket {
    return TokenBucket{
        .tokens = rate,
        .capacity = rate,
        .rate = rate,
        .last_refill_ms = 0,
    };
}

// Refill by the wall time elapsed since the last call. `now_ms - last` is
// unsigned (wraps); the add is widened to u64 and capped at capacity.
pub fn refill(b: *TokenBucket, now_ms: u32) void {
    var elapsed: u32 = now_ms - b.last_refill_ms;
    var add: u64 = (@intCast(u64, b.rate) * @intCast(u64, elapsed)) / @intCast(u64, 1000);
    var total: u64 = @intCast(u64, b.tokens) + add;
    if (total > @intCast(u64, b.capacity)) {
        total = @intCast(u64, b.capacity);
    }
    b.tokens = @intCast(u32, total);
    b.last_refill_ms = now_ms;
}

// True and drains n when at least n tokens are available; false (unchanged)
// otherwise. The caller yields and retries on the next tick.
pub fn take(b: *TokenBucket, n: u32) bool {
    if (b.tokens >= n) {
        b.tokens -= n;
        return true;
    }
    return false;
}

// Return `n` tokens that were charged but not used, capped at `capacity`. Used
// when a multi-bucket charge is aborted after a partial take, so a request that
// is never sent consumes nothing from either bucket. Widened to u64 for the add.
pub fn refund(b: *TokenBucket, n: u32) void {
    var total: u64 = @intCast(u64, b.tokens) + @intCast(u64, n);
    if (total > @intCast(u64, b.capacity)) {
        total = @intCast(u64, b.capacity);
    }
    b.tokens = @intCast(u32, total);
}
