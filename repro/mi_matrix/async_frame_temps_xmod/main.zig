// Regression for Fix F1 (Track 2 async compiler core): P2's authoritative
// frame-size reservation must be a conservative upper bound over the temps P3
// finds live across a suspension.
//
// The three `foo(a)` results are defined before `bar(1)` suspends and read
// after it, so P3 marks them live-across. Before the fix, P2 reserved only
// `var_decl` locals, so `precise > frame_sizes[caller]` and P3 panicked.
//
// RED (pre-fix, fixed point eda943dc): --dump-c89 rc=133
//   `panic: async frame layout exceeds authoritative frame size`, 0 `.c`.
// GREEN (post-fix): --dump-c89 rc=0, 4 `.c`, gcc -m32 -std=c89 -O0 -Wall clean,
//   self-contained link, run rc=0 with the arithmetic self-check below.
//
// caller(5) = foo(5)*3 + bar(1) = 15 + 15 + 15 + 1 = 46.

fn bar(x: i32) i32 { @asyncSuspend(null); return x; }
fn foo(x: i32) i32 { return x * 3; }
fn caller(a: i32) i32 { return foo(a) + foo(a) + foo(a) + bar(1); }

pub fn main() void {
    var r: i32 = caller(5);
    if (r != 46) {
        @panic("async frame temps mismatch");
    }
}
