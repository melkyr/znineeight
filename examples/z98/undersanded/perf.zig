// perf.zig — UNDERSANDED M9 frame-time summary (spec §26/§35).
//
// Pure math + formatting: no I/O, no gfx, no game imports. The Windows loop
// feeds high-res tick deltas here and app.zig appends the one summary line to
// errors.log when `under.exe --perf` exits. Frame timings are never a gate.

const text_scan = @import("text_scan.zig");

pub const MAX_FRAMES: usize = 1024;

pub const Perf = struct {
    samples: [MAX_FRAMES]i64,
    n: usize,
};

pub fn reset(p: *Perf) void {
    p.n = 0;
}

pub fn addMs(p: *Perf, ms: i64) void {
    if (p.n >= MAX_FRAMES) return;
    p.samples[p.n] = ms;
    p.n += 1;
}

// Whole milliseconds from a high-res tick delta (integer division, truncated).
pub fn ticksToMs(delta: u64, freq: u64) i64 {
    if (freq == 0) return 0;
    const ms: u64 = delta * @intCast(u64, 1000) / freq;
    return @intCast(i64, ms);
}

pub fn addTicks(p: *Perf, delta: u64, freq: u64) void {
    addMs(p, ticksToMs(delta, freq));
}

// Copy up to out.len samples and sort them ascending (insertion sort keeps the
// module dependency-free and deterministic). Returns the copied count.
pub fn sortedCopy(p: *const Perf, out: []i64) usize {
    var n = p.n;
    if (n > out.len) n = out.len;
    var i: usize = 0;
    while (i < n) : (i += 1) out[i] = p.samples[i];

    i = 1;
    while (i < n) : (i += 1) {
        const v = out[i];
        var j = i;
        while (j > 0 and out[j - 1] > v) : (j -= 1) {
            out[j] = out[j - 1];
        }
        out[j] = v;
    }
    return n;
}

// Nearest-rank percentile over an ascending array; pct is 0..100. Rank is
// ceil(pct * n / 100), clamped to [1, n]. Empty input returns 0.
pub fn percentileSorted(sorted: []const i64, pct: i32) i64 {
    if (sorted.len == 0) return 0;
    const n: i64 = @intCast(i64, sorted.len);
    const p: i64 = @intCast(i64, pct);
    var rank: i64 = (p * n + 99) / 100;
    if (rank < 1) rank = 1;
    if (rank > n) rank = n;
    return sorted[@intCast(usize, rank - 1)];
}

// One line, no trailing newline: `perf frames=N p50=Xms p95=Yms p99=Zms`.
pub fn format(p: *const Perf, out: []u8) []const u8 {
    var scratch: [MAX_FRAMES]i64 = undefined;
    const n = sortedCopy(p, scratch[0..]);
    const p50 = percentileSorted(scratch[0..n], 50);
    const p95 = percentileSorted(scratch[0..n], 95);
    const p99 = percentileSorted(scratch[0..n], 99);

    var at: usize = 0;
    text_scan.appendText(out, &at, "perf frames=");
    text_scan.appendInt(out, &at, @intCast(i64, n));
    text_scan.appendText(out, &at, " p50=");
    text_scan.appendInt(out, &at, p50);
    text_scan.appendText(out, &at, "ms p95=");
    text_scan.appendInt(out, &at, p95);
    text_scan.appendText(out, &at, "ms p99=");
    text_scan.appendInt(out, &at, p99);
    text_scan.appendText(out, &at, "ms");
    return out[0..at];
}
