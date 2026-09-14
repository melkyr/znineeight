// Off-corpus marker fixture (Task 3, Amendment 3). Excluded from the corpus
// universe by the `known_excluded` guard in scripts/corpus/list_corpus_dirs.sh.
//
// Suspension-graph shape:
//   leaf        -> @asyncSuspend (direct seed)
//   mid         -> leaf          (cross-function propagation)
//   top         -> mid
//   explicit_only -> @asyncSuspend
//   ping        -> leaf, pong    (SCC entry: a cycle member calls a suspending fn)
//   pong        -> ping
// Expected SUSP set: leaf, mid, top, explicit_only, ping, pong. `main` is not
// suspending (it calls none of them).

pub fn leaf() void {
    @asyncSuspend(null);
}
pub fn mid() void {
    leaf();
}
pub fn top() void {
    mid();
}
pub fn explicit_only() void {
    @asyncSuspend(null);
}
pub fn ping() void {
    leaf();
    pong();
}
pub fn pong() void {
    ping();
}

pub fn main() void {
}
