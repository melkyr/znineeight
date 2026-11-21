// taskptr_field_store_xmod — GREEN fixture (compile + run rc=0).
//
// T0b residual, FIXED in Task 0h. `s.tasks[0].cancel_requested = true` where
// `s.tasks` is `[*]*Task`: `lowerFieldStore` (sf/src/lower.zig) now detects that
// the indexed element (`s.tasks[i]`) is itself a pointer and loads the element
// pointer, so the field store resolves to the pointee `Task` struct instead of
// unwrapping one level to `*Task` and hitting
// `error[3043]: internal: unsupported field-store base`. The in-tree
// `std.async.cancelAll` local-`*Task` workaround is removed (direct form).
//
// Compile gate: dump rc=0 / gcc-clean / link rc=0 / run rc=0 (no stdout).
// Removed from `repro/mi_matrix/EXPECTED_FAIL.md`.
//
// Declared by Task 0g; FIXED by Task 0h.
const Task = struct {
    id: u32,
    cancel_requested: bool,
};

const Scheduler = struct {
    tasks: [*]*Task,
};

pub fn main() void {
    var t0: Task = .{ .id = 1, .cancel_requested = false };
    var t1: Task = .{ .id = 2, .cancel_requested = false };
    var arr: [2]*Task = undefined;
    arr[0] = &t0;
    arr[1] = &t1;
    var s = Scheduler{ .tasks = @ptrCast([*]*Task, &arr[0]) };
    s.tasks[0].cancel_requested = true;
    if (!t0.cancel_requested) { @panic("taskptr_field_store_xmod: field store did not take effect"); }
}
