// backend.zig — z9gb platform backend table (P1).
//
// The emulator drives presentation, input, audio, and lifecycle through this
// five-field record. `state` is opaque `*void`: no HWND, COM, Win32, or
// DirectX type appears here or in the headless backend. Pure Z98 free
// functions only; no methods, generics, or anytype.

pub const InputState = struct {
    // Same bit order as emuSetButtons: 0 right, 1 left, 2 up, 3 down,
    // 4 a, 5 b, 6 select, 7 start.
    buttons: u8,
    quit: bool,
};

pub const Platform = struct {
    state: *void,
    open_fn: fn (*void, u32, u32, u32) bool,   // width, height, scale
    present_fn: fn (*void, []const u32) void,  // 160*144 RGB32
    poll_fn: fn (*void, *InputState) bool,
    audio_fn: fn (*void, []const i16) void,    // stereo interleaved
    close_fn: fn (*void) void,
};

fn noopOpen(state: *void, width: u32, height: u32, scale: u32) bool {
    _ = state;
    _ = width;
    _ = height;
    _ = scale;
    return false;
}

fn noopPresent(state: *void, frame: []const u32) void {
    _ = state;
    _ = frame;
}

fn noopPoll(state: *void, input: *InputState) bool {
    _ = state;
    _ = input;
    return false;
}

fn noopAudio(state: *void, samples: []const i16) void {
    _ = state;
    _ = samples;
}

fn noopClose(state: *void) void {
    _ = state;
}

var g_noop_platform: Platform = Platform{
    .state = @intToPtr(*void, 0),
    .open_fn = noopOpen,
    .present_fn = noopPresent,
    .poll_fn = noopPoll,
    .audio_fn = noopAudio,
    .close_fn = noopClose,
};

// Null-safe fallback table: the callbacks ignore the opaque state, so a null
// state is safe. Callers that have no backend yet use this instead of null
// function pointers.
pub fn platformNoop() *Platform {
    return &g_noop_platform;
}
