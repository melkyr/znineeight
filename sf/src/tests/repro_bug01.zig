// repro_bug01.zig — reproduces the exact scenario from lexer.zig:lexerTestDiagnostics()
// Build: cd /workspace/znineeight && mkdir -p /tmp/repro_bug01 && ./zig0 -o /tmp/repro_bug01/out.c sf/src/tests/repro_bug01.zig
// Then: gcc -std=c89 -Iinclude -I/tmp/repro_bug01 /tmp/repro_bug01/*.c -o /tmp/repro_bug01/bin 2>&1
// Expected: C89 error "incompatible type for argument" on 2nd call to stderr_write.

const pal = @import("../pal.zig");
const Sand = @import("../allocator.zig").Sand;
const alloc_mod = @import("../allocator.zig");
const interner_mod = @import("../string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const sm_mod = @import("../source_manager.zig");
const SourceManager = sm_mod.SourceManager;
const diag_mod = @import("../diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const ErrorCode = diag_mod.ErrorCode;

// Same pattern as lexerTestDiagnostics(): 3 prior calls, then 2x fn([]const u8) with literals
pub fn main() void {
    var arena_buf: [8192]u8 = undefined;
    var sand = alloc_mod.sandInit(arena_buf[0..]);
    var interner = interner_mod.stringInternerInit(&sand, 4);
    var source_man = sm_mod.sourceManagerInit(&sand);
    var diag = diag_mod.diagnosticCollectorInit(&sand, &source_man, &interner);

    // Bug: 2nd literal call to fn([]const u8) after prior calls
    diag_mod.diagnosticCollectorAdd(&diag, 0, 0, 0, 0, 0, "first");
    diag_mod.diagnosticCollectorAdd(&diag, 0, 0, 0, 0, 0, "second");
}
