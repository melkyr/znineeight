// Off-corpus cross-module marker fixture (Task 3 review-fix, Finding 2).
// Excluded from the corpus universe by the `known_excluded` guard in
// scripts/corpus/list_corpus_dirs.sh.
//
// Cross-module call-edge shape:
//   lib.leaf  -> @asyncSuspend (direct seed)
//   xcall     -> lib.leaf      (cross-module field_access callee; main module)
// Propagation must mark the main-module caller `xcall` as suspending via the
// absolute-key edge (mod_main << 32 | xcall) <- (mod_lib << 32 | leaf).
// Expected SUSP set: lib.leaf, main.xcall. `main` is not suspending.

const lib = @import("lib.zig");

pub fn xcall() void {
    lib.leaf();
}

pub fn main() void {
}
