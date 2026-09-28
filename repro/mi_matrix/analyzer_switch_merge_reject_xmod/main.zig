// analyzer_switch_merge_reject_xmod — FX7 reject fixture for the diagnostics
// the switch-merge prong-name propagation now reaches (error[3035] class).
//
// After the FX7 fix, a name first assigned `arena_alloc(...)` in a switch prong
// is tracked after the switch as `AllocState.unknown` (conservative join), so a
// post-switch `arena_free` marks it freed and a SECOND post-switch free is a
// definite `error[3035]` double free. PRE (`1a258bd4`) the name was untracked
// after the merge and every free warned `warning[3039]` instead.
//
// The `nullDerefAfterSwitch` shape is the null control: a tracked optional set
// to null in a prong keeps the pre-existing `error[3034]` reject after the
// switch (the fix does not change the null map).
//
// Contract POST: dump rc=2, 0 `.c`, exactly
//   error[3035] x3  (two double-free sites: one after two frees, two after
//                    three frees)
//   error[3034] x1  (null deref after switch, control)
//   warning[3038] x2 (the leaked allocations at their prong exits)
// PRE: same error[3034], no error[3035], `warning[3039]` x5 and the
// prong-allocated names read untracked.
extern fn arena_alloc(size: usize) *u8;
extern fn arena_free(alloc: usize, p: *u8) void;

fn doubleFreeAfterSwitch(c: bool) void {
    var p: *u8 = undefined;
    switch (c) {
        true => {
            p = arena_alloc(8);
        },
        else => {},
    }
    arena_free(0, p);
    arena_free(0, p);
}

fn tripleFreeAfterSwitch(c: bool) void {
    var p: *u8 = undefined;
    switch (c) {
        true => {
            p = arena_alloc(8);
        },
        else => {},
    }
    arena_free(0, p);
    arena_free(0, p);
    arena_free(0, p);
}

fn nullDerefAfterSwitch(c: bool) void {
    var p: ?*i32 = null;
    switch (c) {
        true => {
            p = null;
        },
        else => {},
    }
    if (p.* == 0) {
    }
}

pub fn main() void {
    doubleFreeAfterSwitch(true);
    tripleFreeAfterSwitch(true);
    nullDerefAfterSwitch(true);
}
