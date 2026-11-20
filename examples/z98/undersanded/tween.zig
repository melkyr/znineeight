// tween.zig — UNDERSANDED UI tween accumulator (spec §29).
//
// Raw high-res ticks are accumulated and divided once; a tween updated from
// truncated per-frame deltas would never advance when samples repeat. Equal
// consecutive samples therefore leave `pos` unchanged (and `done` clear until
// TWEEN_MS has actually elapsed). u64 arithmetic stays in locals.

const std_time = @import("std_time.zig");

pub const TWEEN_MS: u32 = 180;

pub const Tween = struct {
    from: i32,
    to: i32,
    pos: i32,
    start: u64,
    done: i32,
};

pub fn tweenBegin(tw: *Tween, from: i32, to: i32, now: u64) void {
    tw.from = from;
    tw.to = to;
    tw.pos = from;
    tw.start = now;
    tw.done = 0;
}

pub fn tweenStart(tw: *Tween, from: i32, to: i32) void {
    tweenBegin(tw, from, to, std_time.highRes());
}

pub fn tweenAdvance(tw: *Tween, now: u64, freq: u64) void {
    if (freq == 0) {
        tw.done = 1;
        return;
    }
    const elapsed: u64 = now - tw.start;
    const ms: u64 = elapsed * @intCast(u64, 1000) / freq;
    if (ms >= @intCast(u64, TWEEN_MS)) {
        tw.done = 1;
        tw.pos = tw.to;
        return;
    }
    const span: i32 = tw.to - tw.from;
    const msi: i32 = @intCast(i32, ms);
    const dur: i32 = @intCast(i32, TWEEN_MS);
    tw.pos = tw.from + span * msi / dur;
}
