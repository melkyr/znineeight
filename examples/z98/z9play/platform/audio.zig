// audio.zig — application-level audio output abstraction for z9play (M4 Task 1).
//
// Blueprint §2.2: the `AudioOut` vtable. It lives in the player's own
// `platform/` (not std) so backends can be swapped (Linux OSS `/dev/dsp`,
// Win9x `waveOut`, hermetic WAV/null sink) and tested independently.
//
// Shape is exactly blueprint §2.2:
//   open_fn(rate, channels) -> opaque device context (*void)
//   write_fn(ctx, interleaved s16) -> samples accepted (blocks until consumed)
//   close_fn(ctx) -> release
//   drain_fn(ctx) -> block until buffered audio is played
//   state -> the device context open_fn returned
//
// Assembly note (compiler defect D8): a backend must NOT expose a function that
// *returns* `AudioOut`. A function whose return type is the vtable struct
// triggers D8 in multi-module builds (the emitter writes the error-union-
// returning function-pointer typedefs before the error-union typedefs they
// reference, producing invalid C89). Backends therefore expose their vtable
// entries as public free functions (`open`/`write`/`close`/`drain`) and the
// caller assembles the vtable literal inline. See
// examples/torrent_example_defects.md (D8).
//
// Pure Z98: free functions only (no method syntax), no generics. The vtable is
// a plain struct of function pointers; callers invoke them as
// `ao.write_fn(ao.state, samples)`.

const std = @import("std");

// Errors every backend must be able to report. OpenFailed: the device / sink
// could not be opened. WriteFailed: a write or flush failed. ConfigUnsupported:
// the requested sample rate / channel count is not supported (v1 accepts only
// 44100 and 48000). DeviceError: any other device-level failure (drain, etc.).
pub const AudioError = error{ OpenFailed, WriteFailed, ConfigUnsupported, DeviceError };

// The audio output vtable (blueprint §2.2). A backend module exposes the four
// operations as public free functions; the caller fills the literal and sets
// `state` to the context `open_fn` produced.
pub const AudioOut = struct {
    open_fn: fn (u32, u8) AudioError!*void,
    write_fn: fn (*void, []const i16) AudioError!usize,
    close_fn: fn (*void) void,
    drain_fn: fn (*void) AudioError!void,
    state: *void,
};
