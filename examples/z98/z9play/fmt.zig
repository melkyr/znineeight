// fmt.zig — z9play M5: minimal player-local formatter (CLI status line).
//
// Spec §3 deliberately does NOT grow std with `std.fmt.bufPrint`; the CLI/TUI
// needs only integers plus fixed strings, so this module renders them by hand.
// Two entry points:
//
//   mmss(buf, ms)                      -> `MM:SS` (minutes zero-padded to two
//                                         digits, wider when >= 100; seconds
//                                         always two digits).
//   statusLine(buf, pos, dur, vol)     -> fixed-width `\r`-ready line
//                                         `00:42 / 03:15  vol 80%  [####----]`.
//
// statusLine layout (byte-stable; asserted by tests/fmt_test.zig):
//
//   <pos> / <dur>  vol <vol>%  [<bar>]
//
//   dur : `MM:SS`, or `--` when `dur_ms == 0` (guard: no progress denominator).
//   bar : 20 chars between `[` and `]`; floor(pos_ms * 20 / dur_ms) are `#`,
//         the rest `-`; clamped to the full bar when `pos_ms >= dur_ms`; all
//         `-` when `dur_ms == 0`.
//
// All arithmetic is integer (manual decimal placement, no float/format API).
// Z98 rules: free functions only, no generics, strict `@intCast`, no `switch`,
// string literals via `var s: []const u8 = "...";`.

// Upper bounds for the rendered outputs. `MMSS_MAX` is the widest `MM:SS`
// (u64 ms: 15-minute digits + ':' + 2); `STATUS_LINE_MAX` covers the full line.
pub const MMSS_MAX: usize = 20;
pub const STATUS_LINE_MAX: usize = 96;

const BAR_WIDTH: usize = 20;

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

// Decimal, unsigned, no padding; zero prints a single `0`.
fn putU64(out: []u8, pos: *usize, v: u64) void {
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    var x: u64 = v;
    if (x == 0) {
        putByte(out, pos, '0');
        return;
    }
    while (x > 0) {
        tmp[n] = @intCast(u8, x % 10) + '0';
        x = x / 10;
        n += 1;
    }
    var i: usize = 0;
    while (i < n) : (i += 1) {
        putByte(out, pos, tmp[n - 1 - i]);
    }
}

// Zero-padded two-digit decimal (00..=99).
fn put2(out: []u8, pos: *usize, v: u64) void {
    if (v < 10) putByte(out, pos, '0');
    putU64(out, pos, v);
}

// `ms` as `MM:SS`; minutes at least two digits, seconds always two.
pub fn mmss(buf: []u8, ms: u64) []const u8 {
    var total_s: u64 = ms / 1000;
    var mins: u64 = total_s / 60;
    var secs: u64 = total_s % 60;
    var pos: usize = 0;
    if (mins < 10) putByte(buf, &pos, '0');
    putU64(buf, &pos, mins);
    putByte(buf, &pos, ':');
    put2(buf, &pos, secs);
    return buf[0..pos];
}

// One fixed-width `\r`-ready status line into `buf`; returns the used prefix.
// `buf` must be at least `STATUS_LINE_MAX` bytes. `vol` is a percent (0..100).
pub fn statusLine(buf: []u8, pos_ms: u64, dur_ms: u64, vol: u8) []const u8 {
    var pos_buf: [MMSS_MAX]u8 = undefined;
    var dur_buf: [MMSS_MAX]u8 = undefined;
    var pos_s: []const u8 = mmss(pos_buf[0..], pos_ms);
    var dur_s: []const u8 = undefined;
    if (dur_ms == 0) {
        var dash: []const u8 = "--";
        dur_s = dash;
    } else {
        dur_s = mmss(dur_buf[0..], dur_ms);
    }

    // Filled cells: floor of the true ratio times the bar width; full when the
    // position has reached or passed the duration, empty with no duration.
    var filled: usize = 0;
    if (dur_ms > 0) {
        if (pos_ms >= dur_ms) {
            filled = BAR_WIDTH;
        } else {
            filled = @intCast(usize, (pos_ms * @intCast(u64, BAR_WIDTH)) / dur_ms);
        }
    }

    var pos: usize = 0;
    putStr(buf, &pos, pos_s);
    putStr(buf, &pos, " / ");
    putStr(buf, &pos, dur_s);
    putStr(buf, &pos, "  vol ");
    putU64(buf, &pos, @intCast(u64, vol));
    putByte(buf, &pos, '%');
    putStr(buf, &pos, "  [");
    var i: usize = 0;
    while (i < BAR_WIDTH) : (i += 1) {
        if (i < filled) {
            putByte(buf, &pos, '#');
        } else {
            putByte(buf, &pos, '-');
        }
    }
    putByte(buf, &pos, ']');
    return buf[0..pos];
}
