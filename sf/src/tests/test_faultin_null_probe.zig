// Task 9-Q-F fix round 1 probe: null-read fallback in sourceManagerFaultIn.
// Deterministically forces pal.readFile to fail at fault-in time by registering
// a transient file whose on-disk path does not exist, then exercises the
// diagnostics path (binary_search + offsets[line_idx]) to prove the fallback
// (empty content + single-0 offset stub) is bounds-safe (no UAF/OOB).
const alloc_mod = @import("../allocator.zig");
const sm_mod = @import("../source_manager.zig");
const diag_mod = @import("../diagnostics.zig");
const interner_mod = @import("../string_interner.zig");
const pal_mod = @import("../pal.zig");

pub fn main() void {
    var ca = alloc_mod.initCompilerAlloc();
    var interner = interner_mod.stringInternerInit(&ca.permanent, 4);
    var sm = sm_mod.sourceManagerInit(&ca.permanent);
    var diag = diag_mod.diagnosticCollectorInit(&ca.permanent, &sm, &interner);
    var src: []const u8 = "abc";
    var missing: []const u8 = "z98_9qf_null_probe_missing_file.zig";
    var fid = sm_mod.sourceManagerAddFileTransient(&sm, missing, src);

    var content = sm_mod.sourceManagerGetSourceContent(&sm, fid);
    if (content.len != @intCast(usize, 0)) @panic("null probe: expected empty fallback content");
    var offsets = sm_mod.sourceManagerGetLineOffsets(&sm, fid);
    if (offsets.len != @intCast(usize, 1)) @panic("null probe: expected single offset stub");
    if (offsets[0] != @intCast(u32, 0)) @panic("null probe: expected zero offset");
    var loc = sm_mod.sourceManagerGetLocation(&sm, fid, @intCast(u32, 0));
    if (loc.line != @intCast(u32, 1)) @panic("null probe: expected line 1");

    var msg: []const u8 = "null read fallback probe";
    _ = diag_mod.diagnosticCollectorAdd(&diag, @intCast(u8, 0), @intCast(u16, 2000), fid, @intCast(u32, 0), @intCast(u32, 1), msg);
    diag_mod.diagnosticCollectorPrintAll(&diag);

    var okmsg: []const u8 = "NULL_PROBE_OK\n";
    pal_mod.stderr_write(okmsg);
}
