// console.zig — application-level console abstraction for z9play (M5b Task 1).
//
// Blueprint §2.2 / spec §5 (amended 2026-10-16): the `Console` vtable plus the
// complete `Key` union. It lives in the player's own `platform/` (not std) so
// backends can be swapped (Linux termios/ANSI, Win9x conhost in M6) and tested
// independently. This module holds the contract only — no platform code and no
// `@cInclude`.
//
// Assembly note (compiler defect D8): a backend must NOT expose a function that
// *returns* `Console`. A function whose return type is the vtable struct trips
// D8 in multi-module builds (the emitter writes the error-union-returning
// function-pointer typedefs before the error-union typedefs they reference,
// producing invalid C89). Backends therefore expose their vtable entries as
// public free functions and the caller assembles the `Console` literal inline,
// exactly as the M4 `AudioOut` vtable is assembled. See
// examples/torrent_example_defects.md (D8).
//
// D1 note: `readKey_fn` returns `Key` directly (`.none` when nothing is
// pending) rather than `?Key`. Seed v98 rejects the function→function-pointer
// coercion for an optional-of-aggregate return and mis-emits the C89 typedef
// order; `Key.none` is the in-band sentinel workaround. See D1 in
// examples/torrent_example_defects.md.
//
// Pure Z98: free functions only (no method syntax), no generics. The vtable is
// a plain struct of function pointers; callers invoke them as
// `c.clear_fn(c.state)`. Every operation takes the opaque backend state as
// `*void`; the backend casts it to its own concrete state struct.

// One key event. `none` is the "nothing pending" result of `readKey` (there is
// no optional-of-aggregate function-pointer return in the vtable: seed v98
// rejects and mis-emits `fn (*void) ?Key` — compiler defect D1; the in-band
// sentinel is the documented workaround). `char` is one raw byte (printable /
// control / `j k a d n p s space + - q`, etc.); `sigint` is Ctrl-C (Linux
// SIGINT; the Win9x console-control handler in M6); the arrow variants are the
// decoded ESC-introduced cursor sequences; `enter` is CR/LF; `esc` is a bare
// ESC (or an unrecognised escape sequence).
pub const Key = union(enum) {
    none,       // no key ready (readKey "nothing pending"; D1 workaround)
    char: u8,
    sigint,
    up, down, left, right,
    enter,
    esc,
};

// The console vtable. A backend module exposes the nine operations as public
// free functions whose signatures match the fields below exactly; the caller
// fills the literal and sets `state` to its own backend state struct.
pub const Console = struct {
    clear_fn:       fn (*void) void,
    setCursor_fn:   fn (*void, u16, u16) void,
    writeStr_fn:    fn (*void, []const u8) void,
    readKey_fn:     fn (*void) Key,   // returns Key.none when no key is ready
    enterRaw_fn:    fn (*void) void,
    leaveRaw_fn:    fn (*void) void,
    width_fn:       fn (*void) u16,
    height_fn:      fn (*void) u16,
    cursorShow_fn:  fn (*void, bool) void,
    state:          *void,
};
