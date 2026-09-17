// opt_void_extern_xmod — Plan A Task 4b-I control: optional `*void` parameter
// in an `extern "c"` declaration.
//
// The C prototype this declaration binds to is
//
//     void take_void(void* p);   /* null = 0 */
//
// Unlike `?fn(...)`, a `?*void` extern parameter lowers correctly today: the
// call site ABI-unwraps the optional to a plain `void*` (`p.has_value ?
// p.value : NULL`) and a null argument is emitted as `(void*)(NULL)`. This
// fixture is the GREEN control for the Task 4b-I investigation — it pins the
// correct half of the premise.
//
// Emission-only: the C definition of `take_void` lives on the C side, so the
// gate is gcc compiling the emitted C.
//
// GREEN contract: the emitted call site passes `void*` (null = `(void*)(NULL)`)
// and gcc compiles the emitted C clean.

const std = @import("std");

extern "c" fn take_void(p: ?*void) void;

pub fn main() void {
    var x: i32 = 5;
    var vp: *void = @ptrCast(*void, &x);
    take_void(vp);
    take_void(null);
    std.io.printInt(@intCast(i32, 1));
    std.io.writeByte('\n');
}
