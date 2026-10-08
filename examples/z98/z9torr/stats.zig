// stats.zig — z9torr M3: 1 Hz progress line renderer.
//
// Spec §6. One call renders a single status line for the given `Stats` into
// `out_buf` and returns the used slice; the caller writes it (typically once a
// second). The `Stats` type is owned by `tracker.zig` (M2, operator ruling
// I1=A) — imported here, never redefined.
//
// Concrete format (fixed, byte-stable; asserted by testdata/stats_test.zig):
//
//   <P>.<p>% [<bar>] <d>.<dd>MB/<t>.<dd>MB <r>KB/s peers=<n> eta=<eta>
//
//   percent : downloaded / (downloaded + left) * 100, one decimal (per-mille
//             integer math, no float).
//   bar     : 40 chars between '[' and ']'; floor(pct * 40 / 1000) are '#'.
//   MB pair : downloaded and total = downloaded + left, each
//             `whole . frac` with frac = (bytes % 1048576) * 100 / 1048576
//             (two digits, zero-padded), `MB`.
//   KB/s    : average of the 5-sample rolling window `window_down`, divided by
//             1024 (integer, truncated). `window_up` feeds the mirrored upload
//             path; `window_idx` is the sampler's write cursor (Task 3).
//   eta     : `left / rate` seconds => `Ss` (< 1 min), `MmSSs` (< 1 h), or
//             `HhMMmSSs`; `--` when the rate is 0 (guard against div-by-zero).
//
// All arithmetic is integer; the decimal points are placed manually. Elapsed /
// time math is unsigned (monotonic ms via `std.time.ticksMs` at the call site).
//
// Z98 rules: free functions only, no generics/`anytype`/`@Type`, strict
// `@intCast`, every `switch` needs `else` (none here), string literals via
// `var s: []const u8 = "...";`. D2: the only slice is `[]u8`/`[]const u8`
// (primitive element); no slice of a synthetic type.

const parse = @import("std_parse.zig");
const tracker = @import("tracker.zig");

// Upper bound on a rendered line. The format is well under this; Task 3 should
// size its line buffer as at least `STATS_LINE_MAX`.
pub const STATS_LINE_MAX: usize = 256;

const BAR_WIDTH: u32 = 40;
const MB: u64 = 1048576;

fn putByte(out: []u8, pos: *usize, c: u8) void {
    out[pos.*] = c;
    pos.* += 1;
}

fn putStr(out: []u8, pos: *usize, s: []const u8) void {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        out[pos.*] = s[i];
        pos.* += 1;
    }
}

fn putU64(out: []u8, pos: *usize, v: u64) void {
    var tmp: [20]u8 = undefined;
    var r: []u8 = parse.utoa64(tmp[0..], v);
    putStr(out, pos, r);
}

// Zero-padded two-digit decimal fraction (0..99).
fn putFrac2(out: []u8, pos: *usize, frac: u64) void {
    if (frac < 10) putByte(out, pos, '0');
    putU64(out, pos, frac);
}

// Render `bytes` as `<whole>.<frac2>MB` (integer math, manual point).
fn putMB(out: []u8, pos: *usize, bytes: u64) void {
    var whole: u64 = bytes / MB;
    var frac: u64 = (bytes % MB) * 100 / MB;
    putU64(out, pos, whole);
    putByte(out, pos, '.');
    putFrac2(out, pos, frac);
    putStr(out, pos, "MB");
}

// Render the ETA suffix from `left` bytes at `rate` bytes/s. `rate == 0` emits
// `eta=--` (safe placeholder; no division).
fn putEta(out: []u8, pos: *usize, left: u64, rate: u64) void {
    putStr(out, pos, "eta=");
    if (rate == 0) {
        putStr(out, pos, "--");
        return;
    }
    var secs: u64 = left / rate;
    if (secs < 60) {
        putU64(out, pos, secs);
        putByte(out, pos, 's');
    } else if (secs < 3600) {
        putU64(out, pos, secs / 60);
        putByte(out, pos, 'm');
        putFrac2(out, pos, secs % 60);
        putByte(out, pos, 's');
    } else {
        var rem: u64 = secs % 3600;
        putU64(out, pos, secs / 3600);
        putByte(out, pos, 'h');
        putFrac2(out, pos, rem / 60);
        putByte(out, pos, 'm');
        putFrac2(out, pos, rem % 60);
        putByte(out, pos, 's');
    }
}

// Render one progress line into `out_buf`; return the used prefix (a slice of
// `out_buf`). `out_buf` must be at least `STATS_LINE_MAX` bytes.
pub fn statsRender(s: *tracker.Stats, out_buf: []u8) []const u8 {
    var pos: usize = 0;

    var total: u64 = s.downloaded + s.left;

    // Percent in per-mille (integer, one manual decimal point).
    var p1000: u64 = 0;
    if (total > 0) {
        if (s.downloaded >= total) {
            p1000 = 1000;
        } else {
            p1000 = (s.downloaded * 1000) / total;
        }
    }
    putU64(out_buf, &pos, p1000 / 10);
    putByte(out_buf, &pos, '.');
    putU64(out_buf, &pos, p1000 % 10);
    putByte(out_buf, &pos, '%');
    putByte(out_buf, &pos, ' ');

    // 40-char progress bar.
    var filled: u64 = (p1000 * @intCast(u64, BAR_WIDTH)) / 1000;
    putByte(out_buf, &pos, '[');
    var i: usize = 0;
    while (i < BAR_WIDTH) : (i += 1) {
        if (@intCast(u64, i) < filled) {
            putByte(out_buf, &pos, '#');
        } else {
            putByte(out_buf, &pos, '-');
        }
    }
    putByte(out_buf, &pos, ']');
    putByte(out_buf, &pos, ' ');

    // downloaded / total in MB.
    putMB(out_buf, &pos, s.downloaded);
    putByte(out_buf, &pos, '/');
    putMB(out_buf, &pos, total);
    putByte(out_buf, &pos, ' ');

    // Rate: mean of the 5-sample rolling window (bytes/s), widened to u64.
    var sum: u64 = 0;
    var k: usize = 0;
    while (k < 5) : (k += 1) {
        sum += @intCast(u64, s.window_down[k]);
    }
    var rate: u64 = sum / 5;
    putU64(out_buf, &pos, rate / 1024);
    putStr(out_buf, &pos, "KB/s peers=");

    putU64(out_buf, &pos, @intCast(u64, s.peer_count));
    putByte(out_buf, &pos, ' ');
    putEta(out_buf, &pos, s.left, rate);

    return out_buf[0..pos];
}
