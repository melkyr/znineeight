// taskptr_field_store_xmod — COMPILE-FAIL fixture (dump rc=3, 0 `.c`, error[3043]).
//
// T0b residual. `s.tasks[0].cancel_requested = true` where `s.tasks` is `[*]*Task`:
// `lowerFieldStore` (sf/src/lower.zig:1740-1831) resolves the field-store base to the
// `[*]*Task` many-pointer type and unwraps exactly ONE pointer level (:1744-1748),
// leaving `*Task` — NOT a struct — so none of the struct/slice/tagged-union/union arms
// match and the final `else` calls `iceFieldStoreUnsupported` (:1827) →
// `error[3043]: internal: unsupported field-store base (node N)`.
//
// Contrast (both compile clean, confirmed): binding the element first
// (`var p = s.tasks[0]; p.cancel_requested = true;`) works, because the store base is
// then a single `*Task` whose one-level unwrap yields the `Task` struct.
//
// Compile gate: dump rc=3, exactly ONE `error[3043]`, ZERO `.c` emitted. Declared in
// `repro/mi_matrix/EXPECTED_FAIL.md`.
//
// Declared by Task 0g; the fix (if any) is Task 0h. NOT fixed here.
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
