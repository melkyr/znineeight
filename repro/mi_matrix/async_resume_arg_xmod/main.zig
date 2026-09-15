// async_resume_arg_xmod — Fix F4 #6: `@asyncResume(frame, arg)` must pass
// `ec[1]` as the step's second argument (the `?*void` optional).
//
// A hand-built frame's step word (offset 0) points at `probe`, whose signature
// matches the generic step type `fn(*void, ?*void) ?*void`. `@asyncResume`
// loads that word, casts it, and calls it with the caller's `arg`. `probe`
// reads the optional payload into the global `seen`; the program self-checks it.
//
// RED (pre-fix): lowering always passes a null optional, so `probe` takes the
// else branch and `@panic("resume arg dropped")` fires.
// GREEN (post-fix): `seen == 42`, no panic.

var seen: i32 = 0;

fn probe(frame: *void, arg: ?*void) ?*void {
    if (arg) |p| {
        var ip: *i32 = @ptrCast(*i32, p);
        seen = ip.*;
    } else {
        @panic("resume arg dropped");
    }
    return null;
}

const Frame = struct { step: usize };

pub fn main() void {
    var value: i32 = 42;
    var frame: Frame = undefined;
    frame.step = @ptrToInt(probe);
    var fp: *void = @ptrCast(*void, &frame);
    var p: *void = @ptrCast(*void, &value);
    var arg: ?*void = p;
    var more: ?*void = @asyncResume(fp, arg);
    if (more != null) {
        @panic("expected a completed probe");
    }
    if (seen != 42) {
        @panic("resume arg mismatch");
    }
}
