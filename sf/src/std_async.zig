// std_async.zig — concrete cooperative task scheduler + per-task child-frame
// pool for Z98 coroutines (Track 3, std.async). No generics, no module-scope
// mutable globals: the caller supplies all storage.
//
// Frame model (umbrella m1166/m1172):
//   - The root frame lives in the caller-owned `buf` passed to @asyncInit and
//     is OUTSIDE the pool.
//   - `Context` owns the caller-sized pool for CHILD frames only; it is a
//     per-task LIFO frame stack (bump pointer + mark), not a shared allocator.
//   - `contextAlloc` advances the bump; `contextMark`/`contextRelease` bracket a
//     child so it is reclaimed exactly when it returns. Exhaustion returns
//     `error.OutOfFrame` and sets the sticky `oom` flag; it is never a crash.
//
// Scheduler dispatch (Amendment 7): `Task` stores NO step pointer. `tick`/
// `waitAll` self-dispatch with `@asyncResume(t.frame, t.arg)`, which loads the
// hidden pointer-sized step word the compiler writes at frame offset 0. Track 3
// therefore DEPENDS on the landed Track 2 compiler core for `@asyncResume` and
// the frame/`ctx` layout. (The historical `fn_ptr_struct_field` gap is CLOSED;
// `StepFn` remains the documented `__async_step_<f>` ABI alias only.)

/// Cooperative task lifecycle.
pub const TaskState = enum(u8) {
    ready = 0,
    running = 1,
    suspended = 2,
    done = 3,
    cancelled = 4,
};

/// Pool exhaustion, surfaced by the scheduler free functions.
pub const FrameError = error{OutOfFrame};

/// The documented `__async_step_<f>` ABI alias: `fn(frame, arg) ?*void`; null =
/// terminal (done), non-null = still yielded. Documentation only — the scheduler
/// never stores or passes a `StepFn` (Amendment 7 self-dispatch via
/// `@asyncResume(t.frame, t.arg)`); Track 3 fixtures set it as the first `Frame`
/// field so it lands at frame offset 0.
pub const StepFn = fn(frame: *void, arg: ?*void) ?*void;

// Branch (a) — DECIDED (operator ruling m1662). Context occupies the first 12
// bytes of the caller's pool buffer; the pool bytes follow: `pool_base =
// ctx + 12` (DERIVED — never stored). The by-value Context + separate
// `pool_base` alternative is REJECTED (redoes landed Track 2 work).
/// Per-task child-frame pool. The caller declares `var buf: [N]u8 = undefined;`
/// and the Context sits at the HEAD of that buffer; `capacity` is the usable
/// bytes AFTER the 12-byte header; `oom` is sticky for the pool's lifetime.
pub const Context = struct {
    used: usize,       // @ ctx+0
    capacity: usize,   // @ ctx+4 — usable bytes AFTER the 12-byte header
    oom: bool,         // @ ctx+8 — sticky
};

/// Places the Context at the head of `buf` and returns a pointer into `buf`.
pub fn contextInit(buf: []u8) *Context {
    var c: *Context = @ptrCast(*Context, buf.ptr);
    c.used = 0;
    c.capacity = buf.len - 12;
    c.oom = false;
    return c;
}

pub fn contextAlloc(ctx: *Context, size: usize) FrameError![*]u8 {
    if (ctx.used + size > ctx.capacity) {
        ctx.oom = true;
        return error.OutOfFrame;
    }
    var base: [*]u8 = @ptrCast([*]u8, ctx) + 12;
    var p: [*]u8 = base + ctx.used;
    ctx.used += size;
    return p;
}

pub fn contextMark(ctx: *Context) usize {
    return ctx.used;
}

pub fn contextRelease(ctx: *Context, mark: usize) void {
    ctx.used = mark;
}
