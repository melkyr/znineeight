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
