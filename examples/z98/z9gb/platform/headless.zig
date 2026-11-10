// headless.zig — deterministic headless platform backend (P1).
//
// Imports no Win32 and no DirectX header: open/present/poll/audio/close are
// pure Z98. The frame is copied into a static snapshot; there is no window,
// no surface, and no C interop here.

const backend = @import("backend.zig");

const FRAME_W: u32 = 160;
const FRAME_H: u32 = 144;
const FRAME_PIXELS: usize = 160 * 144;

const HeadlessState = struct {
    width: u32,
    height: u32,
    scale: u32,
    closed: bool,
    audio_samples: usize,
};

var g_state: HeadlessState = HeadlessState{
    .width = 0,
    .height = 0,
    .scale = 0,
    .closed = false,
    .audio_samples = 0,
};
var g_snapshot: [160 * 144]u32 = undefined;

fn headlessOpen(state: *void, width: u32, height: u32, scale: u32) bool {
    var s = @ptrCast(*HeadlessState, state);
    s.width = width;
    s.height = height;
    s.scale = scale;
    s.closed = false;
    return width == FRAME_W and height == FRAME_H;
}

fn headlessPresent(state: *void, frame: []const u32) void {
    _ = state;
    var i: usize = 0;
    while (i < FRAME_PIXELS) : (i += 1) {
        if (i < frame.len) {
            g_snapshot[i] = frame[i];
        }
    }
}

fn headlessPoll(state: *void, input: *backend.InputState) bool {
    _ = state;
    _ = input;
    return false;
}

fn headlessAudio(state: *void, samples: []const i16) void {
    var s = @ptrCast(*HeadlessState, state);
    s.audio_samples += samples.len;
}

fn headlessClose(state: *void) void {
    var s = @ptrCast(*HeadlessState, state);
    s.closed = true;
}

var g_platform: backend.Platform = backend.Platform{
    .state = @ptrCast(*void, &g_state),
    .open_fn = headlessOpen,
    .present_fn = headlessPresent,
    .poll_fn = headlessPoll,
    .audio_fn = headlessAudio,
    .close_fn = headlessClose,
};

pub fn platformHeadless() *backend.Platform {
    return &g_platform;
}
