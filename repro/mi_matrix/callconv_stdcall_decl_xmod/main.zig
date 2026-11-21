// callconv_stdcall_decl_xmod — Track1 Task 3R use-site convention fixture.
//
// Operator ruling (Option B): a convention-bearing extern is self-describing
// WITHOUT a second, header-conflicting prototype. This fixture asserts the
// emitted `-osw` C:
//   GREEN (post-3R): NO `Z98_STDCALL` prototype for MessageBoxA, and the call
//                    uses an explicit cast to the convention-qualified
//                    fn-pointer typedef: `((FS_... )MessageBoxA)(...)`.
//   RED (pre-3R):    a forced `int Z98_STDCALL MessageBoxA(...)` prototype and
//                    a plain `MessageBoxA(...)` call.
// The `FS_...` typedef is emitted into zig_special_types.h because convention
// fn types are marked used on creation.
extern "stdcall" fn MessageBoxA(hwnd: *void, text: [*]const u8, cap: [*]const u8, typ: u32) i32;

pub fn main() void {
    if (@isWindows()) {
        _ = MessageBoxA(@ptrCast(*void, @intToPtr(*void, 0)), @ptrCast([*]const u8, @intToPtr([*]const u8, 0)), @ptrCast([*]const u8, @intToPtr([*]const u8, 0)), @intCast(u32, 0));
    }
}
